#!/usr/bin/env bash

kubectl create namespace mongodb
kubectl apply -f ./helm/mongodboperator/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml -n mongodb

kubectl get crd/mongodbcommunity.mongodbcommunity.mongodb.com -n mongodb


kubectl apply -k ./helm/mongodboperator/rbac/ -n mongodb

kubectl get role mongodb-kubernetes-operator
kubectl get rolebinding mongodb-kubernetes-operator
kubectl get serviceaccount mongodb-kubernetes-operator


kubectl create -f ./helm/mongodboperator/manager/manager.yaml --namespace mongodb

kubectl get pod --namespace mongodb

kubectl apply -f ./helm/mongodboperator/samples/mongodb.com_v1_mongodbcommunity_cr.yaml --namespace mongodb
kubectl get mongodbcommunity --namespace mongodb