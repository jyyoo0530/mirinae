#!/usr/bin/env bash

mkdir -p ~/kafka
cd ~/kafka

curl -o kafkaoperator.yaml https://strimzi.io/install/latest?namespace=clt-datacenter

#deploy kafka-operator
kubectl create -f kafkaoperator.yaml -n clt-datacenter

#rm and create volume in node1
rm -rf /database/kafka
for i in 1 2 3
do
  mkdir -p /database/kafka/kafka$i
  chmod 777 /database/kafka/kafka$i
  mkdir -p /database/kafka/zookeeper$i
  chmod 777 /database/kafka/zookeeper$i
done

#create pv
for i in 1 2 3
do
cat <<EOF > ./kafka_pv$i.yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kafka-kafka-pv$i
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: kafka-kafka-sc
  local:
    path: /database/kafka/kafka$i
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - node1
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kafka-zookeeper-pv$i
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: kafka-zookeeper-sc
  local:
    path: /database/kafka/zookeeper$i
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - node1
---
EOF
done
kubectl apply -f kafka_pv1.yaml
kubectl apply -f kafka_pv2.yaml
kubectl apply -f kafka_pv3.yaml

#create sc
cat <<EOF > ./kafka_sc.yaml
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: kafka-kafka-sc
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: kafka-zookeeper-sc
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
kubectl apply -f kafka_sc.yaml -n clt-datacenter

#create cluster
cat <<EOF > ./kafka_cluster.yaml
---
apiVersion: kafka.strimzi.io/v1beta1
kind: Kafka
metadata:
  name: kafka-cluster
spec:
  kafka:
    version: 2.7.0
    replicas: 3
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
      - name: external
        port: 9094
        type: nodeport
        tls: false
    readinessProbe:
      initialDelaySeconds: 15
      timeoutSeconds: 5
    livenessProbe:
      initialDelaySeconds: 15
      timeoutSeconds: 5
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      log.message.format.version: "2.7"
      inter.broker.protocol.version: "2.7"
    storage:
      type: jbod
      volumes:
      - id: 0
        type: persistent-claim
        class: kafka-kafka-sc
        size: 1Gi
        deleteClaim: false
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: kafka-metrics
          key: kafka-metrics-config.yml
  zookeeper:
    replicas: 3
    readinessProbe:
      initialDelaySeconds: 15
      timeoutSeconds: 5
    livenessProbe:
      initialDelaySeconds: 15
      timeoutSeconds: 5
    storage:
      type: persistent-claim
      class: kafka-zookeeper-sc
      size: 1Gi
      deleteClaim: false
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: kafka-metrics
          key: zookeeper-metrics-config.yml
    config:
      quorum.auth: 2
  entityOperator:
    topicOperator: {}
    userOperator: {}
  kafkaExporter:
    topicRegex: ".*"
    groupRegex: ".*"
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: kafka-metrics
  labels:
    app: strimzi
