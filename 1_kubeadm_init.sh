#!/usr/bin/env bash

sudo kubeadm init --apiserver-advertise-address=$(hostname -I | cut -d' ' -f1) --pod-network-cidr=10.244.0.0/16