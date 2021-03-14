#!/usr/bin/env bash

hostname -I | cut -d' ' -f1
sudo kubeadm init --apiserver-advertise-address=170.168.0.3 --pod-network-cidr=10.244.0.0/16