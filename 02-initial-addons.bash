#!/bin/bash

#export $(xargs <.env)

mkdir -p addons
sudo mkdir -p /data

# ต้องเพิ่ม volume map ตรง k3s volume ด้วย
SRC_FILE=00-configs/addons-argocd.yaml
kubectl apply -f ${SRC_FILE}

SRC_FILE=00-configs/addons-ingress.yaml
kubectl apply -f ${SRC_FILE}

SRC_FILE=00-configs/addons-external-secret.yaml
kubectl apply -f ${SRC_FILE}

SRC_FILE=00-configs/addons-cert-manager.yaml
kubectl apply -f ${SRC_FILE}

#SRC_FILE=00-configs/addons-gitea.yaml
#kubectl apply -f ${SRC_FILE}
