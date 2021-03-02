#!/usr/bin/env bash


kubectl apply -f ./test/sparkoperator/spark-pi.yaml -n spark-apps
kubectl apply -f ./test/sparkoperator/spark-pi-configmap.yaml -n spark-apps
kubectl apply -f ./test/sparkoperator/spark-pi-custom-resource.yaml -n spark-apps
kubectl apply -f ./test/sparkoperator/spark-pi-prometheus.yaml -n spark-apps
kubectl apply -f ./test/sparkoperator/spark-pi-schedule.yaml -n spark-apps
kubectl apply -f ./test/sparkoperator/spark-py-pi.yaml -n spark-apps


kubectl delete -f ./test/sparkoperator/spark-pi.yaml -n spark-apps
kubectl delete -f ./test/sparkoperator/spark-pi-configmap.yaml -n spark-apps
kubectl delete -f ./test/sparkoperator/spark-pi-custom-resource.yaml -n spark-apps
kubectl delete -f ./test/sparkoperator/spark-pi-prometheus.yaml -n spark-apps
kubectl delete -f ./test/sparkoperator/spark-pi-schedule.yaml -n spark-apps
kubectl delete -f ./test/sparkoperator/spark-py-pi.yaml -n spark-apps