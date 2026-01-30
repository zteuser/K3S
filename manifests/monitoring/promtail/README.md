# Promtail (Фаза 3 з LOGGING_PLAN)

DaemonSet на кожній ноді: збирає логи контейнерів з `/var/log/pods` та логи systemd journal з `/var/log/journal`, відправляє в Loki.

## Що збирається

- **kubernetes-pods:** логи всіх контейнерів (namespace, pod, container, node) з `/var/log/pods`.
- **journal:** логи systemd (k3s, k3s-agent тощо) з мітками `job=journal`, `unit`, `nodename`.

## Планування на нодах

За замовчуванням Promtail планується **лише на master-node** (nodeSelector), бо на worker-нодах часто немає маршруту до API (10.43.0.1) та Loki — виникають "no route to host" і "context deadline exceeded". Loki теж на master-node. Логи збираються з master-node (поди + journal). Щоб збирати логи з усіх нод — налаштуйте доступ до ClusterIP з worker-нод за інструкцією **`manifests/FIX_CLUSTERIP_ACCESS_FROM_ALL_NODES.md`**, потім приберіть nodeSelector з DaemonSet.

## Вимоги на нодах

- Каталог `/var/log/pods` (стандартний шлях логів подів у k3s).
- Каталог `/var/log/journal` (journald, для логів k3s).
- Файл `/etc/machine-id` (для читання journal).

## Деплой

Разом з усім monitoring stack:

```bash
kubectl apply -k manifests/monitoring
```

Або окремо:

```bash
kubectl apply -f manifests/monitoring/promtail/serviceaccount.yaml
kubectl apply -f manifests/monitoring/promtail/clusterrole.yaml
kubectl apply -f manifests/monitoring/promtail/clusterrolebinding.yaml
kubectl apply -f manifests/monitoring/promtail/configmap.yaml
kubectl apply -f manifests/monitoring/promtail/daemonset.yaml
```

## Перевірка

```bash
kubectl -n monitoring get pods -l app=promtail
kubectl -n monitoring logs -l app=promtail --tail=30
```

У Grafana Explore (Loki) через кілька хвилин мають з’явитися логи за мітками `namespace`, `pod`, `container`, `job=journal`, `unit`.

## Якщо Promtail показує "context deadline exceeded" при POST до Loki

1. **Таймаут клієнта:** у конфігу встановлено `timeout: 30s` і `batchwait: 2s`. Після оновлення ConfigMap перезапустіть поди: `kubectl -n monitoring apply -f manifests/monitoring/promtail/configmap.yaml` і `kubectl -n monitoring delete pod -l app=promtail`.

2. **DNS/мережа між нодами:** якщо Loki на одній ноді, а Promtail на інших — спробуйте URL через ClusterIP: `kubectl -n monitoring get svc loki -o wide`, потім у ConfigMap змініть `url` на `http://<ClusterIP>:3100/loki/api/v1/push`.

3. **Навантаження на Loki:** перевірте `kubectl -n monitoring logs -l app=loki --tail=50`; при потребі збільште ресурси або retention у Loki.
