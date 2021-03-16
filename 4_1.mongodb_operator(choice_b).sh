#!/usr/bin/env bash

kubectl create namespace mongodb
kubectl apply -f ./helm/mongodb/local_storageclass.yaml

#(Optional) In case of cold running
sudo mkdir -p /database/mongodb/db1
sudo chmod 777 /database/mongodb/db1
sudo mkdir -p /database/mongodb/db2
sudo chmod 777 /database/mongodb/db2
sudo mkdir -p /database/mongodb/db3
sudo chmod 777 /database/mongodb/db3

kubectl apply -f ./helm/mongodb/mongo_pv.yaml

kubectl apply -f ./helm/mongodb/operator/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml
kubectl apply -k ./helm/mongodb/operator/rbac/ -n mongodb
kubectl apply -f ./helm/mongodb/operator/manager/manager.yaml --namespace mongodb

kubectl apply -f ./helm/mongodb/mongo_replica_statefulset.yaml -n mongodb

kubectl get pods --namespace mongodb