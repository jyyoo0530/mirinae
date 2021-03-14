#!/usr/bin/env bash
## reference: https://gruuuuu.github.io/cloud/monitoring-02/#

# create name space
kubectl create ns monitoring

# deploy prometheus-cluster-role.yaml
kubectl apply -f ./helm/monitoring/prometheus-cluster-role.yaml

# deploy prometheus-config-map.yaml
kubectl apply -f ./helm/monitoring/prometheus-config-map.yaml

# deploy prometheus-deployment.yaml
kubectl apply -f ./helm/monitoring/prometheus-deployment.yaml

# deploy prometheus-node-exporter.yaml
kubectl apply -f ./helm/monitoring/prometheus-node-exporter.yaml

# deploy prometheus-svc.yaml
kubectl apply -f ./helm/monitoring/prometheus-svc.yaml

# deploy kube-state-cluster-role.yaml
kubectl apply -f ./helm/monitoring/kube-state-cluster-role.yaml

# deploy kube-state-svcaccount.yaml
kubectl apply -f ./helm/monitoring/kube-state-svcaccount.yaml

# deploy kube-state-deployment.yaml
kubectl apply -f ./helm/monitoring/kube-state-deployment.yaml

# deploy kube-state-svc.yaml
kubectl apply -f ./helm/monitoring/kube-state-svc.yaml

# apply grafana, grafana.yaml
kubectl apply -f ./helm/monitoring/grafana.yaml

# open 170.168.0.3:30004, and add data source, and add prometheus as source. To get URL,
kubectl get svc -n monitoring

# open https://grafana.com/grafana/dashboards, find suitable prometheus dashboard UI and copy ID & Use it in import dashboard.