data:
  kafka-metrics-config.yml: |
    # See https://github.com/prometheus/jmx_exporter for more info about JMX Prometheus Exporter metrics
    lowercaseOutputName: true
    rules:
    # Special cases and very specific rules
    - pattern: kafka.server<type=(.+), name=(.+), clientId=(.+), topic=(.+), partition=(.*)><>Value
      name: kafka_server_$1_$2
      type: GAUGE
      labels:
       clientId: "$3"
       topic: "$4"
       partition: "$5"
    - pattern: kafka.server<type=(.+), name=(.+), clientId=(.+), brokerHost=(.+), brokerPort=(.+)><>Value
      name: kafka_server_$1_$2
      type: GAUGE
      labels:
       clientId: "$3"
       broker: "$4:$5"
    - pattern: kafka.server<type=(.+), cipher=(.+), protocol=(.+), listener=(.+), networkProcessor=(.+)><>connections
      name: kafka_server_$1_connections_tls_info
      type: GAUGE
      labels:
        listener: "$2"
        networkProcessor: "$3"
        protocol: "$4"
        cipher: "$5"
    - pattern: kafka.server<type=(.+), clientSoftwareName=(.+), clientSoftwareVersion=(.+), listener=(.+), networkProcessor=(.+)><>connections
      name: kafka_server_$1_connections_software
      type: GAUGE
      labels:
        clientSoftwareName: "$2"
        clientSoftwareVersion: "$3"
        listener: "$4"
        networkProcessor: "$5"
    - pattern: "kafka.server<type=(.+), listener=(.+), networkProcessor=(.+)><>(.+):"
      name: kafka_server_$1_$4
      type: GAUGE
      labels:
       listener: "$2"
       networkProcessor: "$3"
    - pattern: kafka.server<type=(.+), listener=(.+), networkProcessor=(.+)><>(.+)
      name: kafka_server_$1_$4
      type: GAUGE
      labels:
       listener: "$2"
       networkProcessor: "$3"
    # Some percent metrics use MeanRate attribute
    # Ex) kafka.server<type=(KafkaRequestHandlerPool), name=(RequestHandlerAvgIdlePercent)><>MeanRate
    - pattern: kafka.(\w+)<type=(.+), name=(.+)Percent\w*><>MeanRate
      name: kafka_$1_$2_$3_percent
      type: GAUGE
    # Generic gauges for percents
    - pattern: kafka.(\w+)<type=(.+), name=(.+)Percent\w*><>Value
      name: kafka_$1_$2_$3_percent
      type: GAUGE
    - pattern: kafka.(\w+)<type=(.+), name=(.+)Percent\w*, (.+)=(.+)><>Value
      name: kafka_$1_$2_$3_percent
      type: GAUGE
      labels:
        "$4": "$5"
    # Generic per-second counters with 0-2 key/value pairs
    - pattern: kafka.(\w+)<type=(.+), name=(.+)PerSec\w*, (.+)=(.+), (.+)=(.+)><>Count
      name: kafka_$1_$2_$3_total
      type: COUNTER
      labels:
        "$4": "$5"
        "$6": "$7"
    - pattern: kafka.(\w+)<type=(.+), name=(.+)PerSec\w*, (.+)=(.+)><>Count
      name: kafka_$1_$2_$3_total
      type: COUNTER
      labels:
        "$4": "$5"
    - pattern: kafka.(\w+)<type=(.+), name=(.+)PerSec\w*><>Count
      name: kafka_$1_$2_$3_total
      type: COUNTER
    # Generic gauges with 0-2 key/value pairs
    - pattern: kafka.(\w+)<type=(.+), name=(.+), (.+)=(.+), (.+)=(.+)><>Value
      name: kafka_$1_$2_$3
      type: GAUGE
      labels:
        "$4": "$5"
        "$6": "$7"
    - pattern: kafka.(\w+)<type=(.+), name=(.+), (.+)=(.+)><>Value
      name: kafka_$1_$2_$3
      type: GAUGE
      labels:
        "$4": "$5"
    - pattern: kafka.(\w+)<type=(.+), name=(.+)><>Value
      name: kafka_$1_$2_$3
      type: GAUGE
    # Emulate Prometheus 'Summary' metrics for the exported 'Histogram's.
    # Note that these are missing the '_sum' metric!
    - pattern: kafka.(\w+)<type=(.+), name=(.+), (.+)=(.+), (.+)=(.+)><>Count
      name: kafka_$1_$2_$3_count
      type: COUNTER
      labels:
        "$4": "$5"
        "$6": "$7"
    - pattern: kafka.(\w+)<type=(.+), name=(.+), (.+)=(.*), (.+)=(.+)><>(\d+)thPercentile
      name: kafka_$1_$2_$3
      type: GAUGE
      labels:
        "$4": "$5"
        "$6": "$7"
        quantile: "0.$8"
    - pattern: kafka.(\w+)<type=(.+), name=(.+), (.+)=(.+)><>Count
      name: kafka_$1_$2_$3_count
      type: COUNTER
      labels:
        "$4": "$5"
    - pattern: kafka.(\w+)<type=(.+), name=(.+), (.+)=(.*)><>(\d+)thPercentile
      name: kafka_$1_$2_$3
      type: GAUGE
      labels:
        "$4": "$5"
        quantile: "0.$6"
    - pattern: kafka.(\w+)<type=(.+), name=(.+)><>Count
      name: kafka_$1_$2_$3_count
      type: COUNTER
    - pattern: kafka.(\w+)<type=(.+), name=(.+)><>(\d+)thPercentile
      name: kafka_$1_$2_$3
      type: GAUGE
      labels:
        quantile: "0.$4"
  zookeeper-metrics-config.yml: |
    # See https://github.com/prometheus/jmx_exporter for more info about JMX Prometheus Exporter metrics
    lowercaseOutputName: true
    rules:
    # replicated Zookeeper
    - pattern: "org.apache.ZooKeeperService<name0=ReplicatedServer_id(\\d+)><>(\\w+)"
      name: "zookeeper_$2"
      type: GAUGE
    - pattern: "org.apache.ZooKeeperService<name0=ReplicatedServer_id(\\d+), name1=replica.(\\d+)><>(\\w+)"
      name: "zookeeper_$3"
      type: GAUGE
      labels:
        replicaId: "$2"
    - pattern: "org.apache.ZooKeeperService<name0=ReplicatedServer_id(\\d+), name1=replica.(\\d+), name2=(\\w+)><>(Packets\\w+)"
      name: "zookeeper_$4"
      type: COUNTER
      labels:
        replicaId: "$2"
        memberType: "$3"
    - pattern: "org.apache.ZooKeeperService<name0=ReplicatedServer_id(\\d+), name1=replica.(\\d+), name2=(\\w+)><>(\\w+)"
      name: "zookeeper_$4"
      type: GAUGE
      labels:
        replicaId: "$2"
        memberType: "$3"
    - pattern: "org.apache.ZooKeeperService<name0=ReplicatedServer_id(\\d+), name1=replica.(\\d+), name2=(\\w+), name3=(\\w+)><>(\\w+)"
      name: "zookeeper_$4_$5"
      type: GAUGE
      labels:
        replicaId: "$2"
        memberType: "$3"


---
EOF
kubectl apply -f kafka_cluster.yaml -n clt-datacenter

## test by test-topic
cat <<EOF > ./kafka_topic.yaml
apiVersion: kafka.strimzi.io/v1beta1
kind: KafkaTopic
metadata:
  name: test-topic
  labels:
    strimzi.io/cluster: "kafka-cluster"
spec:
  partitions: 3
  replicas: 1
EOF
kubectl apply -f kafka_topic.yaml -n clt-datacenter
#find port of bootstrap
nodePort=$(kubectl get service kafka-cluster-kafka-external-bootstrap -n clt-datacenter -o=jsonpath='{.spec.ports[0].nodePort}{"\n"}')

