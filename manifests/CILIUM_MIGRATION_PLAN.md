# План міграції k3s з Flannel на Cilium

> **⚠️ НЕ РОБОЧИЙ — НЕ ВИКОРИСТОВУВАТИ**
>
> Цей план викликав **повну втрату мережевої зв'язності** на нодах. Відкат (iptables, CNI, config) не допоміг — довелося **повністю перевстановити Ubuntu** для відновлення.
>
> **Рекомендація:** для Cilium використовувати лише **свіжий кластер** з нуля (див. `K3S_FRESH_INSTALL_CILIUM_RESTORE.md`), не міграцію існуючого.

---

Документ описує покроковий план переведення діючого кластера k3s з CNI **Flannel** на **Cilium** ([cilium.io](https://cilium.io/)). **На практиці план не працює.**

**Мережева діаграма після міграції:** `manifests/cilium/K3S_CILIUM_NETWORK_DIAGRAM.pdf`

---

## 1. Огляд та передумови

### 1.1 Поточний стан кластера (згідно з документацією)

| Параметр | Значення |
|---------|----------|
| **CNI** | Flannel (за замовчуванням k3s) |
| **Pod CIDR** | 10.42.0.0/16 |
| **Service CIDR** | 10.43.0.0/16 |
| **k3s версія** | v1.34.3+k3s1 |
| **Ноди** | master-node (10.0.10.10), macmini7 (192.168.2.19), beelinkeqr5 (192.168.1.19), work-node (10.0.10.20) |
| **Ingress** | Traefik (стандартний k3s) |

### 1.2 Що дає Cilium

- **eBPF-based** мережування замість iptables
- **Hubble** — observability (flow, DNS, HTTP, drop events)
- **NetworkPolicy** з розширеними можливостями
- **Gateway API** (замість/доповнення Ingress)
- **LB-IPAM** — виділення IP для LoadBalancer без MetalLB
- **Egress Gateway** — керований SNAT для вихідного трафіку

### 1.3 Варіанти міграції

| Варіант | Downtime | Складність | Рекомендація |
|---------|----------|------------|--------------|
| **A. Проста заміна** | 5–15 хв | Низька | Для кластера 3+1 ноди |
| **B. Dual overlay** | Мінімальний | Висока | Для production з жорсткими SLA |

Нижче детально описано **варіант A** (проста заміна). Варіант B — у [офіційній документації Cilium](https://docs.cilium.io/en/stable/installation/k8s-install-migration/).

---

## 2. Підготовка (перед міграцією)

### 2.1 Бекапи та збереження стану

```bash
# Експорт ресурсів
kubectl get all -A -o yaml > backup-all-resources.yaml

# Зберегти конфіги k3s з кожної ноди
# На кожній ноді:
cat /etc/rancher/k3s/config.yaml
systemctl cat k3s  # або k3s-agent
```

### 2.2 Перевірка мережевої досяжності

- Усі ноди мають маршрути між собою (WireGuard, OSPF тощо)
- Firewall дозволяє трафік для 10.42.0.0/16 та 10.43.0.0/16 (див. `FIX_CLUSTERIP_ACCESS_FROM_ALL_NODES.md`)

### 2.3 Визначити мережевий інтерфейс

Cilium native routing потребує `devices` та `directRoutingDevice`. Типово — `eth0`. На нодах з іншими інтерфейсами перевірте:

```bash
ip route get 8.8.8.8
# Використати інтерфейс з default route (наприклад eth0, enp0s3)
```

### 2.4 Визначити IP API server

Для `k8sServiceHost` в Helm values — IP, за яким усі ноди досягають API. Наприклад: `10.0.10.10` (master-node) або `192.168.2.19` (macmini7), залежно від мережевої топології.

---

## 3. Варіант A: Проста заміна Flannel на Cilium

**Орієнтовний downtime:** 5–15 хвилин (перезапуск k3s на всіх нодах).

### Крок 1. Зупинити k3s на усіх нодах

**Порядок:** спочатку agent-ноди, потім server-ноди.

```bash
# На work-node, master-node (agent):
sudo systemctl stop k3s-agent

# На macmini7, beelinkeqr5 (server) — останніми:
sudo systemctl stop k3s
```

### Крок 2. Вимкнути Flannel та Network Policy на server-нодах

На **кожній server-ноді** (macmini7, beelinkeqr5, master-node) додати в `/etc/rancher/k3s/config.yaml`:

```yaml
flannel-backend: none
disable-network-policy: true
```

Якщо є інші параметри (node-ip, tls-san, server, token) — зберегти їх без змін.

### Крок 3. Видалити інтерфейс Flannel (опційно, на кожній ноді)

```bash
ip link delete flannel.1 2>/dev/null || true
```

### Крок 4. Запустити k3s на server-нодах

```bash
# На першій server-ноді (наприклад macmini7):
sudo systemctl start k3s

# На інших server-нодах (beelinkeqr5, master-node):
sudo systemctl start k3s
```

Дочекатися, поки API server буде доступний (`kubectl get nodes`).

### Крок 5. Встановити Cilium через Helm

З control-plane ноди (де є `kubectl` і `helm`):

```bash
# Додати Helm repo
helm repo add cilium https://helm.cilium.io/
helm repo update

# Встановити Cilium з values для k3s (шлях від кореня репо k3s)
helm install cilium cilium/cilium \
  --version 1.19.0 \
  --namespace kube-system \
  --values manifests/cilium/values-k3s.yaml
```

**Важливо:** перед встановленням підставити в `values-k3s.yaml`:
- `k8sServiceHost` — IP API server (наприклад `10.0.10.10`)
- `devices` / `directRoutingDevice` — якщо не eth0

```bash
# Дочекатися готовності Cilium (потрібен cilium-cli: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-cilium-cli)
cilium status --wait
# Або перевірка вручну:
kubectl get pods -n kube-system -l k8s-app=cilium
```

### Крок 6. Запустити k3s на agent-нодах

```bash
# На work-node:
sudo systemctl start k3s-agent
```

### Крок 7. Перевірка

```bash
# Статус Cilium
cilium status --wait

# Ноди Ready
kubectl get nodes -o wide

# Поди в kube-system
kubectl get pods -n kube-system -o wide

# Тест мережі з пода
kubectl run test-curl --rm -it --restart=Never --image=curlimages/curl -- \
  curl -k -s -o /dev/null -w "%{http_code}" https://10.43.0.1:443/healthz
# Очікується 200 або 403
```

### Крок 8. Перезапуск workload

Якщо поди в Pending або CrashLoopBackOff після міграції:

```bash
kubectl rollout restart deployment -n monitoring
kubectl rollout restart daemonset -n kube-system
# За потреби — інші namespace
```

---

## 4. Після міграції: опційні можливості

Після успішної роботи базового Cilium можна поетапно вмикати додаткові функції.

### 4.1 Hubble (observability)

Якщо не вмикали при встановленні:

```bash
helm upgrade cilium cilium/cilium -n kube-system --reuse-values \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true
kubectl rollout restart ds/cilium -n kube-system
```

Доступ до UI: `kubectl port-forward -n kube-system svc/hubble-relay 4245:80` → http://localhost:4245

### 4.2 LB-IPAM та L2 announcements (LoadBalancer IP)

Якщо потрібні LoadBalancer сервіси з виділеними IP (без MetalLB):

1. Увімкнути в `values-k3s.yaml`: `l2announcements.enabled: true`
2. Створити `CiliumLoadBalancerIPPool` з діапазоном у вашій мережі (наприклад 192.168.2.50–70)
3. Створити `CiliumL2AnnouncementPolicy` для інтерфейсу та нод

Див. [Cilium LB-IPAM](https://docs.cilium.io/en/stable/network/l2-announcements/) та [Helm reference](https://docs.cilium.io/en/stable/helm-reference/).

### 4.3 Gateway API (замість/доповнення Traefik)

- Cilium Envoy вже підтримує Gateway API при `gatewayAPI.enabled: true`
- Можна залишити Traefik для існуючих Ingress і поступово мігрувати на HTTPRoute

### 4.4 Egress Gateway

Для керованого SNAT вихідного трафіку — створити `CiliumEgressGatewayPolicy`. У `excludedCIDRs` вказати Pod/Service/Node CIDR (10.42, 10.43, 192.168.x, 10.0.10.x). Див. [Cilium Egress Gateway](https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/).

### 4.5 NetworkPolicy (default deny)

За замовчуванням Cilium не блокує трафік. Для default deny:

1. Застосувати `CiliumClusterwideNetworkPolicy` для доступу до CoreDNS **до** вмикання default deny
2. Увімкнути `policyEnforcementMode: always` у Helm values

---

## 5. Адаптація під топологію k3s

### 5.1 CIDR

У цьому плані **зберігаємо** k3s CIDR:
- Pod: 10.42.0.0/16
- Service: 10.43.0.0/16

Зміна CIDR вимагає перебудови кластера або dual-overlay міграції (див. офіційну документацію Cilium).

### 5.2 Node network та nonMasqueradeCIDRs

У `ipMasqAgent.config.nonMasqueradeCIDRs` вказати:
- 10.42.0.0/16 (Pod)
- 10.43.0.0/16 (Service)
- 192.168.1.0/24, 192.168.2.0/24, 10.0.10.0/24 (Node мережі)

### 5.3 Інтерфейси

Ноди в різних локаціях можуть мати різні інтерфейси (eth0, enp0s3, тощо). Cilium підтримує regex: `devices: "eth0|enp0s3"` або окремо на ноду через CiliumNodeConfig.

---

## 6. Відкат (rollback)

Якщо міграція не вдалася:

1. Видалити Cilium: `helm uninstall cilium -n kube-system`
2. Прибрати з `/etc/rancher/k3s/config.yaml`: `flannel-backend: none`, `disable-network-policy: true`
3. Перезапустити k3s на всіх нодах (agent → server)
4. Відновити workload з бекапу за потреби

---

## 7. Посилання

| Ресурс | URL |
|--------|-----|
| Cilium офіційний сайт | https://cilium.io/ |
| Cilium Migration (dual overlay) | https://docs.cilium.io/en/stable/installation/k8s-install-migration/ |
| Cilium Helm reference | https://docs.cilium.io/en/stable/helm-reference/ |
| Cilium Egress Gateway | https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/ |
| Cilium L2 Announcements | https://docs.cilium.io/en/stable/network/l2-announcements/ |

---

## 8. Чеклист міграції

- [x] Бекап ресурсів та конфігів k3s
- [x] Перевірка мережевої досяжності між нодами
- [x] Визначено `k8sServiceHost` та `devices`
- [x] Підготовлено `manifests/cilium/values-k3s.yaml`
- [x] Зупинено k3s на всіх нодах
- [x] Додано `flannel-backend: none` у config.yaml на server-нодах
- [ ] Встановлено Cilium через Helm
- [ ] Запущено k3s на server, потім agent
- [ ] `cilium status` — OK, усі поди managed by Cilium
- [ ] Тест доступу до API з пода
- [ ] Перезапуск workload при потребі
- [ ] (Опційно) Hubble, LB-IPAM, Gateway API, Egress Gateway
