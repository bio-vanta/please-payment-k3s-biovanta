#!/bin/bash

MODE=${1:-prod}

cd 01-bootstrap

kubectl apply -f argocd-ing.yaml

#if [ "$MODE" = "dev" ]; then
  # ให้ปรับ repoURL ให้ชี้ตรงไปที่ remote GIT ด้วย เพื่อให้ ArgoCD ไป sync มาจากตรงนั้นแทน
  DATA_PLANE_REMOTE_REPO=https://github.com/bio-vanta/please-payment-k3s-biovanta.git
  CTRL_PLANE_REMOTE_REPO=https://github.com/wintech-thai/please-payment-control-plane.git

  sed -i "s|^\([[:space:]]*\)repoURL: .*|\1repoURL: ${DATA_PLANE_REMOTE_REPO}|g" argocd-bootstrap-data-plane.yaml
  #sed -i "s|^\([[:space:]]*\)repoURL: .*|\1repoURL: ${CTRL_PLANE_REMOTE_REPO}|g" argocd-bootstrap-control-plane-dev.yaml
  sed -i "s|^\([[:space:]]*\)repoURL: .*|\1repoURL: ${CTRL_PLANE_REMOTE_REPO}|g" argocd-bootstrap-please-payment-prod.yaml

  #echo "Deploying DEV control plane"
  #kubectl apply -f argocd-bootstrap-control-plane-dev.yaml
#fi

echo "Deploying PROD control plane"
kubectl apply -f argocd-bootstrap-please-payment-prod.yaml

echo "Deploying data plane"
kubectl apply -f argocd-bootstrap-data-plane.yaml

kubectl apply -f argocd-cluster-secret.yaml

GIT_USER=$(kubectl get secret initial-secret -n default -o jsonpath='{.data.GIT_USER}' | base64 -d)
GIT_PASSWORD=$(kubectl get secret initial-secret -n default -o jsonpath='{.data.GIT_PASSWORD}' | base64 -d)

YAML_FILE="argocd-local-repo.yaml"
cp ${YAML_FILE} ${YAML_FILE}.tmp
sed -i "s|<<GITEA_USERNAME>>|${GIT_USER}|g" ${YAML_FILE}.tmp
sed -i "s|<<GITEA_PASSWORD>>|${GIT_PASSWORD}|g" ${YAML_FILE}.tmp 
kubectl apply -f ${YAML_FILE}.tmp

# Sync code จาก remote มาที่ local
# TODO : กำหนดเวอร์ชันของ data-plane, control-plane ที่จะ sync ได้
# TODO : ปรับ config ได้ว่าจะ sync  control-plane ด้วยหรือไม่
#kubectl apply -f git-sync-job.yaml

cd ..