#install(optional)
cd test
wget http://apache.mirror.cdnetworks.com/kafka/2.7.0/kafka_2.13-2.7.0.tgz
tar -xvzf kafka_2.13-2.7.0.tgz -C ~/kafka/test
mv ~/kafka/test/kafka_2.13-2.7.0/* ~/kafka/test
rm -rf ./kafka_2.13-2.7.0 && rm kafka_2.13-2.7.0.tgz
cd ..

#test using producer and consumer
~/kafka/test/bin/kafka-console-producer.sh --broker-list 30.0.2.31:$nodePort --topic test-topic
~/kafka/test/bin/kafka-console-consumer.sh --bootstrap-server 30.0.2.31:$nodePort --topic test-topic --from-beginning

## Adding monitoring tool
#download crd (optional)
curl -s https://raw.githubusercontent.com/coreos/prometheus-operator/master/bundle.yaml | sed -e '/[[:space:]]*namespace: [a-zA-Z0-9-]*$/s/namespace:[[:space:]]*[a-zA-Z0-9-]*$/namespace: clt-datacenter/' > prometheus-operator-deployment.yaml
#appply prometheus-operator
kubectl apply -f prometheus-operator-deployment.yaml -n clt-datacenter

#strimzi pod-monitor
cat <<EOF > ./strimzi-pod-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: cluster-operator-metrics
  labels:
    app: strimzi
spec:
  selector:
    matchLabels:
      strimzi.io/kind: cluster-operator
  namespaceSelector:
    matchNames:
      - clt-datacenter
  podMetricsEndpoints:
  - path: /metrics
    port: http
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: entity-operator-metrics
  labels:
    app: strimzi
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: entity-operator
  namespaceSelector:
    matchNames:
      - clt-datacenter
  podMetricsEndpoints:
  - path: /metrics
    port: healthcheck
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: bridge-metrics
  labels:
    app: strimzi
spec:
  selector:
    matchLabels:
      strimzi.io/kind: KafkaBridge
  namespaceSelector:
    matchNames:
      - clt-datacenter
  podMetricsEndpoints:
  - path: /metrics
    port: rest-api
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: kafka-resources-metrics
  labels:
    app: strimzi
spec:
  selector:
    matchExpressions:
      - key: "strimzi.io/kind"
        operator: In
        values: ["Kafka", "KafkaConnect", "KafkaConnectS2I", "KafkaMirrorMaker", "KafkaMirrorMaker2"]
  namespaceSelector:
    matchNames:
      - clt-datacenter
  podMetricsEndpoints:
  - path: /metrics
    port: tcp-prometheus
    relabelings:
    - separator: ;
      regex: __meta_kubernetes_pod_label_(strimzi_io_.+)
      replacement: $1
      action: labelmap
    - sourceLabels: [__meta_kubernetes_namespace]
      separator: ;
      regex: (.*)
      targetLabel: namespace
      replacement: $1
      action: replace
    - sourceLabels: [__meta_kubernetes_pod_name]
      separator: ;
      regex: (.*)
      targetLabel: kubernetes_pod_name
      replacement: $1
      action: replace
    - sourceLabels: [__meta_kubernetes_pod_node_name]
      separator: ;
      regex: (.*)
      targetLabel: node_name
      replacement: $1
      action: replace
    - sourceLabels: [__meta_kubernetes_pod_host_ip]
      separator: ;
      regex: (.*)
      targetLabel: node_ip
      replacement: $1
      action: replace
EOF
kubectl apply -f strimzi-pod-monitor.yaml -n clt-datacenter

#prometheus-rules
cat <<EOF > ./prometheus-rules.yaml
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  labels:
    role: alert-rules
    app: strimzi
  name: prometheus-k8s-rules
spec:
  groups:
  - name: kafka
    rules:
    - alert: KafkaRunningOutOfSpace
      expr: kubelet_volume_stats_available_bytes{persistentvolumeclaim=~"data-([0-9]+)?-(.+)-kafka-[0-9]+"} < 5368709120
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Kafka is running out of free disk space'
        description: 'There are only {{ $value }} bytes available at {{ $labels.persistentvolumeclaim }} PVC'
    - alert: UnderReplicatedPartitions
      expr: kafka_server_replicamanager_underreplicatedpartitions > 0
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Kafka under replicated partitions'
        description: 'There are {{ $value }} under replicated partitions on {{ $labels.kubernetes_pod_name }}'
    - alert: AbnormalControllerState
      expr: sum(kafka_controller_kafkacontroller_activecontrollercount) by (strimzi_io_name) != 1
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Kafka abnormal controller state'
        description: 'There are {{ $value }} active controllers in the cluster'
    - alert: OfflinePartitions
      expr: sum(kafka_controller_kafkacontroller_offlinepartitionscount) > 0
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Kafka offline partitions'
        description: 'One or more partitions have no leader'
    - alert: UnderMinIsrPartitionCount
      expr: kafka_server_replicamanager_underminisrpartitioncount > 0
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Kafka under min ISR partitions'
        description: 'There are {{ $value }} partitions under the min ISR on {{ $labels.kubernetes_pod_name }}'
    - alert: OfflineLogDirectoryCount
      expr: kafka_log_logmanager_offlinelogdirectorycount > 0
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Kafka offline log directories'
        description: 'There are {{ $value }} offline log directories on {{ $labels.kubernetes_pod_name }}'
    - alert: ScrapeProblem
      expr: up{kubernetes_namespace!~"openshift-.+",kubernetes_pod_name=~".+-kafka-[0-9]+"} == 0
      for: 3m
      labels:
        severity: major
      annotations:
        summary: 'Prometheus unable to scrape metrics from {{ $labels.kubernetes_pod_name }}/{{ $labels.instance }}'
        description: 'Prometheus was unable to scrape metrics from {{ $labels.kubernetes_pod_name }}/{{ $labels.instance }} for more than 3 minutes'
    - alert: ClusterOperatorContainerDown
      expr: count((container_last_seen{container="strimzi-cluster-operator"} > (time() - 90))) < 1 or absent(container_last_seen{container="strimzi-cluster-operator"})
      for: 1m
      labels:
        severity: major
      annotations:
        summary: 'Cluster Operator down'
        description: 'The Cluster Operator has been down for longer than 90 seconds'
    - alert: KafkaBrokerContainersDown
      expr: absent(container_last_seen{container="kafka",pod=~".+-kafka-[0-9]+"})
      for: 3m
      labels:
        severity: major
      annotations:
        summary: 'All `kafka` containers down or in CrashLookBackOff status'
        description: 'All `kafka` containers have been down or in CrashLookBackOff status for 3 minutes'
    - alert: KafkaContainerRestartedInTheLast5Minutes
      expr: count(count_over_time(container_last_seen{container="kafka"}[5m])) > 2 * count(container_last_seen{container="kafka",pod=~".+-kafka-[0-9]+"})
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: 'One or more Kafka containers restarted too often'
        description: 'One or more Kafka containers were restarted too often within the last 5 minutes'
  - name: zookeeper
    rules:
    - alert: AvgRequestLatency
      expr: zookeeper_avgrequestlatency > 10
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Zookeeper average request latency'
        description: 'The average request latency is {{ $value }} on {{ $labels.kubernetes_pod_name }}'
    - alert: OutstandingRequests
      expr: zookeeper_outstandingrequests > 10
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Zookeeper outstanding requests'
        description: 'There are {{ $value }} outstanding requests on {{ $labels.kubernetes_pod_name }}'
    - alert: ZookeeperRunningOutOfSpace
      expr: kubelet_volume_stats_available_bytes{persistentvolumeclaim=~"data-(.+)-zookeeper-[0-9]+"} < 5368709120
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Zookeeper is running out of free disk space'
        description: 'There are only {{ $value }} bytes available at {{ $labels.persistentvolumeclaim }} PVC'
    - alert: ZookeeperContainerRestartedInTheLast5Minutes
      expr: count(count_over_time(container_last_seen{container="zookeeper"}[5m])) > 2 * count(container_last_seen{container="zookeeper",pod=~".+-zookeeper-[0-9]+"})
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: 'One or more Zookeeper containers were restarted too often'
        description: 'One or more Zookeeper containers were restarted too often within the last 5 minutes. This alert can be ignored when the Zookeeper cluster is scaling up'
    - alert: ZookeeperContainersDown
      expr: absent(container_last_seen{container="zookeeper",pod=~".+-zookeeper-[0-9]+"})
      for: 3m
      labels:
        severity: major
      annotations:
        summary: 'All `zookeeper` containers in the Zookeeper pods down or in CrashLookBackOff status'
        description: 'All `zookeeper` containers in the Zookeeper pods have been down or in CrashLookBackOff status for 3 minutes'
  - name: entityOperator
    rules:
    - alert: TopicOperatorContainerDown
      expr: absent(container_last_seen{container="topic-operator",pod=~".+-entity-operator-.+"})
      for: 3m
      labels:
        severity: major
      annotations:
        summary: 'Container topic-operator in Entity Operator pod down or in CrashLookBackOff status'
        description: 'Container topic-operator in Entity Operator pod has been or in CrashLookBackOff status for 3 minutes'
    - alert: UserOperatorContainerDown
      expr: absent(container_last_seen{container="user-operator",pod=~".+-entity-operator-.+"})
      for: 3m
      labels:
        severity: major
      annotations:
        summary: 'Container user-operator in Entity Operator pod down or in CrashLookBackOff status'
        description: 'Container user-operator in Entity Operator pod have been down or in CrashLookBackOff status for 3 minutes'
    - alert: EntityOperatorTlsSidecarContainerDown
      expr: absent(container_last_seen{container="tls-sidecar",pod=~".+-entity-operator-.+"})
      for: 3m
      labels:
        severity: major
      annotations:
        summary: 'Container tls-sidecar Entity Operator pod down or in CrashLookBackOff status'
        description: 'Container tls-sidecar in Entity Operator pod have been down or in CrashLookBackOff status for 3 minutes'
  - name: connect
    rules:
    - alert: ConnectContainersDown
      expr: absent(container_last_seen{container=~".+-connect",pod=~".+-connect-.+"})
      for: 3m
      labels:
        severity: major
      annotations:
        summary: 'All Kafka Connect containers down or in CrashLookBackOff status'
        description: 'All Kafka Connect containers have been down or in CrashLookBackOff status for 3 minutes'
  - name: bridge
    rules:
    - alert: BridgeContainersDown
      expr: absent(container_last_seen{container=~".+-bridge",pod=~".+-bridge-.+"})
      for: 3m
      labels:
        severity: major
      annotations:
        summary: 'All Kafka Bridge containers down or in CrashLookBackOff status'
        description: 'All Kafka Bridge containers have been down or in CrashLookBackOff status for 3 minutes'
    - alert: AvgProducerLatency
      expr: strimzi_bridge_kafka_producer_request_latency_avg > 10
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Kafka Bridge average consumer fetch latency'
        description: 'The average fetch latency is {{ $value }} on {{ $labels.clientId }}'
    - alert: AvgConsumerFetchLatency
      expr: strimzi_bridge_kafka_consumer_fetch_latency_avg > 500
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Kafka Bridge consumer average fetch latency'
        description: 'The average consumer commit latency is {{ $value }} on {{ $labels.clientId }}'
    - alert: AvgConsumerCommitLatency
      expr: strimzi_bridge_kafka_consumer_commit_latency_avg > 200
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Kafka Bridge consumer average commit latency'
        description: 'The average consumer commit latency is {{ $value }} on {{ $labels.clientId }}'
    - alert: Http4xxErrorRate
      expr: strimzi_bridge_http_server_requestCount_total{code=~"^4..$", container=~"^.+-bridge", path !="/favicon.ico"} > 10
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: 'Kafka Bridge returns code 4xx too often'
        description: 'Kafka Bridge returns code 4xx too much ({{ $value }}) for the path {{ $labels.path }}'
    - alert: Http5xxErrorRate
      expr: strimzi_bridge_http_server_requestCount_total{code=~"^5..$", container=~"^.+-bridge"} > 10
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: 'Kafka Bridge returns code 5xx too often'
        description: 'Kafka Bridge returns code 5xx too much ({{ $value }}) for the path {{ $labels.path }}'
  - name: mirrorMaker
    rules:
    - alert: MirrorMakerContainerDown
      expr: absent(container_last_seen{container=~".+-mirror-maker",pod=~".+-mirror-maker-.+"})
      for: 3m
      labels:
        severity: major
      annotations:
        summary: 'All Kafka Mirror Maker containers down or in CrashLookBackOff status'
        description: 'All Kafka Mirror Maker containers have been down or in CrashLookBackOff status for 3 minutes'
  - name: kafkaExporter
    rules:
    - alert: UnderReplicatedPartition
      expr: kafka_topic_partition_under_replicated_partition > 0
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Topic has under-replicated partitions'
        description: 'Topic  {{ $labels.topic }} has {{ $value }} under-replicated partition {{ $labels.partition }}'
    - alert: TooLargeConsumerGroupLag
      expr: kafka_consumergroup_lag > 1000
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'Consumer group lag is too big'
        description: 'Consumer group {{ $labels.consumergroup}} lag is too big ({{ $value }}) on topic {{ $labels.topic }}/partition {{ $labels.partition }}'
    - alert: NoMessageForTooLong
      expr: changes(kafka_topic_partition_current_offset{topic!="__consumer_offsets"}[10m]) == 0
      for: 10s
      labels:
        severity: warning
      annotations:
        summary: 'No message for 10 minutes'
        description: 'There is no messages in topic {{ $labels.topic}}/partition {{ $labels.partition }} for 10 minutes'
---
EOF
kubectl apply -f prometheus-rules.yaml -n clt-datacenter

#prometheus
cat <<EOF > ./prometheus.yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-server
  labels:
    app: strimzi
rules:
  - apiGroups: [""]
    resources:
      - nodes
      - nodes/proxy
      - services
      - endpoints
      - pods
    verbs: ["get", "list", "watch"]
  - apiGroups:
      - extensions
    resources:
      - ingresses
    verbs: ["get", "list", "watch"]
  - nonResourceURLs: ["/metrics"]
    verbs: ["get"]

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus-server
  labels:
    app: strimzi

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-server
  labels:
    app: strimzi
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-server
subjects:
  - kind: ServiceAccount
    name: prometheus-server
    namespace: clt-datacenter

---
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: prometheus
  labels:
    app: strimzi
spec:
  replicas: 1
  serviceAccountName: prometheus-server
  podMonitorSelector:
    matchLabels:
      app: strimzi
  serviceMonitorSelector: {}
  resources:
    requests:
      memory: 400Mi
  enableAdminAPI: false
  ruleSelector:
    matchLabels:
      role: alert-rules
      app: strimzi
  alerting:
    alertmanagers:
    - namespace: clt-datacenter
      name: alertmanager
      port: alertmanager
  additionalScrapeConfigs:
    name: additional-scrape-configs
    key: prometheus-additional.yaml
---
EOF
kubectl apply -f prometheus.yaml -n clt-datacenter

# to do - add alerting

#deploy grafana
cat <<EOF > ./strimzi-zookeeper.json
{
  "__inputs": [
    {
      "name": "DS_PROMETHEUS",
      "label": "Prometheus",
      "description": "",
      "type": "datasource",
      "pluginId": "prometheus",
      "pluginName": "Prometheus"
    }
  ],
  "__requires": [
    {
      "type": "grafana",
      "id": "grafana",
      "name": "Grafana",
      "version": "7.3.7"
    },
    {
      "type": "panel",
      "id": "graph",
      "name": "Graph",
      "version": "5.0.0"
    },
    {
      "type": "datasource",
      "id": "prometheus",
      "name": "Prometheus",
      "version": "5.0.0"
    },
    {
      "type": "panel",
      "id": "singlestat",
      "name": "Singlestat",
      "version": "5.0.0"
    }
  ],
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "limit": 100,
        "name": "Annotations & Alerts",
        "showIn": 0,
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "gnetId": null,
  "graphTooltip": 0,
  "id": null,
  "iteration": 1600637492559,
  "links": [],
  "panels": [
    {
      "collapsed": false,
      "gridPos": {
        "h": 1,
        "w": 24,
        "x": 0,
        "y": 0
      },
      "id": 26,
      "panels": [],
      "title": "Zookeeper",
      "type": "row"
    },
    {
      "cacheTimeout": null,
      "colorBackground": false,
      "colorValue": true,
      "colors": [
        "#d44a3a",
        "rgba(237, 129, 40, 0.89)",
        "#299c46"
      ],
      "datasource": "${DS_PROMETHEUS}",
      "description": "Quorum Size of Zookeeper ensemble",
      "format": "none",
      "gauge": {
        "maxValue": 100,
        "minValue": 0,
        "show": false,
        "thresholdLabels": false,
        "thresholdMarkers": true
      },
      "gridPos": {
        "h": 4,
        "w": 4,
        "x": 0,
        "y": 1
      },
      "id": 52,
      "interval": null,
      "links": [],
      "mappingType": 1,
      "mappingTypes": [
        {
          "name": "value to text",
          "value": 1
        },
        {
          "name": "range to text",
          "value": 2
        }
      ],
      "maxDataPoints": 100,
      "nullPointMode": "connected",
      "nullText": null,
      "postfix": "",
      "postfixFontSize": "50%",
      "prefix": "",
      "prefixFontSize": "50%",
      "rangeMaps": [
        {
          "from": "null",
          "text": "N/A",
          "to": "null"
        }
      ],
      "sparkline": {
        "fillColor": "rgba(31, 118, 189, 0.18)",
        "full": false,
        "lineColor": "rgb(31, 120, 193)",
        "show": false
      },
      "tableColumn": "",
      "targets": [
        {
          "expr": "max(zookeeper_quorumsize{namespace=\"$kubernetes_namespace\",strimzi_io_cluster=\"$strimzi_cluster_name\",strimzi_io_kind=\"Kafka\"})",
          "format": "time_series",
          "intervalFactor": 1,
          "refId": "A"
        }
      ],
      "thresholds": "2,3",
      "title": "Quorum Size",
      "type": "singlestat",
      "valueFontSize": "200%",
      "valueMaps": [
        {
          "op": "=",
          "text": "N/A",
          "value": "null"
        }
      ],
      "valueName": "current"
    },
    {
      "cacheTimeout": null,
      "colorBackground": false,
      "colorValue": true,
      "colors": [
        "#299c46",
        "rgba(237, 129, 40, 0.89)",
        "#d44a3a"
      ],
      "datasource": "${DS_PROMETHEUS}",
      "description": "Number of Alive Connections",
      "format": "none",
      "gauge": {
        "maxValue": 100,
        "minValue": 0,
        "show": false,
        "thresholdLabels": false,
        "thresholdMarkers": true
      },
      "gridPos": {
        "h": 4,
        "w": 4,
        "x": 4,
        "y": 1
      },
      "id": 54,
      "interval": null,
      "links": [],
      "mappingType": 1,
      "mappingTypes": [
        {
          "name": "value to text",
          "value": 1
        },
        {
          "name": "range to text",
          "value": 2
        }
      ],
      "maxDataPoints": 100,
      "nullPointMode": "connected",
      "nullText": null,
      "postfix": "",
      "postfixFontSize": "50%",
      "prefix": "",
      "prefixFontSize": "50%",
      "rangeMaps": [
        {
          "from": "null",
          "text": "N/A",
          "to": "null"
        }
      ],
      "sparkline": {
        "fillColor": "rgba(31, 118, 189, 0.18)",
        "full": false,
        "lineColor": "rgb(31, 120, 193)",
        "show": false
      },
      "tableColumn": "",
      "targets": [
        {
          "expr": "sum(zookeeper_numaliveconnections{namespace=\"$kubernetes_namespace\",strimzi_io_cluster=\"$strimzi_cluster_name\",strimzi_io_kind=\"Kafka\",kubernetes_pod_name=~\"$strimzi_cluster_name-$zk_node\"})",
          "format": "time_series",
          "intervalFactor": 1,
          "refId": "A"
        }
      ],
      "thresholds": "60,120",
      "title": "Alive Connections",
      "type": "singlestat",
      "valueFontSize": "200%",
      "valueMaps": [
        {
          "op": "=",
          "text": "N/A",
          "value": "null"
        }
      ],
      "valueName": "current"
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "description": "Number of queued requests in the server. This goes up when the server receives more requests than it can process",
      "fill": 1,
      "gridPos": {
        "h": 8,
        "w": 16,
        "x": 8,
        "y": 1
      },
      "id": 12,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "zookeeper_outstandingrequests{namespace=\"$kubernetes_namespace\",strimzi_io_cluster=\"$strimzi_cluster_name\",strimzi_io_kind=\"Kafka\",kubernetes_pod_name=~\"$strimzi_cluster_name-$zk_node\"}",
          "format": "time_series",
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{kubernetes_pod_name}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeShift": null,
      "title": "Outstanding Requests",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "cacheTimeout": null,
      "colorBackground": false,
      "colorValue": true,
      "colors": [
        "#299c46",
        "rgba(237, 129, 40, 0.89)",
        "#d44a3a"
      ],
      "datasource": "${DS_PROMETHEUS}",
      "format": "none",
      "gauge": {
        "maxValue": 100,
        "minValue": 0,
        "show": false,
        "thresholdLabels": false,
        "thresholdMarkers": true
      },
      "gridPos": {
        "h": 4,
        "w": 4,
        "x": 0,
        "y": 5
      },
      "id": 64,
      "interval": null,
      "links": [],
      "mappingType": 1,
      "mappingTypes": [
        {
          "name": "value to text",
          "value": 1
        },
        {
          "name": "range to text",
          "value": 2
        }
      ],
      "maxDataPoints": 100,
      "nullPointMode": "connected",
      "nullText": null,
      "postfix": "",
      "postfixFontSize": "50%",
      "prefix": "",
      "prefixFontSize": "50%",
      "rangeMaps": [
        {
          "from": "null",
          "text": "N/A",
          "to": "null"
        }
      ],
      "sparkline": {
        "fillColor": "rgba(31, 118, 189, 0.18)",
        "full": false,
        "lineColor": "rgb(31, 120, 193)",
        "show": false
      },
      "tableColumn": "",
      "targets": [
        {
          "expr": "avg(zookeeper_inmemorydatatree_nodecount{namespace=\"$kubernetes_namespace\",strimzi_io_cluster=\"$strimzi_cluster_name\",strimzi_io_kind=\"Kafka\"})",
          "format": "time_series",
          "intervalFactor": 1,
          "refId": "A"
        }
      ],
      "thresholds": "500,800",
      "title": "Number of ZNodes",
      "type": "singlestat",
      "valueFontSize": "200%",
      "valueMaps": [
        {
          "op": "=",
          "text": "N/A",
          "value": "null"
        }
      ],
      "valueName": "current"
    },
    {
      "cacheTimeout": null,
      "colorBackground": false,
      "colorValue": true,
      "colors": [
        "#299c46",
        "rgba(237, 129, 40, 0.89)",
        "#d44a3a"
      ],
      "datasource": "${DS_PROMETHEUS}",
      "description": "Number of Watchers",
      "format": "none",
      "gauge": {
        "maxValue": 100,
        "minValue": 0,
        "show": false,
        "thresholdLabels": false,
        "thresholdMarkers": true
      },
      "gridPos": {
        "h": 4,
        "w": 4,
        "x": 4,
        "y": 5
      },
      "id": 66,
      "interval": null,
      "links": [],
      "mappingType": 1,
      "mappingTypes": [
        {
          "name": "value to text",
          "value": 1
        },
        {
          "name": "range to text",
          "value": 2
        }
      ],
      "maxDataPoints": 100,
      "nullPointMode": "connected",
      "nullText": null,
      "postfix": "",
      "postfixFontSize": "50%",
      "prefix": "",
      "prefixFontSize": "50%",
      "rangeMaps": [
        {
          "from": "null",
          "text": "N/A",
          "to": "null"
        }
      ],
      "sparkline": {
        "fillColor": "rgba(31, 118, 189, 0.18)",
        "full": false,
        "lineColor": "rgb(31, 120, 193)",
        "show": false
      },
      "tableColumn": "",
      "targets": [
        {
          "expr": "sum(zookeeper_inmemorydatatree_watchcount{namespace=\"$kubernetes_namespace\",strimzi_io_cluster=\"$strimzi_cluster_name\",strimzi_io_kind=\"Kafka\",kubernetes_pod_name=~\"$strimzi_cluster_name-$zk_node\"})",
          "format": "time_series",
          "intervalFactor": 1,
          "refId": "A"
        }
      ],
      "thresholds": "100,200",
      "title": "Number of Watchers",
      "type": "singlestat",
      "valueFontSize": "200%",
      "valueMaps": [
        {
          "op": "=",
          "text": "N/A",
          "value": "null"
        }
      ],
      "valueName": "current"
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "description": "ZooKeeper Pods Memory Usage",
      "fill": 1,
      "gridPos": {
        "h": 7,
        "w": 6,
        "x": 0,
        "y": 9
      },
      "id": 87,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "sum(container_memory_usage_bytes{namespace=\"$kubernetes_namespace\",container=\"zookeeper\",pod=~\"$strimzi_cluster_name-$zk_node\"}) by (pod)",
          "format": "time_series",
          "intervalFactor": 1,
          "legendFormat": "{{pod}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeShift": null,
      "title": "Memory Usage",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "bytes",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "description": "Aggregated ZooKeeper Pods CPU Usage",
      "fill": 1,
      "gridPos": {
        "h": 7,
        "w": 6,
        "x": 6,
        "y": 9
      },
      "id": 85,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"$kubernetes_namespace\",container=\"zookeeper\",pod=~\"$strimzi_cluster_name-$zk_node\"}[5m])) by (pod)",
          "format": "time_series",
          "intervalFactor": 1,
          "legendFormat": "{{pod}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeShift": null,
      "title": "CPU Usage",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "description": "Kafka Broker Pods Disk Usage",
      "fill": 1,
      "gridPos": {
        "h": 7,
        "w": 6,
        "x": 12,
        "y": 9
      },
      "id": 89,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "kubelet_volume_stats_available_bytes{namespace=\"$kubernetes_namespace\",persistentvolumeclaim=~\"data(-[0-9]+)?-$strimzi_cluster_name-zookeeper-[0-9]+\"}",
          "format": "time_series",
          "intervalFactor": 1,
          "legendFormat": "{{persistentvolumeclaim}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeShift": null,
      "title": "Available Disk Space",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "bytes",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "description": "Open File Descriptors",
      "fill": 1,
      "gridPos": {
        "h": 7,
        "w": 6,
        "x": 18,
        "y": 9
      },
      "id": 96,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "paceLength": 10,
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "process_open_fds{namespace=\"$kubernetes_namespace\",pod=~\"$strimzi_cluster_name-zookeeper-[0-9+]\",container=\"zookeeper\"}",
          "format": "time_series",
          "hide": false,
          "intervalFactor": 1,
          "legendFormat": "{{pod}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeShift": null,
      "title": "Open File Descriptors",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "none",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "fill": 1,
      "gridPos": {
        "h": 7,
        "w": 6,
        "x": 0,
        "y": 16
      },
      "id": 91,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "sum(jvm_memory_bytes_used{namespace=\"$kubernetes_namespace\",kubernetes_pod_name=~\"$strimzi_cluster_name-$zk_node\",strimzi_io_name=\"$strimzi_cluster_name-zookeeper\"}) by (kubernetes_pod_name)",
          "format": "time_series",
          "intervalFactor": 1,
          "legendFormat": "{{kubernetes_pod_name}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeShift": null,
      "title": "JVM Memory Used",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "decbytes",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "fill": 1,
      "gridPos": {
        "h": 7,
        "w": 6,
        "x": 6,
        "y": 16
      },
      "id": 93,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "sum(rate(jvm_gc_collection_seconds_sum{namespace=\"$kubernetes_namespace\",kubernetes_pod_name=~\"$strimzi_cluster_name-$zk_node\",strimzi_io_name=\"$strimzi_cluster_name-zookeeper\"}[5m])) by (kubernetes_pod_name)",
          "format": "time_series",
          "intervalFactor": 1,
          "legendFormat": "{{kubernetes_pod_name}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeShift": null,
      "title": "JVM GC Time",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "ms",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "fill": 1,
      "gridPos": {
        "h": 7,
        "w": 6,
        "x": 12,
        "y": 16
      },
      "id": 95,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "sum(rate(jvm_gc_collection_seconds_count{namespace=\"$kubernetes_namespace\",kubernetes_pod_name=~\"$strimzi_cluster_name-$zk_node\",strimzi_io_name=\"$strimzi_cluster_name-zookeeper\"}[5m])) by (kubernetes_pod_name)",
          "format": "time_series",
          "intervalFactor": 1,
          "legendFormat": "{{kubernetes_pod_name}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeShift": null,
      "title": "JVM GC Count",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "description": "JVM Thread Count",
      "fill": 1,
      "gridPos": {
        "h": 7,
        "w": 6,
        "x": 18,
        "y": 16
      },
      "id": 97,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "paceLength": 10,
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "jvm_threads_current{namespace=\"$kubernetes_namespace\",kubernetes_pod_name=~\"$strimzi_cluster_name-zookeeper-[0-9+]\",strimzi_io_name=\"$strimzi_cluster_name-zookeeper\"}",
          "format": "time_series",
          "intervalFactor": 1,
          "legendFormat": "{{kubernetes_pod_name}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeShift": null,
      "title": "JVM Thread Count",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "description": "Amount of time (in ms) it takes for the server to respond to a client request",
      "fill": 1,
      "gridPos": {
        "h": 8,
        "w": 8,
        "x": 0,
        "y": 23
      },
      "id": 10,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "zookeeper_minrequestlatency{namespace=\"$kubernetes_namespace\",kubernetes_pod_name=~\"$strimzi_cluster_name-$zk_node\"}",
          "format": "time_series",
          "intervalFactor": 1,
          "legendFormat": "{{kubernetes_pod_name}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeShift": null,
      "title": "Request Latency - Minimum",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "ms",
          "label": "Request Latency (ms)",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "description": "Amount of time (in ms) it takes for the server to respond to a client request",
      "fill": 1,
      "gridPos": {
        "h": 8,
        "w": 8,
        "x": 8,
        "y": 23
      },
      "id": 6,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "zookeeper_avgrequestlatency{namespace=\"$kubernetes_namespace\",kubernetes_pod_name=~\"$strimzi_cluster_name-$zk_node\"}",
          "format": "time_series",
          "intervalFactor": 1,
          "legendFormat": "{{kubernetes_pod_name}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeShift": null,
      "title": "Request Latency - Average",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "ms",
          "label": "Request Latency (ms)",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "description": "Amount of time (in ms) it takes for the server to respond to a client request",
      "fill": 1,
      "gridPos": {
        "h": 8,
        "w": 8,
        "x": 16,
        "y": 23
      },
      "id": 8,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "zookeeper_maxrequestlatency{namespace=\"$kubernetes_namespace\",kubernetes_pod_name=~\"$strimzi_cluster_name-$zk_node\"}",
          "format": "time_series",
          "intervalFactor": 1,
          "legendFormat": "{{kubernetes_pod_name}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeShift": null,
      "title": "Request Latency - Maximum",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "ms",
          "label": "Request Latency (ms)",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    }
  ],
  "refresh": "5s",
  "schemaVersion": 21,
  "style": "dark",
  "tags": [
    "Strimzi",
    "Kafka",
    "Zookeeper"
  ],
  "templating": {
    "list": [
      {
        "allValue": null,
        "current": {},
        "datasource": "${DS_PROMETHEUS}",
        "hide": 0,
        "includeAll": false,
        "label": "Namespace",
        "multi": false,
        "name": "kubernetes_namespace",
        "options": [],
        "query": "query_result(zookeeper_inmemorydatatree_nodecount)",
        "refresh": 1,
        "regex": "/.*namespace=\"([^\"]*).*/",
        "sort": 0,
        "tagValuesQuery": "",
        "tags": [],
        "tagsQuery": "",
        "type": "query",
        "useTags": false
      },
      {
        "allValue": null,
        "current": {},
        "datasource": "${DS_PROMETHEUS}",
        "hide": 0,
        "includeAll": false,
        "label": "Cluster Name",
        "multi": false,
        "name": "strimzi_cluster_name",
        "options": [],
        "query": "query_result(zookeeper_inmemorydatatree_nodecount{namespace=\"$kubernetes_namespace\"})",
        "refresh": 1,
        "regex": "/.*strimzi_io_cluster=\"([^\"]*).*/",
        "sort": 0,
        "tagValuesQuery": "",
        "tags": [],
        "tagsQuery": "",
        "type": "query",
        "useTags": false
      },
      {
        "allValue": ".*",
        "current": {},
        "datasource": "${DS_PROMETHEUS}",
        "hide": 0,
        "includeAll": true,
        "label": "Node",
        "multi": false,
        "name": "zk_node",
        "options": [],
        "query": "query_result(zookeeper_inmemorydatatree_nodecount{namespace=\"$kubernetes_namespace\",strimzi_io_cluster=\"$strimzi_cluster_name\"})",
        "refresh": 1,
        "regex": "/.*statefulset_kubernetes_io_pod_name=\"$strimzi_cluster_name-([^\"]*).*/",
        "sort": 0,
        "tagValuesQuery": "",
        "tags": [],
        "tagsQuery": "",
        "type": "query",
        "useTags": false
      }
    ]
  },
  "time": {
    "from": "now-1h",
    "to": "now"
  },
  "timepicker": {
    "refresh_intervals": [
      "5s",
      "10s",
      "30s",
      "1m",
      "5m",
      "15m",
      "30m",
      "1h",
      "2h",
      "1d"
    ],
    "time_options": [
      "5m",
      "15m",
      "1h",
      "6h",
      "12h",
      "24h",
      "2d",
      "7d",
      "30d"
    ]
  },
  "timezone": "",
  "title": "Strimzi ZooKeeper",
  "uid": "fc85de600d62d9841e9de00083b24b72",
  "version": 2
}
EOF

#install grafana
cat <<EOF > ./grafana.yaml
---
# This is not a recommended configuration, and further support should be available
# from the Prometheus and Grafana communities.

apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  labels:
    app: strimzi
spec:
  replicas: 1
  selector:
    matchLabels:
      name: grafana
  template:
    metadata:
      labels:
        name: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:7.3.7
        ports:
        - name: grafana
          containerPort: 3000
          protocol: TCP
        volumeMounts:
        - name: grafana-data
          mountPath: /var/lib/grafana
        - name: grafana-logs
          mountPath: /var/log/grafana
        readinessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 15
          periodSeconds: 20
      volumes:
      - name: grafana-data
        emptyDir: {}
      - name: grafana-logs
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  labels:
    app: strimzi
spec:
  ports:
  - name: grafana
    port: 3000
    targetPort: 3000
    protocol: TCP
  selector:
    name: grafana
  type: ClusterIP
---
EOF
kubectl apply -f grafana.yaml -n clt-datacenter

kubectl get service grafana -n clt-datacenter
kubectl get service prometheus-operated -n clt-datacenter