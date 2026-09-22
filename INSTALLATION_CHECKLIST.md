# Please Payment — installation checklist (Ubuntu EC2)

คู่มือนี้ติดตั้ง K3s และ deployment configuration จาก repository นี้บน Ubuntu EC2 แบบ single node จนเปิดหน้า Please Payment ได้

> สถานะล่าสุดที่ตรวจเมื่อ 2026-09-22: เชื่อมต่อ SSH ไปที่ `54.254.254.50` ได้แล้ว, เป็น Ubuntu, root disk 48 GB เหลือประมาณ 46 GB และยังไม่มี K3s ติดตั้งอยู่

## Prerequisites

- [x] SSH เข้าเครื่องด้วย user `ubuntu` ได้
- [x] EC2 มี root disk 48 GB (เหมาะกับ config ปัจจุบัน; แนะนำ 60 GB สำหรับ buffer ระยะยาว)
- [ ] Security Group เปิด TCP `22` เฉพาะ IP ผู้ดูแล และเปิด TCP `80`, `443` สำหรับผู้ใช้งาน/Let’s Encrypt
- [x] DNS A records ของโดเมนที่กำหนดใน `domain1`–`domain3` ชี้ไปที่ public IP `54.254.254.50`
- [x] EC2 สามารถ pull `biovanta2002/please-protect-jobs:v0.0.14` จาก Docker Hub ได้
- [ ] EC2 สามารถ pull image ของ `please-payment-control-plane` ได้
- [ ] มีค่า secret สำหรับสร้างไฟล์ `.env` (ห้าม commit หรือส่งไฟล์นี้เข้าระบบ version control)

เชื่อมต่อเครื่องจาก Git Bash:

```bash
ssh -i "/c/Users/Bilbong/Documents/Bio-Vanta/please-payment/please-payment-bevorax-ssh.pem" ubuntu@54.254.254.50
```

## ค่าที่ผู้ใช้ template ต้องกำหนด

ทำรายการนี้ก่อนเริ่มติดตั้ง เพื่อไม่ให้ใช้ค่าโดเมน, email หรือ secret ของ environment เดิมโดยไม่ตั้งใจ

- [ ] แก้ `.env` (เป็น secret ห้าม commit)

```dotenv
# ค่าความเข้ากันได้กับ initial-secret flow; ใช้ค่า non-secret ได้
DUMMY=demo

# shared secret สำหรับการสื่อสารระหว่าง services ของ Please Payment
# สร้างค่าใหม่ที่เดายาก และใช้ค่าเดียวกันกับ control-plane ของ environment นี้
MUTUAL_KEY=<generate-a-new-random-secret>

# Discord Incoming Webhook สำหรับ alertmanager-discord
DISCORD_WEBHOOK=https://discord.com/api/webhooks/<webhook-id>/<webhook-token>
```

`01-initial-secrets.bash` รับ key/value ทุกตัวใน `.env` แล้วสร้าง secret `initial-secret-preset`; ใน repo นี้ `DISCORD_WEBHOOK` ถูกอ่านโดย `discord-alm` โดยตรง. `MUTUAL_KEY` เป็นค่าที่ control-plane ของ Please Payment ต้องใช้ร่วมกัน แม้ไม่ได้อ้างอิงจาก manifest ใน repo นี้โดยตรง. สร้างค่า `MUTUAL_KEY` ใหม่ได้ เช่น:

```bash
openssl rand -hex 32
```

หากยังไม่ต้องการส่ง Discord alert ให้ปิด application `discord-alm` ใน `99-deployments/applications/app-discord-alm.yaml` แทนการใส่ URL ปลอม; มิฉะนั้นใส่ webhook ที่ใช้งานได้.

- [x] เปลี่ยนโดเมน 3 ค่าใน `99-deployments/manifests/please-payment/values.yaml`

```yaml
domain1: admin.yourdomain.com
domain2: merchant.yourdomain.com
domain3: api.yourdomain.com
```

