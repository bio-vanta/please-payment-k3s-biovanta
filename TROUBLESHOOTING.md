# Troubleshooting log

บันทึกนี้เก็บปัญหาที่พบระหว่างติดตั้งตาม `INSTALLATION_CHECKLIST.md` พร้อมหลักฐานและผลหลังแก้ไข

## P-001 — DNS ของ bevorax.com ยังไม่ชี้ไปที่ EC2 ใหม่

- **ขั้นที่พบ:** ก่อน bootstrap Argo CD / Certificate
- **อาการ:** การ resolve DNS จาก EC2 เมื่อ 2026-09-22 ได้ผลดังนี้

  ```text
  admin.bevorax.com     -> 104.155.134.15
  merchant.bevorax.com  -> 104.155.134.15
  api.bevorax.com       -> 104.155.134.15
  ```

  แต่ server ที่ติดตั้ง K3s มี public IP `54.254.254.50`.

- **ผลกระทบ:** Ingress ที่ตั้งค่าเป็น `admin.bevorax.com`, `merchant.bevorax.com` และ `api.bevorax.com` จะยังไม่รับ traffic ของ server ใหม่ และ cert-manager จะไม่สามารถผ่าน Let’s Encrypt HTTP-01 challenge บน EC2 นี้ได้
- **สาเหตุ:** A record ของทั้งสาม subdomain ยังคงชี้ไปยัง infrastructure เดิม
- **สิ่งที่ตรวจแล้ว:** EC2 `54.254.254.50` รับ TCP 80 และ 443 ได้จากภายนอกแล้ว จึงไม่พบการ block ที่ port สาธารณะในเส้นทางที่ทดสอบ
- **วิธีแก้:** ที่ DNS provider ของ `bevorax.com` เปลี่ยนหรือสร้าง A record ต่อไปนี้ให้ชี้ `54.254.254.50`:

  | Name | Type | Value |
  | --- | --- | --- |
  | `admin` | A | `54.254.254.50` |
  | `merchant` | A | `54.254.254.50` |
  | `api` | A | `54.254.254.50` |

  หากใช้ Cloudflare ให้เลือกโหมด DNS only เพื่อใช้ certificate จาก cert-manager หรือใช้ Proxy mode พร้อมกำหนด SSL/TLS mode ให้เหมาะสม. AWS Security Group ต้องเปิด TCP 80 และ 443 มายัง EC2 ด้วย.

- **สถานะ:** แก้ไขแล้ว
- **ผลหลังแก้:** หลังผู้ใช้เปลี่ยน DNS, ทั้งสาม host resolve ผ่าน Cloudflare Proxy (`104.21.79.68`, `172.67.169.60`) และการเรียก HTTP/HTTPS ตอบ `404` จาก Cloudflare. ผล `404` เป็นปกติก่อน Please Payment Ingress ถูก deploy และยืนยันว่า Cloudflare ติดต่อ origin ได้. EC2 รับ TCP 80/443 ได้อยู่แล้ว.

## P-002 — Argo CD bootstrap ใช้ GitHub remote ไม่ใช่ working copy บน EC2

- **ขั้นที่พบ:** ก่อน bootstrap Argo CD
- **อาการ:** `04-boot-strap.bash` แก้ `bootstrap-data-plane` ให้ใช้ `https://github.com/wintech-thai/please-payment-k3s-pjp.git`, branch `main`. Working copy ที่แก้ในเครื่อง local/EC2 จึงไม่ใช่ source ที่ Argo CD จะ sync.
- **ผลกระทบ:** หาก bootstrap ตอนนี้ Argo CD จะใช้ค่าเดิมบน GitHub ได้แก่ Docker image จาก Google Artifact Registry และ domains เดิม `*.sgdwallets.com`; การแก้ `biovanta2002/please-protect-jobs` และ `*.bevorax.com` จะไม่ถูกนำไปใช้.
- **สาเหตุ:** flow นี้ตั้งใจให้ deploy จาก GitHub remote โดยตรง และ Gitea/git-sync ถูกปิดอยู่.
- **วิธีแก้:** publish การเปลี่ยนแปลงที่ตรวจทานแล้วไปยัง `origin/main` ของ `bio-vanta/please-payment-k3s-biovanta` ก่อน bootstrap และชี้ Argo CD ไปยัง repository นี้. การเปลี่ยนแปลงที่ต้อง publish คือ:

  | File | การเปลี่ยนแปลง |
  | --- | --- |
  | `00-configs/initial-secret.yaml` | ใช้ `biovanta2002/please-protect-jobs:v0.0.14` |
  | `99-deployments/manifests/please-payment/values.yaml` | เปลี่ยน domains เป็น `*.bevorax.com` |
  | `INSTALLATION_CHECKLIST.md` | คู่มือติดตั้งและสถานะ checklist |
  | `TROUBLESHOOTING.md` | บันทึกปัญหาและแนวทางแก้ |

  การ commit/push ต้องได้รับการยืนยันอย่างชัดเจนจากผู้ใช้ก่อนดำเนินการ.
- **สถานะ:** รออนุมัติ commit และ push ไป `origin/main`
- **ผลหลังแก้:** รอการตรวจสอบ
