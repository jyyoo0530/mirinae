#!/usr/bin/env bash

hostname -I | cut -d' ' -f1
sudo kubeadm init --apiserver-advertise-address=172.20.106.206 --pod-network-cidr=10.244.0.0/16