#!/usr/bin/env bash

#deploy crd

mkdir -p ~/maria
cd ~/maria

git clone https://github.com/abalki001/mariadb-operator.git

mv ~/maria/mariadb-operator/* ~/maria

kubectl create namespace clt-datacenter
kubectl apply -f ./deploy/crds/mariadb.persistentsys_backups_crd.yaml -n clt-datacenter
kubectl apply -f ./deploy/crds/mariadb.persistentsys_mariadbs_crd.yaml -n clt-datacenter
kubectl apply -f ./deploy/crds/mariadb.persistentsys_monitors_crd.yaml -n clt-datacenter

#deploy PV
cat <<EOF > ./mariadb_pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mariadb-pv-volume
  labels:
    type: local
spec:
  storageClassName: default
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/mnt/data"
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - node1
EOF

#deploy PVC
cat <<EOF > ./mariadb_pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb-pv-claim
spec:
  storageClassName: default
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  volumeName: "mariadb-pv-volume"
EOF

#deploy role
cat <<EOF > ./role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  creationTimestamp: null
  name: mariadb-operator
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - services
  - services/finalizers
  - endpoints
  - persistentvolumeclaims
  - events
  - configmaps
  - secrets
  verbs:
  - create
  - delete
  - get
  - list
  - patch
  - update
  - watch
- apiGroups:
  - apps
  resources:
  - deployments
  - daemonsets
  - replicasets
  - statefulsets
  verbs:
  - create
  - delete
  - get
  - list
  - patch
  - update
  - watch
- apiGroups:
  - monitoring.coreos.com
  resources:
  - servicemonitors
  verbs:
  - get
  - create
- apiGroups:
  - apps
  resourceNames:
  - mariadb-operator
  resources:
  - deployments/finalizers
  verbs:
  - update
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
- apiGroups:
  - apps
  resources:
  - replicasets
  - deployments
  verbs:
  - get
- apiGroups:
  - mariadb.persistentsys
  resources:
  - '*'
  - backups
  verbs:
  - create
  - delete
  - get
  - list
  - patch
  - update
  - watch
- apiGroups:
  - batch
  resources:
  - cronjobs
  - jobs
  verbs:
  - create
  - delete
  - get
  - list
  - watch
  - update
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  creationTimestamp: null
  name: mariadb-operator-cl-role
rules:
- apiGroups: [""]
  resources:
  - nodes
  - persistentvolumes
  - namespaces
  verbs:
  - list
  - watch
  - get
  - create
  - delete
- apiGroups: ["storage.k8s.io"]
  resources:
  - storageclasses
  verbs:
  - list
  - watch
  - get
  - create
  - delete
- apiGroups:
  - monitoring.coreos.com
  resources:
  - alertmanagers
  - prometheuses
  - prometheuses/finalizers
  - servicemonitors
  verbs:
  - "*"
EOF

#deploy role_binding
cat <<EOF > ./role_binding.yaml
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: mariadb-operator
subjects:
- kind: ServiceAccount
  name: mariadb-operator
roleRef:
  kind: Role
  name: mariadb-operator
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: mariadb-operator-cl-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: mariadb-operator-cl-role
subjects:
  - kind: ServiceAccount
    name: mariadb-operator
    namespace: mariadb

EOF

cat <<EOF > ./service_account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mariadb-operator
EOF

kubectl delete pv mariadb-pv-volume
kubectl apply -f mariadb_pv.yaml
kubectl apply -f mariadb_pvc.yaml -n clt-datacenter
kubectl apply -f role.yaml -n clt-datacenter
kubectl apply -f role_binding.yaml -n clt-datacenter
kubectl apply -f service_account.yaml -n clt-datacenter

##deploy oeprator
cat <<EOF > ./operator.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb-operator
  namespace: clt-datacenter
spec:
  replicas: 1
  selector:
    matchLabels:
      name: mariadb-operator
  template:
    metadata:
      labels:
        name: mariadb-operator
    spec:
      serviceAccountName: mariadb-operator
      containers:
        - name: mariadb-operator
          # Replace this with the built image name
          image: quay.io/manojdhanorkar/mariadb-operator:v0.0.4
          command:
          - mariadb-operator
          imagePullPolicy: Always
          env:
            - name: WATCH_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: OPERATOR_NAME
              value: "mariadb-operator"
      nodeSelector:
        kubernetes.io/hostname: node1
#      affinity:
#        nodeAffinity:
#          requiredDuringSchedulingIgnoredDuringExecution:
#            nodeSelectorTerms:
#              - matchExpressions:
#                - key: kubernetes.io/hostname
#                  operator: In
#                  values:
#                  - node2
EOF
kubectl apply -f operator.yaml -n clt-datacenter

##deploy db server
cat <<EOF > ./mariadb.yaml
apiVersion: mariadb.persistentsys/v1alpha1
kind: MariaDB
metadata:
  name: mariadb
spec:
  # Keep this parameter value unchanged.
  size: 1

  # Root user password
  rootpwd: root

  # New Database name
  database: clt-db
  # Database additional user details (base64 encoded)
  username: cltuser
  password: cltuser

  # Image name with version
  image: "mariadb/server:10.3"

  # Database storage Path
  dataStoragePath: "/mnt/data"

  # Database storage Size (Ex. 1Gi, 100Mi)
  dataStorageSize: "5Gi"

  # Port number exposed for Database service
  port: 30685

  nodeSelector:
    kubernetes.io/hostname: node1
EOF
kubectl apply -f mariadb.yaml -n clt-datacenter


##(optional)deploy db backup
cat <<EOF > ./mariadb_backup.yaml
apiVersion: mariadb.persistentsys/v1alpha1
kind: Backup
metadata:
  name: mariadb-backup
spec:
  # Backup Path
  backupPath: "/mnt/backup"

  # Backup Size (Ex. 1Gi, 100Mi)
  backupSize: "100Mi"

  # Schedule period for the CronJob.
  # This spec allow you setup the backup frequency
  # Default: "0 0 * * *" # daily at 00:00
  schedule: "0 0 * * *"

  nodeSelector:
    kubernetes.io/hostname: node1
EOF
kubectl apply -f mariadb_backup.yaml -n clt-datacenter

mysql -h 30.0.2.31 -P 30685 -u cltuser -p
# enter password
# sql create test db
CREATE DATABASE test;

##(optional) monitoring
cat <<EOF > ./mariadb_monitoring.yaml
apiVersion: mariadb.persistentsys/v1alpha1
kind: Monitor
metadata:
  name: mariadb-monitor
spec:
  # Add fields here
  size: 1
  # Database source to connect with for colleting metrics
  # Format: "<db-user>:<db-password>@(<dbhost>:<dbport>)/<dbname>">
  # Make approprite changes
  dataSourceName: "cltuser:cltuser@(30.0.2.31:30685)/test"
  # Image name with version
  # Refer https://registry.hub.docker.com/r/prom/mysqld-exporter for more details
  image: "prom/mysqld-exporter"
  nodeSelector:
    kubernetes.io/hostname: node1
EOF
kubectl apply -f mariadb_monitoring.yaml -n clt-datacenter