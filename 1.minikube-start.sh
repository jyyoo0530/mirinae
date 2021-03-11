#!/usr/bin/env bash

minikube start --cpus 4 --memory 8096

minikube addons enable registry-creds
minikube addons configure registry-creds


kubectl cluster-info
https://index.docker.io/v1/
https://index.docker.io/v2/