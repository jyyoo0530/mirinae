#!/usr/bin/env bash

kubectl create namespace kafka
kubectl apply -f ./helm/kafkaoperator/kafkaoperator.yaml -n kafka

kubectl apply -f ./helm/kafkaoperator/local_storageclass.yaml

#(Optional) remove all data
sudo rm -rf /database/kafka

#(Optional) In case of cold running
for i in 1 2 3
do
  sudo mkdir -p /database/kafka/kafka$i
  sudo chmod 777 /database/kafka/kafka$i
  sudo mkdir -p /database/kafka/zookeeper$i
  sudo chmod 777 /database/kafka/zookeeper$i
done

kubectl apply -f ./helm/kafkaoperator/kafka_pv.yaml

kubectl apply -f ./helm/kafkaoperator/kafka_cluster_persistent.yaml -n kafka
kubectl wait kafka/kafka-cluster --for=condition=Ready --timeout=300s -n kafka

## test by test-topic
  kubectl apply -f ./helm/kafkaoperator/kafka_topic.yaml -n kafka
  #find node IP
  nodeIp=$(kubectl get nodes --output=jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')
  #find port of bootstrap
  nodePort=$(kubectl get service kafka-cluster-kafka-external-bootstrap -n kafka -o=jsonpath='{.spec.ports[0].nodePort}{"\n"}')

  #test using producer and consumer
  ~/tools/kafka/bin/kafka-console-producer.sh --broker-list $nodeIp:$nodePort --topic test-topic
  ~/tools/kafka/bin/kafka-console-consumer.sh --bootstrap-server $nodeIp:$nodePort --topic test-topic --from-beginning

## Adding monitoring tool
  #download crd (optional)
  curl -s https://raw.githubusercontent.com/coreos/prometheus-operator/master/bundle.yaml | sed -e '/[[:space:]]*namespace: [a-zA-Z0-9-]*$/s/namespace:[[:space:]]*[a-zA-Z0-9-]*$/namespace: kafka/' > ./helm/kafkaoperator/prometheus/prometheus-operator-deployment.yaml
  #appply Grafana
  kubectl apply -f ./helm/kafkaoperator/prometheus/prometheus-operator-deployment.yaml -n kafka
  kubectl apply -f ./helm/kafkaoperator/prometheus/strimzi-pod-monitor.yaml -n kafka
  kubectl apply -f ./helm/kafkaoperator/prometheus/prometheus-rules.yaml -n kafka
  kubectl apply -f ./helm/kafkaoperator/prometheus/prometheus.yaml -n kafka
  # to do - add alerting
  #deploy grafana
  kubectl apply -f ./helm/kafkaoperator/grafana-dashboards/grafana_kafka.yaml -n kafka
  kubectl get service grafana -n kafka
  kubectl get service prometheus-operated -n kafka
