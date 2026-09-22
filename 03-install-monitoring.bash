#!/bin/bash

# Server มี resource น้อยเลยไม่ลง monitoring
#exit 0



# Run this after app install on ArgoCD

cd 03-monitoring

kubectl apply -f <(cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
EOF
)

GRAFANA_USER=$(kubectl get secret initial-secret -n default -o jsonpath='{.data.GRAFANA_USER}' | base64 -d)
GRAFANA_PASSWORD=$(kubectl get secret initial-secret -n default -o jsonpath='{.data.GRAFANA_PASSWORD}' | base64 -d)

YAML_FILE="grafana-secret.yaml"
cp ${YAML_FILE} ${YAML_FILE}.tmp
sed -i "s|<<GRAFANA_USER>>|${GRAFANA_USER}|g" ${YAML_FILE}.tmp
sed -i "s|<<GRAFANA_PASSWORD>>|${GRAFANA_PASSWORD}|g" ${YAML_FILE}.tmp
kubectl apply -f ${YAML_FILE}.tmp


helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# วนลูป 2 ครั้งใส่ delay เพราะ run ครั้งแรกมักจะไม่สำเร็จเพราะ CRD ยังสร้างไม่ทัน
for i in 1 2; do
  echo "Attempt $i..."

  helm template kube-prometheus-crds \
    prometheus-community/kube-prometheus-stack \
    --version 76.4.0 \
    --include-crds \
    --namespace monitoring \
    -f prometheus-values.yaml \
    | kubectl apply -f - --server-side --force-conflicts

  # ถ้าไม่ใช่รอบสุดท้าย ให้หน่วง
  if [ "$i" -lt 2 ]; then
    echo "Waiting for CRDs to be ready..."
    sleep 5
  fi
done

# ตอนนี้ชี้ไปที่ DEV environment อยู่ แต่ถ้าเป็น production ต้องเปลี่ยน URL ใน alm-config.yaml ด้วย
kubectl apply -f alm-config.yaml

cd ..
