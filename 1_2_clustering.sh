#!/usr/bin/env bash

## CASE1 In case if you want to deploy pod in the untaint master node (control-plane node)

#(optional) check master node taint status
kubectl describe node master | grep Taints

# Untaint
kubectl taint nodes --all node-role.kubernetes.io/master-

# (optional) Taint again
kubectl taint nodes master node-role.kubernetes.io=master:NoSchedule

## CASE2 clustering

# join cluster
sudo kubeadm join 