# Діагностика: pod-to-pod між нодами (master-node ↔ work-node)

**Дата:** 2026-03-07

---

## Результати перевірки

### 1. Маршрути — OK

| Нода | Маршрут |
|------|---------|
| master-node | `10.244.1.0/24 via 10.0.10.20 dev enp0s6` |
| work-node | `10.244.0.0/24 via 10.0.10.10 dev enp0s6` |

### 2. Ping pod-to-pod — FAIL

- work-node → 10.244.0.60 (CoreDNS): **100% packet loss**
- master-node → 10.244.1.1: **100% packet loss**

### 3. DNS з pod на work-node — FAIL

```
;; connection timed out; no servers could be reached
```

### 4. Cilium cluster health

```
Cluster health: 1/2 reachable
work-node: 0/1 endpoints
```

---

## Причина

**Native routing** — pod-трафік йде з pod IP (10.244.x.x), без маскування.

**OCI VCN Security List** — фільтрує по source/dest IP. CIDR 10.244.0.0/16 не входить у VCN 10.0.10.0/24, тому пакети з 10.244.x.x можуть відкидатися.

---

## Рішення

### Варіант A: OCI Security List (рекомендовано)

Додати Ingress-правила для subnet з master-node і work-node:

| Source CIDR | Protocol | Port | Опис |
|-------------|----------|------|------|
| 10.244.0.0/16 | All | All | Pod network |
| 10.0.10.0/24 | All | All | Node network (якщо ще немає) |

**OCI Console** → Networking → Virtual Cloud Networks → [ваш VCN] → Security Lists → [Default Security List] → Add Ingress Rules

### Варіант B: VXLAN (тунель)

Змінити Cilium на tunnel mode — pod-трафік буде інкапсульований, зовнішній IP = node IP (10.0.10.x).

```yaml
# values-k8s.yaml
tunnelProtocol: "vxlan"
# Видалити або залишити ipv4NativeRoutingCIDR порожнім
```

Потім: `helm upgrade cilium ... -f values-k8s.yaml`

### Варіант C: Тимчасово вимкнути Hubble

Якщо Hubble не потрібен зараз:

```bash
helm upgrade cilium cilium/cilium -n kube-system -f values-k8s.yaml \
  --set hubble.relay.enabled=false --set hubble.ui.enabled=false
```

---

## Після виправлення

```bash
# Перевірка
kubectl run test-dns --image=busybox:1.36 --restart=Never -- nslookup kube-dns.kube-system.svc.cluster.local
kubectl logs test-dns
kubectl delete pod test-dns
```