ค่าเหล่านี้ถูกใช้สร้าง Ingress และ Certificate ของ Admin, Merchant และ API โดยอัตโนมัติ. Repository เวอร์ชันนี้ **ยังไม่มี `domain4` หรือ Ingress สำหรับ `docs.yourdomain.com`** แม้คู่มือบนเว็บที่ใช้อ้างอิงจะกล่าวถึง 4 subdomains; การเพิ่มแค่ `domain4` ใน values จะยังไม่มีผล ต้องเพิ่ม Ingress/Certificate สำหรับ service เอกสารด้วยก่อน.

- [x] เปลี่ยน email ของ Let’s Encrypt ใน `01-bootstrap/cluster-issuer.yaml` เป็น `phanuwat.p2002@gmail.com`
- [ ] เปลี่ยน `MINIO_ENDPOINT_CUSTOM` ใน `99-deployments/manifests/please-payment/templates/storage-config-cm.yaml` ให้เป็น endpoint object storage ที่ใช้จริง หรือเก็บค่า placeholder นี้ไว้เฉพาะกรณีที่ระบบไม่ได้ใช้ MinIO/S3 แบบ custom endpoint
- [ ] ตรวจ branch `production` และ Helm values ใน repository `please-payment-control-plane`: `01-bootstrap/argocd-bootstrap-please-payment-prod.yaml` จะให้ Argo CD deploy แอปจริงจาก repo นั้น ไม่ได้อยู่ใน repo นี้

## 1. เตรียมเครื่องและ pull code

- [x] ติดตั้ง dependencies

```bash
sudo apt update
sudo apt install -y git curl ca-certificates
```

- [x] Clone repository และเลือก branch `main`

```bash
mkdir -p ~/please-payment
cd ~/please-payment
git clone https://github.com/bio-vanta/please-payment-k3s-biovanta.git
cd please-payment-k3s-biovanta
git switch main
git pull --ff-only origin main
```

ตรวจสอบว่า repository ไม่มีการแก้ไขที่ไม่ตั้งใจ:

```bash
git status --short --branch
```

## 2. ติดตั้ง K3s และตั้งค่า kubectl

- [x] สร้าง directory สำหรับ local Persistent Volume
- [x] ติดตั้ง K3s แบบ single-node พร้อมปิด Traefik (ใช้ NGINX Ingress จาก repo แทน)

```bash
cd ~/please-payment/please-payment-k3s-biovanta
sudo mkdir -p /data
sudo bash 00-install-k3s.bash
```

