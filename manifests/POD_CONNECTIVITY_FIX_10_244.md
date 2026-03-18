# Вирішення проблеми доступності pod networks 10.244.0.0/24 ↔ 10.244.1.0/24

> **Пріоритет:** вирішити **перед** відновленням сервісів. Без cross-node pod connectivity CoreDNS, Service mesh та інші поди не працюватимуть коректно.

---

## 1. Симптоми

- **Ping pod-to-pod між нодами:** 100% packet loss
- **DNS з пода на work-node:** `connection timed out; no servers could be reached`
- **Cilium cluster health:** `1/2 reachable`, `work-node: 0/1 endpoints`
- Маршрути на нодах є (`10.244.1.0/24 via 10.0.10.20`, `10.244.0.0/24 via 10.0.10.10`), але пакети не проходять

---

## 2. Root cause

**Native routing** — pod-трафік йде з **pod IP** (10.244.x.x) без маскування. **OCI VCN Security List** фільтрує по source/dest IP. CIDR **10.244.0.0/16** не входить у VCN 10.0.10.0/24, тому пакети з 10.244.x.x **відкидаються** на рівні мережі OCI.

---

## 3. Рішення (пріоритет)

### Варіант A: OCI Security List (рекомендовано)

**Швидко, без змін Cilium.** Додати Ingress-правила для pod network.

| Source CIDR | Destination | Protocol | Port | Опис |
|-------------|-------------|----------|------|------|
| **10.244.0.0/16** | 10.0.10.0/24 | All | All | Pod network → Node network |
| 10.0.10.0/24 | 10.244.0.0/16 | All | All | Node network → Pod network (відповіді) |

**Кроки:**
1. OCI Console → **Networking** → **Virtual Cloud Networks** → [ваш VCN]
2. **Security Lists** → Default Security List (або той, що привʼязаний до subnet з master-node/work-node)
3. **Add Ingress Rules**
4. Source CIDR: `10.244.0.0/16`, Protocol: All, Destination Port Range: All
5. (Опційно) Source CIDR: `10.0.10.0/24` для повної взаємодії

**Перевірка після зміни:**
```bash
kubectl run test-dns --image=busybox:1.36 --restart=Never -- nslookup kube-dns.kube-system.svc.cluster.local
kubectl logs test-dns
kubectl delete pod test-dns
```

---

### Варіант B: VXLAN (тунель)

Pod-трафік інкапсульований — зовнішній IP = node IP (10.0.10.x). OCI Security List бачить лише 10.0.10.x, не 10.244.x.x.

**Кроки:**
```bash
helm upgrade cilium cilium/cilium -n kube-system \
  -f manifests/cilium/values-k3s.yaml \
  -f manifests/cilium/values-k8s-vxlan.yaml
```

**values-k8s-vxlan.yaml** (вже є):
```yaml
tunnelProtocol: "vxlan"
routingMode: tunnel
autoDirectNodeRoutes: false
```

**Мінус:** додатковий overhead інкапсуляції; для OCI 2 нод — прийнятно.

---

### Варіант C: ipv4NativeRoutingCIDR — перевірка

Якщо кластер використовує **10.244.0.0/16** для pod, а в `values-k3s.yaml` вказано `10.42.0.0/16` — Cilium не оброблятиме 10.244 як native routing.

**Виправити в values-k3s.yaml:**
```yaml
ipv4NativeRoutingCIDR: "10.244.0.0/16"
```

**ipMasqAgent.config.nonMasqueradeCIDRs** — додати:
```yaml
- 10.244.0.0/16   # Pod network
- 10.244.240.0/20 # Service network (якщо використовується)
```

Потім:
```bash
helm upgrade cilium cilium/cilium -n kube-system -f manifests/cilium/values-k3s.yaml
```

---

## 4. Додатково: --disable-kube-proxy

Якщо при встановленні Cilium з `kubeProxyReplacement: true` **не** використовувався `--disable-kube-proxy` при install k3s — можливий конфлікт iptables і втрата мережі.

**Перевірка на server-нодах:**
```bash
cat /etc/rancher/k3s/config.yaml
# Має бути: disable-kube-proxy: true
# Або в INSTALL_K3S_EXEC: --disable-kube-proxy
```

**Виправлення:** додати в config.yaml і перезапустити k3s (потребує перевстановлення або ручної зміни systemd unit).

---

## 5. Чеклист

- [ ] OCI Security List: додано 10.244.0.0/16 (варіант A) **або**
- [ ] Cilium переведено на VXLAN (варіант B)
- [ ] ipv4NativeRoutingCIDR відповідає cluster-cidr (варіант C)
- [ ] k3s встановлено з `--disable-kube-proxy`
- [ ] `kubectl run test-dns ... nslookup kube-dns` — успішно
