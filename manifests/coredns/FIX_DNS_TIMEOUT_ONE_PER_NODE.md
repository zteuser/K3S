# DNS "connection timed out" — обхід через Local traffic

## Проблема

Под у default (або іншому namespace) при `nslookup kube-dns.kube-system.svc.cluster.local` отримує **connection timed out; no servers could be reached**. Причина: трафік до ClusterIP kube-dns (10.96.0.10) йде на backend (pod CoreDNS) на іншій ноді, а cross-node трафік 10.244.x.x блокується (OCI Security List або відсутні маршрути до on-prem).

## Рішення (без зміни OCI / маршрутів)

1. **Один CoreDNS на кожну ноду** — topology spread по `kubernetes.io/hostname`, 4 репліки.
2. **internalTrafficPolicy: Local** для сервісу `kube-dns` — трафік до 10.96.0.10 йде лише на под CoreDNS на тій самій ноді, без cross-node.

Таким чином DNS не використовує міжнодову мережу для pod IP.

### Застосування

```bash
kubectl patch deployment coredns -n kube-system --patch-file=manifests/coredns/coredns-one-per-node-patch.yaml
kubectl patch svc kube-dns -n kube-system -p '{"spec":{"internalTrafficPolicy":"Local"}}'
```

Дочекатися, поки поди CoreDNS будуть Ready на всіх нодах (або принаймні на тих, де запускаються workload).

### Перевірка

Якщо под потрапляє на ноду без Ready CoreDNS (macmini7, іноді beelinkeqr5), DNS поверне *connection timed out* або *Operation not permitted*. Для гарантованої перевірки прив’яжіть тест до ноди з Ready CoreDNS (master-node або work-node):

```bash
# Варіант 1: прив’язка до master-node (завжди є Ready CoreDNS)
kubectl run test-dns --rm -i --restart=Never --image=busybox:1.36 --overrides='{"spec":{"nodeName":"master-node"}}' -- nslookup kube-dns.kube-system.svc.cluster.local

# Варіант 2: без прив’язки (працює, якщо под потрапить на master-node або work-node)
kubectl run test-dns --rm -i --restart=Never --image=busybox:1.36 -- nslookup kube-dns.kube-system.svc.cluster.local
```

Очікується: вивід з Address 10.96.0.10, без timeout.

### Важливо

- На нодах, де под CoreDNS не стає Ready (немає маршруту до Kubernetes API 10.96.0.1), поди на цій ноді не матимуть DNS (internalTrafficPolicy: Local → немає локального endpoint).
- Зараз Ready CoreDNS є на **master-node** та **work-node**; на **macmini7** та частині **beelinkeqr5** — часто не Ready (i/o timeout до API). Тому тест без `nodeName` може падати, якщо под потрапить на macmini7/beelinkeqr5.
- Повне вирішення: OCI Security List + маршрути до API та pod CIDR (див. `manifests/OCI_SECURITY_LIST_MANUAL_STEPS.md`); тоді CoreDNS на всіх нодах стане Ready і DNS працюватиме скрізь.
