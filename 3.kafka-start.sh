#!/usr/bin/env bash

kubectl create namespace kafka
kubectl apply -f ./helm/kafkaoperator/kafkaoperator.yaml -n kafka
