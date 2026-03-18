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

## Перевірка після змін

```bash
kubectl run test-dns --rm -i --restart=Never --image=busybox:1.36 -- nslookup kube-dns.kube-system.svc.cluster.local
# Очікується: адреса 10.96.0.10 або подібна, без "connection timed out"
kubectl delete pod test-dns --ignore-not-found
```

Після успішної перевірки в Prometheus → Targets пул **alloy** має показувати більше таргетів у стані UP (залежить від маршрутів до macmini7/beelinkeqr5).
