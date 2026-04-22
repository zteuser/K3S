# OCI Security List — ручні кроки (варіант A)

Cilium **VXLAN** (варіант B) уже застосовано. Для повної cross-node доступності між нодами в OCI також додайте правила в Security List (варіант A).

## Кроки в OCI Console

1. Увійдіть в **Oracle Cloud Console** → **Networking** → **Virtual Cloud Networks**.
2. Виберіть VCN, у якому знаходяться **master-node** та **work-node** (наприклад VCN з subnet 10.0.10.0/24).
3. Перейдіть у **Security Lists** → виберіть Security List, прив’язаний до subnet з цими нодами (зазвичай **Default Security List**).
4. **Add Ingress Rules** — додайте **два** правила:

| # | Source CIDR     | Protocol | Destination Port | Опис                    |
|---|-----------------|----------|------------------|-------------------------|
| 1 | **10.244.0.0/16** | All      | All              | Pod network → ноди      |
| 2 | **10.0.10.0/24** | All      | All              | Node network → pod (відповіді) |

5. Збережіть зміни.

---

## Egress: CoreDNS — resolve в internet (8.8.8.8, 1.1.1.1)

Щоб у логах CoreDNS не було **i/o timeout** при запитах до зовнішніх імен (наприклад stats.grafana.org), потрібен **egress** з VCN до публічних DNS.

1. У тому ж Security List (subnet з master-node/work-node) відкрийте **Egress Rules**.
2. Переконайтесь, що є правило (або додайте):

| Destination CIDR | Protocol | Destination Port | Опис |
|------------------|----------|-------------------|------|
| **8.8.8.8/32**   | UDP      | 53                | Google DNS — upstream для CoreDNS |
| **1.1.1.1/32**   | UDP      | 53                | Cloudflare DNS — upstream для CoreDNS |

   Або одне правило на **0.0.0.0/0**, Protocol **UDP**, Port **53**, якщо потрібен egress DNS у будь-який резолвер.

3. **Маршрут до інтернету:** subnet має мати **Route Table** з маршрутом **0.0.0.0/0** → **Internet Gateway** або **NAT Gateway**. Інакше пакети до 8.8.8.8/1.1.1.1 не вийдуть з VCN.

Після змін трафік з подів CoreDNS зможе досягати 8.8.8.8:53 та 1.1.1.1:53, і зовнішній DNS resolve запрацює.

**Важливо:** DNS використовує **UDP** 53 (не TCP). Якщо з ноди `nc -z 8.8.8.8 53` (TCP) проходить, а CoreDNS все одно дає `read udp ...->8.8.8.8:53: i/o timeout`, переконайтесь, що в Egress дозволено саме **Protocol UDP**, Destination Port **53**. Перевірка UDP з ноди (master-node): `echo "" | timeout 2 nc -u 8.8.8.8 53` або `nslookup grafana.io 8.8.8.8`.

## Перевірка після змін

```bash
kubectl run test-dns --rm -i --restart=Never --image=busybox:1.36 -- nslookup kube-dns.kube-system.svc.cluster.local
# Очікується: адреса 10.96.0.10 або подібна, без "connection timed out"
kubectl delete pod test-dns --ignore-not-found
```

Після успішної перевірки в Prometheus → Targets пул **alloy** має показувати більше таргетів у стані UP (залежить від маршрутів до macmini7/beelinkeqr5).
