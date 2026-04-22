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

## 5. Чеклист (базовий)

- [ ] OCI Security List: додано 10.244.0.0/16 (варіант A) **або**
- [ ] Cilium переведено на VXLAN (варіант B)
- [ ] ipv4NativeRoutingCIDR відповідає cluster-cidr (варіант C)
- [ ] k3s встановлено з `--disable-kube-proxy`
- [ ] `kubectl run test-dns ... nslookup kube-dns` — успішно

---

## 6. Важливо: перевірка на **всіх** нодах кластера

Цей документ і команди вище стосуються переважно пари **master-node ↔ work-node** (OCI). Якщо в кластері є інші ноди (**beelinkeqr5**, **macmini7** тощо), після VXLAN або Security List потрібна **повна перевірка** — інакше поди на цих нодах можуть не досягати API server або подів на інших нодах (наприклад CoreDNS дасть `dial tcp 10.96.0.1:443: i/o timeout`).

**Остаточний чеклист** (Cilium + CoreDNS для всіх нод): див. **[CILIUM_COREDNS_FINAL_VERIFICATION.md](CILIUM_COREDNS_FINAL_VERIFICATION.md)** — нумеровані кроки перевірки з точними командами. **Встановлення Cilium CLI** (для `cilium status` та `cilium connectivity test`): **[cilium/install-cilium-cli.sh](cilium/install-cilium-cli.sh)**.

**Що перевірити з поду на кожній ноді:**

1. **Доступ до Kubernetes API** (потрібен для CoreDNS watch):
   ```bash
   for NODE in master-node work-node beelinkeqr5 macmini7; do
     echo "=== $NODE ==="
     kubectl run curl-api-$NODE --rm -i --restart=Never --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" --image=curlimages/curl -- \
       curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://10.96.0.1:443/version 2>/dev/null || echo "timeout/fail"
   done
   ```
   Очікується: HTTP код (наприклад 403), не таймаут.

2. **Pod-to-pod** (наприклад DNS) — под на конкретній ноді:
   ```bash
   kubectl run test-dns-beelinkeqr5 --image=busybox:1.36 --restart=Never --overrides='{"spec":{"nodeName":"beelinkeqr5"}}' -- nslookup kube-dns.kube-system.svc.cluster.local
   kubectl logs test-dns-beelinkeqr5
   kubectl delete pod test-dns-beelinkeqr5
   ```
   Аналогічно для інших нод — замінити `nodeName` на `master-node`, `work-node`, `macmini7`.

3. **Cilium connectivity test** (якщо встановлено cilium CLI):
   ```bash
   cilium connectivity test
   ```
   Переконайтеся, що тест проходить між усіма парами нод, а не лише OCI.

Якщо з поду на **beelinkeqr5** (або macmini7) до 10.96.0.1 таймаут — VXLAN-трафік між цією нодою та нодою з API server (наприклад master-node) не проходить: firewall між мережами (Syhiv17/VRN625 ↔ OCI) має дозволяти **VXLAN UDP 4789** між node IP, або потрібно перевірити маршрути/WireGuard тощо.
