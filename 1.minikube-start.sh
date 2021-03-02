#!/usr/bin/env bash

minikube start --cpus 4 --memory 8096
minikube addons configure registry-creds
minikube addons enable registry-creds

kubectl cluster-info