ตั้งค่า kubeconfig สำหรับ user `ubuntu` แล้วตรวจสอบ node:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG="$HOME/.kube/config"
echo 'export KUBECONFIG="$HOME/.kube/config"' >> ~/.bashrc
kubectl get nodes -o wide
```

ผลลัพธ์ที่ต้องได้คือ node สถานะ `Ready`.

## 3. ติดตั้ง Helm และสร้าง secrets

- [x] ติดตั้ง Helm (จำเป็นสำหรับ monitoring script)

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

- [x] สร้างไฟล์ `.env` จาก secret ที่ได้รับ โดยหนึ่งบรรทัดต่อหนึ่งค่าในรูปแบบ `KEY=value`

```bash
cd ~/please-payment/please-payment-k3s-biovanta
nano .env
chmod 600 .env
```

`01-initial-secrets.bash` จะอ่านทุก key ใน `.env` ไปสร้าง Kubernetes Secret ชื่อ `initial-secret-preset` ใน namespace `default` ดังนั้นต้องตรวจสอบชื่อ key และค่าให้ตรงกับ environment ก่อนทำต่อ. ดูรูปแบบที่ต้องใช้ในหัวข้อ “ค่าที่ผู้ใช้ template ต้องกำหนด”.

- [x] สร้าง initial secrets

```bash
./01-initial-secrets.bash
kubectl get secret initial-secret initial-secret-preset -n default
```

Job `secret-init` ใช้ image `biovanta2002/please-protect-jobs:v0.0.14` จาก Docker Hub. จึงไม่ต้องมี Google Artifact Registry credential สำหรับขั้นนี้.

หากคำสั่งรอ `GIT_USER` ไม่สิ้นสุด ให้ตรวจ job และ log ก่อนดำเนินการต่อ:

```bash
kubectl get jobs,pods -n default
kubectl logs job/secret-init -n default
```

## 4. ติดตั้ง platform addons

- [x] ติดตั้ง Argo CD, NGINX Ingress, External Secrets และ Cert-Manager

```bash
cd ~/please-payment/please-payment-k3s-biovanta
./02-initial-addons.bash
kubectl get helmcharts -n kube-system
kubectl get pods -A
```

รอจน pods หลักเป็น `Running` หรือ `Completed`:

```bash
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=10m
kubectl wait --for=condition=Available deployment/nginx-ingress-nginx-controller -n ingress-nginx --timeout=10m
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=10m
```

Gitea ถูกปิดไว้ใน `02-initial-addons.bash` และ `git-sync-job.yaml` ไม่ได้ถูก apply ใน bootstrap flow โดยตั้งใจ. Argo CD ของ installation นี้ดึง manifest จาก GitHub remote โดยตรง จึงไม่ต้องใช้ Git server ภายใน cluster และไม่สร้าง PVC ของ Gitea ขนาด 10 GiB. หากจะเปลี่ยนไปใช้ Gitea ภายหลัง ต้องเปิดทั้ง Gitea และ git-sync flow พร้อมตรวจชื่อ source/destination repository ก่อน.

### หน้าที่ของ addon หลัก

| Addon | ทำเพื่ออะไร | ผลที่ต้องตรวจ |
| --- | --- | --- |
| Argo CD | ดึง manifest/Helm values จาก Git และ sync แอปให้ตรงกับ source | Application เป็น `Synced` / `Healthy` |
| ingress-nginx | รับ HTTP/HTTPS ที่ port 80/443 แล้วส่งต่อไป service ภายใน | Ingress มี address และเข้าถึงจาก public network ได้ |
| cert-manager | ขอและต่ออายุ TLS certificate จาก Let’s Encrypt | Certificate เป็น `Ready=True` |
| external-secrets | คัดลอก secret จาก `default/initial-secret-preset` ไปยัง namespace ที่ addon ใช้ | Secret ปลายทางถูกสร้าง |

## 5. Bootstrap Argo CD และ Please Payment

- [ ] ยืนยันว่า repo `please-payment-control-plane` และ application image registries เข้าถึงได้จาก EC2
- [x] Bootstrap Argo CD

```bash
cd ~/please-payment/please-payment-k3s-biovanta
./04-boot-strap.bash
```

สคริปต์นี้ปรับ `repoURL` ใน manifest bootstrap ให้ใช้ GitHub remote แล้ว apply Argo CD Application/ApplicationSet. หลังรันจึงอาจเห็นไฟล์ที่ถูกแก้ไขใน `git status`; อย่า commit ค่าที่มี secret หรือ URL เฉพาะ environment โดยไม่ตรวจทาน

ขั้นตอนนี้สำคัญเพราะเป็นจุดที่ Argo CD เริ่ม deploy ทั้ง data plane (Ingress, Certificate, Loki, Discord alert, config เสริม) และ control plane (Admin, Merchant, API, jobs, Redis, PostgreSQL). ไฟล์ `argocd-cluster-secret.yaml` ติด label `custom: "true"` ให้ cluster เพื่อให้ ApplicationSet เลือก cluster นี้ได้; หาก label นี้หาย addons ภายใต้ ApplicationSet จะไม่ถูก deploy.

- [x] ตรวจสถานะ Argo CD และ application deployments

```bash
kubectl get applications,applicationsets -n argocd
kubectl get pods -n please-payment-production -w
```

รอจน application ที่เกี่ยวข้องเป็น `Synced` และ `Healthy`. หากไม่ healthy ให้ดูรายละเอียด:

```bash
kubectl describe application bootstrap-please-payment-prod -n argocd
kubectl get events -n please-payment-production --sort-by=.lastTimestamp
```

## 6. ติดตั้ง monitoring และ logging (เลือกใช้ แต่รวมอยู่ใน addons ของ repo)

> Discord alert และ Terminal ถูก defer ใน environment นี้: ApplicationSet จะยังไม่สร้าง application จนกว่า cluster secret ใน namespace `argocd` จะมี label `discord-enabled=true` หรือ `terminal-enabled=true`. Discord ต้องกำหนด `DISCORD_WEBHOOK` ก่อนเปิดใช้; Terminal ต้องเปลี่ยน image ไปเป็น image ที่ pull ได้ หรือกำหนด Artifact Registry credential ก่อนเปิดใช้.

- [x] ติดตั้ง Prometheus/Grafana

```bash
cd ~/please-payment/please-payment-k3s-biovanta
./03-install-monitoring.bash
kubectl get pods -n monitoring
```

ค่า default จะไม่ apply `AlertmanagerConfig` สำหรับ Discord. เมื่อกำหนด `DISCORD_WEBHOOK` และเปิด Discord ApplicationSet แล้ว จึงค่อยรัน `ENABLE_DISCORD_ALERTS=true ./03-install-monitoring.bash`.

- [x] ตรวจ Loki/Grafana ที่ Argo CD deploy

```bash
kubectl get pods -n loki-log
```

ข้อควรทราบ: Loki ใน repo ตั้ง `persistence.enabled: false` และ Prometheus/Grafana ไม่มี PVC ใน values ปัจจุบัน ข้อมูล log/metrics จึงไม่คงอยู่หลัง pod ถูกสร้างใหม่ หากต้องการใช้งาน production ระยะยาวให้เพิ่ม PVC, retention และขยาย disk ก่อน

Prometheus เก็บ metrics เพื่อดูสุขภาพ cluster/application, Grafana แสดง dashboard และ Loki/Promtail รวบรวม container logs. `03-monitoring/alm-config.yaml` ส่ง alert ผ่าน service `discord-alm` ภายใน ซึ่งส่งต่อไปยัง `DISCORD_WEBHOOK` ใน `.env`.

## 7. เปิดและตรวจหน้าเว็บ

- [ ] ตรวจ ingress, certificate และ service

```bash
kubectl get ingress -n please-payment-production
kubectl get certificate -n please-payment-production
kubectl get svc -n please-payment-production
```

- [ ] ตรวจ certificate ให้เป็น `Ready=True`

```bash
kubectl wait --for=condition=Ready certificate/admin-cert -n please-payment-production --timeout=10m
kubectl wait --for=condition=Ready certificate/merchant-cert -n please-payment-production --timeout=10m
kubectl wait --for=condition=Ready certificate/api-cert -n please-payment-production --timeout=10m
```

- [x] เข้าเว็บไซต์

  - Admin: `https://admin.yourdomain.com`
  - Merchant: `https://merchant.yourdomain.com`
  - API: `https://api.yourdomain.com`
  - Argo CD: `https://admin.yourdomain.com/tools/argocd`

