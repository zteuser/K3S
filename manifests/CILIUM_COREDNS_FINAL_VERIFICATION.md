# Остаточна перевірка мережі Cilium та CoreDNS

Єдиний чеклист перевірки після налаштування Cilium (VXLAN або native + Security List) та політик для CoreDNS. Виконувати кроки по порядку; при першій помилці — зупинитися і виправити причину.

**Ноди кластера:** master-node, work-node (OCI), beelinkeqr5 (Syhiv17), macmini7 (VRN625).

**Посилання:**
- Політика egress CoreDNS (API + upstream DNS): [cilium/networkpolicy-coredns-egress-upstream-dns.yaml](cilium/networkpolicy-coredns-egress-upstream-dns.yaml)
- Діагностика «Failed to watch»: [coredns/FIX_COREDNS_FAILED_TO_WATCH.md](coredns/FIX_COREDNS_FAILED_TO_WATCH.md)
- Встановлення Cilium CLI: [cilium/install-cilium-cli.sh](cilium/install-cilium-cli.sh)

---

## 2.1 Cilium і ноди

**1. Статус Cilium**

```bash
cilium status --wait
```

Очікується: усі ноди в кластері reachable (не `0/x endpoints`). Якщо CLI не встановлено — див. [cilium/install-cilium-cli.sh](cilium/install-cilium-cli.sh).

**2. Ноди**

```bash
kubectl get nodes -o wide
```

Очікується: усі 4 ноди в стані `Ready`, з коректними InternalIP (10.0.10.10, 10.0.10.20, 192.168.1.19, 192.168.2.19).

---

## 2.2 Pod → Kubernetes API (критично для CoreDNS watch)

Доступ до API (10.96.0.1:443) з поду на **кожній** ноді. Якщо таймаут — перевірити Cilium egress policy та мережу (VXLAN UDP 4789 або маршрути pod CIDR).

```bash
for NODE in master-node work-node beelinkeqr5 macmini7; do
  echo "=== Pod on $NODE -> 10.96.0.1:443 ==="
  kubectl run "curl-api-${NODE}" --rm -i --restart=Never \
    --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" \
    --image=curlimages/curl -- \
    curl -k -s -o /dev/null -w "%{http_code}\n" --connect-timeout 5 https://10.96.0.1:443/version 2>/dev/null || echo "timeout/fail"
done
```

Очікується: для кожної ноди виводиться HTTP код (наприклад 403), не `timeout/fail`.

---

## 2.3 Cilium connectivity test (якщо встановлено CLI)

```bash
cilium connectivity test
```

Очікується: усі тести пройдені. Якщо тест падає на певній парі нод — діагностувати firewall (UDP 4789 для VXLAN), маршрути, політики.

Опційно (наприклад без egress до інтернету):

```bash
cilium connectivity test --test '!pod-to-world'
```

---

## 2.4 CoreDNS: стан і логи

**1. Поди CoreDNS**

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
```

Очікується: хоча б один под у стані `1/1 Ready` (бажано на ноді з гарантованим доступом до API).

**2. Сервіс kube-dns**

```bash
kubectl get svc kube-dns -n kube-system -o yaml
```

Перевірити: при кількох нодах `spec.internalTrafficPolicy: Cluster`, щоб поди з усіх нод могли звертатися до DNS. Якщо лише один Ready под — без `Cluster` поди на інших нодах отримають «Operation not permitted».

**3. Логи CoreDNS**

```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100
```

Очікується: немає повторюваних `Failed to watch *v1.Namespace` та `dial tcp 10.96.0.1:443: i/o timeout`. Якщо є — перевірити політику [networkpolicy-coredns-egress-upstream-dns.yaml](cilium/networkpolicy-coredns-egress-upstream-dns.yaml) і крок 2.2; детальніше [coredns/FIX_COREDNS_FAILED_TO_WATCH.md](coredns/FIX_COREDNS_FAILED_TO_WATCH.md).

---

## 2.5 DNS-резолв з кожної ноди

Запустити **nslookup** з поду на кожній ноді (внутрішній та зовнішній домен).

**Внутрішній (kube-dns):**

```bash
for NODE in master-node work-node beelinkeqr5 macmini7; do
  echo "=== DNS from pod on $NODE (internal) ==="
  kubectl run "dns-internal-${NODE}" --rm -i --restart=Never \
    --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" \
    --image=busybox:1.36 -- \
    nslookup kube-dns.kube-system.svc.cluster.local 2>&1 | head -20
done
```

**Зовнішній (через кластерний DNS):**

```bash
for NODE in master-node work-node beelinkeqr5 macmini7; do
  echo "=== DNS from pod on $NODE (external: grafana.io) ==="
  kubectl run "dns-external-${NODE}" --rm -i --restart=Never \
    --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" \
    --image=busybox:1.36 -- \
    nslookup grafana.io 2>&1 | head -20
done
```

Очікується: відповіді з адресами, без «connection timed out» / «no servers could be reached».

---

## 2.6 Інтеграційний тест CoreDNS (опційно)

З каталогу манифестів (наприклад `manifests/coredns` або корінь репо k3s):

```bash
cd manifests/coredns
./test-coredns-resolve.sh
```

Скрипт перевіряє: kubernetes.default, kube-dns, коротке ім’я, google.com, prometheus.monitoring. Це доповнює, а не замінює перевірку з кожної ноди (крок 2.5).

---

## Підсумок

| Крок | Що перевіряється |
|------|------------------|
| 2.1  | Cilium status, усі ноди Ready |
| 2.2  | Pod → API 10.96.0.1:443 з кожної ноди |
| 2.3  | cilium connectivity test (усі пари нод) |
| 2.4  | CoreDNS поди Ready, kube-dns internalTrafficPolicy, логи без Failed to watch |
| 2.5  | nslookup (internal + external) з поду на кожній ноді |
| 2.6  | test-coredns-resolve.sh (опційно) |

Після успішного проходження всіх кроків мережа Cilium та CoreDNS вважаються перевіреними для всіх нод кластера.
