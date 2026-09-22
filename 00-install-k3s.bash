#/bin/bash

#/usr/local/bin/k3s-uninstall.sh
#rm -rf /data/*

curl -sfL https://get.k3s.io | sh -s - \
  --cluster-init \
  --default-local-storage-path "/data" \
  --disable traefik \
  --etcd-expose-metrics=true

# Copy k3s.yaml to home directory for kubectl usage
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/k3s.yaml
sudo chown $(id -u):$(id -g) $HOME/k3s.yaml
