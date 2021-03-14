#!/usr/bin/env bash

kubectl create namespace mongodb
kubectl apply -f ./helm/mongodboperator/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml -n mongodb

kubectl get crd/mongodbcommunity.mongodbcommunity.mongodb.com -n mongodb


kubectl apply -k ./helm/mongodboperator/rbac/ -n mongodb

kubectl get role mongodb-kubernetes-operator -n mongodb
kubectl get rolebinding mongodb-kubernetes-operator -n mongodb
kubectl get serviceaccount mongodb-kubernetes-operator -n mongodb


kubectl create -f ./helm/mongodboperator/manager/manager.yaml --namespace mongodb

kubectl get pod --namespace mongodb

kubectl apply -f ./helm/mongodboperator/mongodb.yaml --namespace mongodb
kubectl get mongodbcommunity --namespace mongodb