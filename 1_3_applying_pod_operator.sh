#!/usr/bin/env bash

kubectl wait pod/kube-controller-manager-master --for=condition=Ready --timeout=300s -n kube-system
kubectl apply -f ./helm/flannel/kube-flannel.yml

# (optional) - dnsutil
kubectl apply -f ./helm/dnsutil/dnsutil.yaml -n kube-system

# (optional) - dashboard
kubectl apply -f ./helm/dashboard/dashboard.yaml
kubectl proxy --port=8001 &
# using token authentication
kubectl create serviceaccount dashboard-admin-sa
kubectl create clusterrolebinding dashboard-admin-sa \
--clusterrole=cluster-admin --serviceaccount=default:dashboard-admin-sa
kubectl get secrets
kubectl describe secret dashboard-admin-sa-token-<your results>
# get token (copy) open below address in chrome and paste
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/