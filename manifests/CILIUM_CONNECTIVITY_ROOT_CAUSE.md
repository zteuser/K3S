# Діагностика причини втрати мережі при старті Cilium

> **Мета:** знайти root cause втрати SSH/connectivity при старті Cilium pod — без reboot і видалення.

---

## 0. Root cause (підтверджено)

**Відсутній `--disable-kube-proxy` при встановленні k3s.**  
При `kubeProxyReplacement: true` в Cilium k3s має запускатись з `--disable-kube-proxy`. Інакше kube-proxy і Cilium одночасно керують iptables → конфлікт правил (TPROXY, ip rules) → втрата мережі.

Джерело: [Cilium K3s Installation](https://docs.cilium.io/en/stable/installation/k3s/)

---

## 1. Гіпотези (з дослідження)

| # | Гіпотеза | Джерело | Що перевірити |
|---|----------|---------|---------------|
| 0 | **L7 Proxy** — TPROXY на порт 40509 (cilium-dns-egress) перехоплює TCP/UDP, ламає host traffic | [cilium#25015](https://github.com/cilium/cilium/issues/25015) | `l7Proxy: false` |
| 1 | **eBPF Host Routing** не враховує kernel routing table — response packets йдуть не туди | [cilium#39806](https://github.com/cilium/cilium/issues/39806) | `bpf.masquerade: false` |
| 2 | **iptables feeder rules** — CILIUM_INPUT/CILIUM_OUTPUT блокують host traffic | Cilium docs | Порівняти iptables до/після |
| 3 | **ip rules** (policy routing) — Cilium додає правила | #39806 | `ip rule` до/після |
| 4 | **BPF masquerade** — помилково впливає на host traffic | #17177, #41866 | `bpf.masquerade: false` |
| 5 | **WireGuard** — Cilium не враховує VPN | #32899, #36491 | devices не включають wg |
| 6 | **--disable-kube-proxy** — обов'язковий при kubeProxyReplacement | [Cilium K3s docs](https://docs.cilium.io/en/stable/installation/k3s/) | Додати до k3s install |
| 7 | **Connectivity loss** — загальна проблема після install | [cilium#33310](https://github.com/cilium/cilium/issues/33310) | ManageForeignRoutes=no (systemd-networkd) |

---

## 2. План діагностики (коли є Console Access)

### 2.1 Перед встановленням Cilium (baseline)

На ноді (master-node через OCI Console Connection або локальні macmini7/beelinkeqr5):

```bash
# Скрипт (копіювати manifests/cilium/diag-capture.sh на ноду):
sudo ./diag-capture.sh before

# Або вручну:
sudo mkdir -p /tmp/cilium-diag
sudo iptables-save > /tmp/cilium-diag/iptables-before.txt 2>/dev/null || sudo iptables-legacy-save > /tmp/cilium-diag/iptables-before.txt
ip rule > /tmp/cilium-diag/ip-rule-before.txt
ip route > /tmp/cilium-diag/ip-route-before.txt
ip addr > /tmp/cilium-diag/ip-addr-before.txt
ip link > /tmp/cilium-diag/ip-link-before.txt
```

### 2.2 Встановити Cilium, дочекатись Running

```bash
helm install cilium ... # як у K3S_FRESH_INSTALL_CILIUM_RESTORE.md
kubectl get pods -n kube-system -l k8s-app=cilium -w  # до Running
```

### 2.3 Після старту Cilium (коли connectivity вже втрачено)

Через **OCI Console Connection** (Serial Console) або **локальний доступ**:

```bash
# Скрипт:
sudo ./diag-capture.sh after

# Або вручну:
sudo iptables-save > /tmp/cilium-diag/iptables-after.txt 2>/dev/null || sudo iptables-legacy-save > /tmp/cilium-diag/iptables-after.txt
ip rule > /tmp/cilium-diag/ip-rule-after.txt
ip route > /tmp/cilium-diag/ip-route-after.txt
ip addr > /tmp/cilium-diag/ip-addr-after.txt

# Cilium status (якщо cilium-dbg доступний)
kubectl -n kube-system exec ds/cilium -- cilium-dbg status 2>/dev/null || true

# BPF програми на інтерфейсах
ip link show enp0s6
tc filter show dev enp0s6 ingress 2>/dev/null
tc filter show dev enp0s6 egress 2>/dev/null
```

### 2.4 Порівняння

```bash
diff /tmp/cilium-diag/iptables-before.txt /tmp/cilium-diag/iptables-after.txt
diff /tmp/cilium-diag/ip-rule-before.txt /tmp/cilium-diag/ip-rule-after.txt
diff /tmp/cilium-diag/ip-route-before.txt /tmp/cilium-diag/ip-route-after.txt
```

---

## 3. Конфігураційні зміни для тестування

### 3.1 Вимкнути BPF masquerade (iptables-based замість eBPF)

У `values-k3s.yaml` або через override:

```bash
helm upgrade cilium cilium/cilium -n kube-system \
  -f manifests/cilium/values-k3s.yaml \
  -f manifests/cilium/values-k3s-no-bpf-masquerade.yaml
```

Або в values вручну: `bpf.masquerade: false`

**Обґрунтування:** BPF masquerade auto-enables BPF Host Routing. Issue #39806 — host routing ламає response packets. iptables masquerade не використовує host routing.

### 3.2 Розширити ipv4NativeRoutingCIDR для OCI

У `values-k3s.yaml`:

```yaml
ipv4NativeRoutingCIDR: "10.0.0.0/8"   # замість 10.42.0.0/16
```

Або явно додати OCI VCN:

```yaml
# Cilium приймає один CIDR (string). Для OCI VCN + pod network:
ipv4NativeRoutingCIDR: "10.0.0.0/8"   # ширший діапазон, включає 10.0.10.0/24 та 10.42.0.0/16
```

### 3.3 Вимкнути kube-proxy replacement (екстремальний тест)

```yaml
kubeProxyReplacement: false
```

**Мінус:** потрібен kube-proxy (k3s його вмикає за замовчуванням з Flannel; з `flannel-backend=none` — перевірити).

### 3.4 Вимкнути socket-level LB

```yaml
socketLB:
  enabled: false
```

---

## 4. Рекомендований порядок тестів

1. **Спочатку діагностика** — зберегти baseline, встановити Cilium, порівняти iptables/ip rule/ip route.
2. **Якщо є підозра на BPF host routing** — `bpf.masquerade: false`.
3. **Якщо є підозра на native routing CIDR** — розширити `ipv4NativeRoutingCIDR`.
4. **Якщо SSH йде через WireGuard** — переконатись, що `devices` не включає wg0/wg1; Cilium має обробляти лише enp0s6.

---

## 5. Важливі деталі для master-node (OCI)

| Параметр | Значення |
|----------|----------|
| Node IP | 10.0.10.10 |
| Інтерфейс | enp0s6 |
| Default gateway | 10.0.10.1 |
| VCN CIDR | 10.0.10.0/24 |
| SSH | через OCI public IP → NAT → 10.0.10.10:22 |
| WireGuard | wg0, wg1 (для API tls-san 192.168.100.x) |

Якщо SSH йде через **OCI public IP**, трафік приходить на enp0s6. Cilium прикріплює BPF до enp0s6 — можливий конфлікт.

---

## 6. Швидкий тест без втрати доступу

На **локальній ноді** (macmini7 або beelinkeqr5), де можна фізично відновити доступ:

1. Зберегти baseline (п. 2.1).
2. Встановити Cilium з `bpf.masquerade: false` (override `values-k3s-no-bpf-masquerade.yaml`).
3. Якщо connectivity зберігається — підтверджує гіпотезу #1/#4.
4. Потім поступово вмикати функції для пошуку мінімального конфліктного набору.

**Fresh install з тестовим values:**
```bash
helm install cilium cilium/cilium --version 1.19.0 -n kube-system \
  -f manifests/cilium/values-k3s.yaml \
  -f manifests/cilium/values-k3s-no-bpf-masquerade.yaml
```

---

## 7. Посилання

- [Cilium Masquerading](https://docs.cilium.io/en/stable/network/concepts/masquerading/)
- [eBPF Host Routing drops packets #39806](https://github.com/cilium/cilium/issues/39806)
- [BPF masquerade wrong interface #41866](https://github.com/cilium/cilium/issues/41866)
- [Cilium Troubleshooting](https://docs.cilium.io/en/stable/operations/troubleshooting/)