ทดสอบจาก EC2 ได้ด้วย:

```bash
curl -I https://admin.yourdomain.com
curl -I https://merchant.yourdomain.com
curl -I https://api.yourdomain.com
```

การตั้งค่า DNS มีความสำคัญต่อทั้งการเข้าหน้าเว็บและ HTTP-01 challenge ของ Let’s Encrypt: สร้าง A record สำหรับ 3 domains ข้างต้นให้ชี้ public IP ของ EC2 และเปิด TCP 80/443 ใน AWS Security Group. หากใช้ Cloudflare แบบ proxy, Cloudflare สามารถออก certificate ที่ edge ได้; หากใช้ DNS only ให้ cert-manager บน cluster ขอ certificate เองผ่าน port 80.

## Troubleshooting quick checks

```bash
# ภาพรวม cluster
kubectl get nodes
kubectl get pods -A

# Ingress และ DNS/ACME certificate
kubectl get ingress,certificate,challenge,order -A

# ดู event ล่าสุด
kubectl get events -A --sort-by=.lastTimestamp | tail -n 50

# ตรวจพื้นที่ disk ของ K3s และ local PV
df -hT
sudo du -sh /var/lib/rancher/k3s /data 2>/dev/null
```

หาก certificate ไม่ออก ให้ตรวจว่าทั้งสาม DNS record ชี้มายัง EC2 และ Security Group/Network ACL เปิด TCP 80 แล้ว ก่อนลบหรือสร้าง Certificate ใหม่.
