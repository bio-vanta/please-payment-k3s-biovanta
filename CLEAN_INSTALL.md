# Please Payment — clean installation runbook

คู่มือนี้เป็นขั้นตอนติดตั้งใหม่ตั้งแต่เครื่อง Ubuntu EC2 ว่างจนเปิด Please Payment ได้ โดยรวมวิธีป้องกันปัญหาที่พบจากการติดตั้งจริงไว้แล้ว ไม่ใช่เพียง checklist ย่อ

ใช้ repository นี้เป็น source of truth:

```text
https://github.com/bio-vanta/please-payment-k3s-biovanta.git
```

## ภาพรวมของสิ่งที่จะติดตั้ง

```text
Internet / Cloudflare
        │ HTTPS 443, HTTP 80
        ▼
EC2 + K3s + ingress-nginx
        ├── Argo CD ──► GitHub repository นี้ + please-payment-control-plane
        ├── Cert-Manager ──► Let's Encrypt certificates
        ├── Please Payment: Admin, Merchant, API, jobs, PostgreSQL, Redis
        ├── Loki / Grafana
        └── Prometheus / Alertmanager / Grafana
```

Gitea, `git-sync-job.yaml`, Discord alert และ Terminal จะไม่ถูก deploy ใน flow นี้. Argo CD ดึง manifest จาก GitHub โดยตรง.

## 0. Preflight — ต้องผ่านก่อนลง K3s

- ⬜ **Disk:** root EBS volume อย่างน้อย **200 GiB**. Control plane ขอ PVC 113 GiB (PostgreSQL 100 GiB, Redis 8 GiB, GeoIP 5 GiB) และ K3s/images/logs ต้องมีพื้นที่สำรองเพิ่ม
- ⬜ **AWS Security Group:** เปิด TCP 22 เฉพาะ IP ผู้ดูแล และ TCP 80/443 สำหรับ Internet
- ⬜ **Repository access:** `https://github.com/bio-vanta/please-payment-k3s-biovanta.git` ต้อง public หรือ Argo CD ต้องมี read-only credential
- ⬜ **DNS:** `admin.bevorax.com`, `merchant.bevorax.com`, `api.bevorax.com` ชี้ไป public IP ของ EC2
- ⬜ **Cloudflare:** ใช้ Proxy mode ได้; ตรวจว่า Cloudflare ติดต่อ origin ที่ TCP 80/443 ได้
- ⬜ **Docker Hub:** EC2 ต้อง pull `biovanta2002/please-protect-jobs:v0.0.14` ได้

ตรวจ disk หลังสร้าง EC2 หรือหลังขยาย EBS:

```bash
df -hT /
lsblk -f
```

หาก volume ถูกขยายแต่ filesystem ยังไม่โต ให้ขยาย partition/filesystem ตาม device ของเครื่องก่อนเริ่ม เช่นบน Ubuntu EC2 ที่ root เป็น `/dev/xvda1`:

```bash
sudo growpart /dev/xvda 1
sudo resize2fs /dev/xvda1
df -hT /
```

> ตรวจชื่อ device ด้วย `lsblk` ก่อนเสมอ; อย่า copy คำสั่ง `growpart` หากชื่อ disk/partition ไม่ตรง.

## 1. เข้าเครื่องและติดตั้งเครื่องมือพื้นฐาน

จาก Git Bash:

```bash
ssh -i "/c/Users/Bilbong/Documents/Bio-Vanta/please-payment/please-payment-bevorax-ssh.pem" ubuntu@<EC2_PUBLIC_IP>
```

บน EC2:

```bash
sudo apt update
sudo apt install -y git curl ca-certificates
git --version
curl --version
```

ผลที่คาดหวัง: คำสั่งทั้งสองแสดง version และไม่มี apt error.

## 2. Clone repository และตรวจ environment config

```bash
mkdir -p ~/please-payment
cd ~/please-payment
git clone --branch main --single-branch https://github.com/bio-vanta/please-payment-k3s-biovanta.git
cd please-payment-k3s-biovanta
git status --short --branch
git log -1 --oneline
```

