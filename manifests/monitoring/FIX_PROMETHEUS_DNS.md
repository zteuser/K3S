# FIX: Prometheus pod не резолвить DNS (CoreDNS timeout)

## Симптоми

- В Prometheus targets видно помилку:
  - `lookup ... on 10.43.0.10:53: ... i/o timeout`
- Всередині `prometheus` pod:
  - `wget: bad address 'snmp-exporter.monitoring.svc.cluster.local:9116'`

Це **не SNMP проблема** — це проблема **DNS з Prometheus pod до CoreDNS** (service `kube-dns` / `coredns`).

## Швидка перевірка (з prometheus pod)

В Portainer → prometheus → Console:

```sh
cat /etc/resolv.conf
```

Очікуємо `nameserver 10.43.0.10` (або інший ClusterIP DNS).

Спробуйте резолв:

```sh
nslookup kubernetes.default.svc.cluster.local 10.43.0.10
nslookup snmp-exporter.monitoring.svc.cluster.local 10.43.0.10
```

Якщо `nslookup` нема — використайте `busybox` (або встановіть пакет, якщо це дозволено).

## Що робити

### Варіант A (рекомендовано як workaround): Перемістити Prometheus на ноду, де DNS працює

1. Знайдіть INTERNAL-IP/hostname нод:

```bash
k3s kubectl get nodes -o wide
```

1. Додайте `nodeSelector` в `k3s/manifests/monitoring/prometheus/deployment.yaml` (вже є підказка-коментар).
   Наприклад:

```yaml
nodeSelector:
  kubernetes.io/hostname: macmini7
```

1. Оновіть Deployment через Portainer і видаліть pod Prometheus (він пересоздасться на потрібній ноді).

### Варіант A2 (ще простіше як workaround): обійти DNS для SNMP (використати ClusterIP сервісу)

Якщо вам потрібно **лише** щоб запрацював `snmp-routers`, можна не лагодити DNS одразу.

1. Дізнайтесь ClusterIP сервісу `snmp-exporter`:

```bash
k3s kubectl -n monitoring get svc snmp-exporter -o wide
```

1. В `prometheus/configmap.yaml` в `snmp-routers` змініть `replacement:` на `<CLUSTER_IP>:9116`
   (наприклад `10.43.x.y:9116`), оновіть ConfigMap і пересоздайте Prometheus pod.

Це не ідеально (IP зміниться лише якщо ви видалите/пересоздасте Service), але швидко розблокує SNMP.

### Варіант B: Полагодити DNS на ноді (правильне довгострокове рішення)

Якщо DNS не працює лише на одній ноді — це зазвичай проблема `kube-proxy` / CNI / iptables на ній.

Перевірки:

```bash
k3s kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
k3s kubectl -n kube-system get svc kube-dns -o wide
```

Далі: перезапуск `k3s-agent`/ноди або відновлення CNI — залежить від вашої інфраструктури.

## Чому SNMP targets DOWN

SNMP job звертається до `snmp-exporter` по HTTP. Якщо Prometheus pod не має DNS, він не може резолвити сервіс, тому і падає scrape.
