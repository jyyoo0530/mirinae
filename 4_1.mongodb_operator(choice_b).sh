#!/usr/bin/env bash

kubectl create namespace mongodb
kubectl apply -f ./helm/mongodb/operator/mongo_sc_operator.yaml

sudo rm -rf /database/mongodb
#(Optional) In case of cold running
for i in 1 2 3
do
 sudo mkdir -p /database/mongodb/mongod$i
 sudo chmod 777 /database/mongodb/mongod$i
 sudo mkdir -p /database/mongodb/agent$i
 sudo chmod 777 /database/mongodb/agent$i
done

kubectl apply -f ./helm/mongodb/operator/mongo_pv_operator.yaml

kubectl apply -f ./helm/mongodb/operator/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml -n mongodb
kubectl apply -k ./helm/mongodb/operator/rbac/ -n mongodb
kubectl apply -f ./helm/mongodb/operator/manager/manager.yaml --namespace mongodb

kubectl apply -f ./helm/mongodb/operator/mongo_replica_statefulset.yaml -n mongodb

kubectl get pods --namespace mongodb