ตรวจค่าที่ต้องใช้ใน environment นี้:

```bash
cat 99-deployments/manifests/please-payment/values.yaml
grep -n 'email:' 01-bootstrap/cluster-issuer.yaml
grep -n 'image:' 00-configs/initial-secret.yaml
```

ค่าที่ต้องเห็น:

```yaml
domain1: admin.bevorax.com
domain2: merchant.bevorax.com
domain3: api.bevorax.com
```

- `cluster-issuer.yaml` ใช้ email `phanuwat.p2002@gmail.com`
- `initial-secret.yaml` ใช้ `biovanta2002/please-protect-jobs:v0.0.14`

หากใช้ environment อื่น ให้เปลี่ยน domains และ Let’s Encrypt email ใน repository, commit/push ไป `main`, แล้วค่อย install. Argo CD จะใช้ GitHub remote ไม่ใช่ file ที่แก้ค้างไว้เฉพาะบน EC2.

## 3. ติดตั้ง K3s และตั้งค่า kubectl

```bash
cd ~/please-payment/please-payment-k3s-biovanta
sudo mkdir -p /data
sudo bash 00-install-k3s.bash

mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG="$HOME/.kube/config"
grep -qxF 'export KUBECONFIG="$HOME/.kube/config"' ~/.bashrc || \
  echo 'export KUBECONFIG="$HOME/.kube/config"' >> ~/.bashrc

kubectl get nodes -o wide
kubectl get pods -n kube-system
kubectl get storageclass
```

ผลที่ต้องผ่าน:

- node เป็น `Ready`
- `coredns`, `metrics-server`, `local-path-provisioner` เป็น `Running`
- `local-path` เป็น default StorageClass

## 4. ติดตั้ง Helm และสร้าง initial secrets

ติดตั้ง Helm สำหรับ monitoring:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
helm version --short
```

สร้าง `.env` โดยไม่ commit ไฟล์นี้:

```bash
cd ~/please-payment/please-payment-k3s-biovanta
umask 077
printf 'DUMMY=demo\nMUTUAL_KEY=%s\n' "$(openssl rand -hex 32)" > .env
chmod 600 .env
cut -d= -f1 .env
```

`MUTUAL_KEY` เป็น shared secret ระหว่าง services. อย่าแสดงหรือส่งค่าออกจาก server. Discord ยังไม่ต้องใส่ `DISCORD_WEBHOOK` ในขั้นนี้.

รัน initial secret job:

```bash
bash 01-initial-secrets.bash
kubectl wait --for=condition=complete job/secret-init -n default --timeout=5m
kubectl get secret initial-secret initial-secret-preset -n default
```

ผลที่ต้องผ่าน: `initial-secret` และ `initial-secret-preset` มีอยู่. Job ต้อง pull Docker Hub image ได้. ข้อความ `jobs.batch "secret-init" not found` ตอนเริ่ม script ครั้งแรกเป็นผลปกติจากการพยายามลบ job เก่า.

## 5. ติดตั้ง core addons

```bash
cd ~/please-payment/please-payment-k3s-biovanta
bash 02-initial-addons.bash

kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=10m
kubectl wait --for=condition=Available deployment/nginx-ingress-nginx-controller -n ingress-nginx --timeout=10m
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=10m
kubectl wait --for=condition=Available deployment/external-secrets -n external-secrets --timeout=10m
kubectl get pods -A
```

ขั้นนี้ติดตั้ง Argo CD, ingress-nginx, cert-manager และ external-secrets เท่านั้น. Gitea ยังถูก comment ไว้ และ `git-sync-job.yaml` ไม่ถูกเรียกใช้.

## 6. Bootstrap application deployment

ก่อนรัน ให้ตรวจ DNS จาก EC2:

```bash
for host in admin.bevorax.com merchant.bevorax.com api.bevorax.com; do
  getent ahostsv4 "$host" | head -n 1
