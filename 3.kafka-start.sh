#!/usr/bin/env bash

kubectl create namespace kafka
kubectl apply -f ./helm/kafkaoperator/kafkaoperator.yaml -n kafka

kubectl apply -f ./helm/kafkaoperator/local_storageclass.yaml

#(Optional) remove all data
sudo rm -rf /database/kafka

#(Optional) In case of cold running
sudo mkdir -p /database/kafka/kafka1
sudo chmod 777 /database/kafka/kafka1
sudo mkdir -p /database/kafka/kafka2
sudo chmod 777 /database/kafka/kafka2
sudo mkdir -p /database/kafka/kafka3
sudo chmod 777 /database/kafka/kafka3
sudo mkdir -p /database/kafka/zookeeper1
sudo chmod 777 /database/kafka/zookeeper1
sudo mkdir -p /database/kafka/zookeeper2
sudo chmod 777 /database/kafka/zookeeper2
sudo mkdir -p /database/kafka/zookeeper3
sudo chmod 777 /database/kafka/zookeeper3

kubectl apply -f ./helm/kafkaoperator/kafka_pv.yaml

kubectl apply -f ./helm/kafkaoperator/kafka_cluster_persistent.yaml -n kafka
kubectl wait kafka/kafka-cluster --for=condition=Ready --timeout=300s -n kafka