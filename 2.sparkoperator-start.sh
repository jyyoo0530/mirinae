#!/usr/bin/env bash

kubectl create namespace spark-operator
kubectl create namespace spark-apps

kubectl create serviceaccount spark \
 --namespace=spark-operator

kubectl create clusterrolebinding spark-operator-role \
 --clusterrole=edit \
 --serviceaccount=spark-operator:spark \
 --namespace=spark-operator

helm install spark \
./helm/sparkoperator \
 --namespace spark-operator \
 --set webhook.enable=true,webhook.port=8080,sparkJobNamespace=spark-apps,logLevel=3

kubectl get all -n spark-operator