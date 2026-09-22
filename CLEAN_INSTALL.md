# Clean install — Please Payment on a single Ubuntu EC2 node

คู่มือนี้เป็น flow ที่ปรับจากปัญหาที่พบระหว่างติดตั้งจริง ใช้กับ repository `bio-vanta/please-payment-k3s-biovanta` และตั้งใจให้เริ่มจากเครื่องใหม่โดยไม่พบปัญหาเดิม

## 0. Preconditions

- ⬜ EBS root volume อย่างน้อย **200 GiB** และขยาย ext4 filesystem แล้ว (`df -hT /` ต้องเห็นขนาดใหม่)
- ⬜ เปิด TCP 22 (เฉพาะผู้ดูแล), 80 และ 443 ใน AWS Security Group
- ⬜ ตั้ง `admin.bevorax.com`, `merchant.bevorax.com`, `api.bevorax.com` ไปยัง public IP ของ EC2; ใช้ Cloudflare Proxy ได้
- ⬜ Repository `https://github.com/bio-vanta/please-payment-k3s-biovanta.git` ต้องอ่านได้จาก EC2/Argo CD (public หรือมี read-only credential)
- ⬜ ไม่เปิด Gitea หรือ `git-sync-job.yaml` ใน flow นี้

## 1. Clone และติดตั้ง K3s

```bash
sudo apt update && sudo apt install -y git curl ca-certificates
mkdir -p ~/please-payment && cd ~/please-payment
git clone --branch main --single-branch https://github.com/bio-vanta/please-payment-k3s-biovanta.git
cd please-payment-k3s-biovanta
sudo mkdir -p /data
sudo bash 00-install-k3s.bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG="$HOME/.kube/config"
kubectl get nodes
```

ต้องได้ node สถานะ `Ready` และ `local-path` เป็น default storage class.

## 2. Prepare secrets และ addons

```bash
cd ~/please-payment/please-payment-k3s-biovanta
umask 077
printf 'DUMMY=demo\nMUTUAL_KEY=%s\n' "$(openssl rand -hex 32)" > .env
chmod 600 .env
bash 01-initial-secrets.bash
bash 02-initial-addons.bash
```

`initial-secret.yaml` ใช้ `biovanta2002/please-protect-jobs:v0.0.14` จาก Docker Hub. อย่าใส่ `DISCORD_WEBHOOK` หรือเปิด Discord จนกว่าจะพร้อมใช้งานจริง.

## 3. Verify core addons

```bash
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=10m
kubectl wait --for=condition=Available deployment/nginx-ingress-nginx-controller -n ingress-nginx --timeout=10m
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=10m
kubectl wait --for=condition=Available deployment/external-secrets -n external-secrets --timeout=10m
```

## 4. Bootstrap applications

```bash
bash 04-boot-strap.bash
kubectl get applications -n argocd
kubectl get certificate -n please-payment-production
```

รอ certificates ทั้งสามเป็น `Ready=True` และ Applications เป็น `Synced/Healthy`. Discord กับ Terminal ถูก defer โดยต้องมี label `discord-enabled=true` หรือ `terminal-enabled=true` จึงจะ deploy.

## 5. Monitoring without Discord

```bash
ENABLE_DISCORD_ALERTS=false bash 03-install-monitoring.bash
kubectl get pods -n monitoring
kubectl get alertmanagerconfig -n monitoring
```

คำสั่งสุดท้ายต้องไม่มี AlertmanagerConfig จนกว่าจะกำหนด Discord webhook แล้วเปิดใช้งานอย่างชัดเจน.

## 6. Acceptance checks

```bash
kubectl get applications -n argocd
kubectl get pods -n please-payment-production
curl -I https://admin.bevorax.com
curl -I https://merchant.bevorax.com
curl -I https://api.bevorax.com
df -hT /
```

Admin และ Merchant ควร redirect ไป `/login`; API root อาจตอบ `404` ได้ตาม route ที่เปิดใช้งาน. ก่อนใช้งาน production ต้องติดตาม disk usage และไม่ควรปล่อยให้ root filesystem ใกล้เต็ม.
