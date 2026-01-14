# FIX: Grafana не може підключитись до Prometheus (lookup prometheus: i/o timeout)

## Симптоми

- В Grafana панелях “No data”
- В логах Grafana:
  - `dial tcp: lookup prometheus: i/o timeout`
  - запити на `http://prometheus:9090/...` падають

Це означає: **Grafana pod не може резолвити DNS** (або не має доступу до CoreDNS).

## Швидкий workaround (без DNS): використати ClusterIP сервісу Prometheus

1. Дізнайтесь ClusterIP:

```bash
k3s kubectl -n monitoring get svc prometheus -o wide
```

2. Оновіть ConfigMap `grafana-datasources` (`grafana/configmap-datasources.yaml`):

- було:
  - `url: http://prometheus:9090`
- стане:
  - `url: http://<CLUSTER_IP>:9090`

3. Перезапустіть Grafana pod:

```bash
k3s kubectl delete pod -n monitoring -l app=grafana
```

Після цього дашборди мають почати показувати дані.

## Правильне рішення

Полагодити DNS/Service routing на ноді, де запускається Grafana (kube-proxy/CNI/iptables),
щоб pod-и могли звертатись до `10.43.0.10:53` (kube-dns/CoreDNS).