done
```

หากใช้ Cloudflare Proxy จะเห็น IP ของ Cloudflare เป็นผลปกติ. จากนั้น bootstrap:

```bash
cd ~/please-payment/please-payment-k3s-biovanta
bash 04-boot-strap.bash
kubectl get applications,applicationsets -n argocd
kubectl get certificate -n please-payment-production
```

รอ sync:

```bash
kubectl get applications -n argocd -w
```

ผลที่ต้องผ่าน:

- `bootstrap-data-plane`, `bootstrap-please-payment-prod`, `cert-manager-main`, `external-secrets-main`, `loki-log-main`, `please-payment-custom-main` เป็น `Synced` และ `Healthy`
- `admin-cert`, `merchant-cert`, `api-cert` เป็น `Ready=True`
- pods ใน `please-payment-production` เป็น `Running`; API/jobs อาจ restart ระหว่าง PostgreSQL migrations ช่วงแรก แต่ต้อง stabilise หลัง database พร้อม

Discord และ Terminal ถูก defer โดย ApplicationSet selector. จะไม่สร้าง Application จนกว่าจะใส่ label `discord-enabled=true` หรือ `terminal-enabled=true` ให้ cluster secret ใน namespace `argocd`.

## 7. ติดตั้ง monitoring โดยไม่เปิด Discord

```bash
cd ~/please-payment/please-payment-k3s-biovanta
ENABLE_DISCORD_ALERTS=false bash 03-install-monitoring.bash

kubectl get pods -n monitoring
kubectl get prometheus,alertmanager -n monitoring
kubectl get alertmanagerconfig -n monitoring
```

รอบแรกของ script อาจรายงานว่า Prometheus CRD ยังไม่พร้อม; script จะ apply รอบที่สองให้อัตโนมัติ. ผลสุดท้ายต้องมี Prometheus/Alertmanager `AVAILABLE=True`, Grafana pod `Running` และไม่มี `AlertmanagerConfig` ใน namespace `monitoring` เพราะ Discord ถูก defer.

## 8. ตรวจ website และ acceptance

```bash
kubectl get ingress,certificate,svc -n please-payment-production
kubectl wait --for=condition=Ready certificate/admin-cert -n please-payment-production --timeout=5m
kubectl wait --for=condition=Ready certificate/merchant-cert -n please-payment-production --timeout=5m
kubectl wait --for=condition=Ready certificate/api-cert -n please-payment-production --timeout=5m

for url in \
  https://admin.bevorax.com \
  https://merchant.bevorax.com \
  https://api.bevorax.com \
  https://admin.bevorax.com/tools/argocd; do
  printf '%s: ' "$url"
  curl -sSIL --max-time 20 -o /dev/null -w '%{http_code}\n' "$url"
done
```

ผลที่คาดหวัง:

| URL | ผลที่ถูกต้อง |
| --- | --- |
| `https://admin.bevorax.com` | `200` หลัง follow redirect หรือหน้า login |
| `https://merchant.bevorax.com` | `200` หลัง follow redirect หรือหน้า login |
| `https://api.bevorax.com` | `404` ที่ root path เป็นปกติ หากไม่มี root route |
| `https://admin.bevorax.com/tools/argocd` | `200` |

ตรวจพื้นที่ disk ก่อนส่งมอบ:

```bash
df -hT /
sudo du -sh /var/lib/rancher/k3s /data 2>/dev/null
kubectl get pvc -n please-payment-production
```

หาก disk ไม่ถึง 200 GiB อย่าใช้งาน production ต่อ แม้ PVC จะขึ้น `Bound` แล้วก็ตาม เพราะ local-path ไม่ reserve พื้นที่จริง.

## Optional: เปิด Discord หรือ Terminal ภายหลัง

Discord ต้องสร้าง `DISCORD_WEBHOOK` ใน `initial-secret-preset` และเปิด label ก่อน:

```bash
kubectl label secret local-cluster-secret -n argocd discord-enabled=true
```

Terminal ต้องมี Docker Hub image ที่ pull ได้หรือ Artifact Registry credential ก่อน แล้วจึงเปิด:

```bash
kubectl label secret local-cluster-secret -n argocd terminal-enabled=true
```

หลังเปิด label ให้รอ Argo CD ApplicationSet สร้าง Application และตรวจ pod/events ก่อนใช้งาน.
