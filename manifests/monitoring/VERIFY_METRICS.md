# Перевірка збору метрик

## Проблема

Grafana дашборд показує "N/A" або "No data" для метрик кластера.

## Перевірка Prometheus

### 1. Перевірка targets в Prometheus

Відкрийте Prometheus UI:
```
http://<node-ip>:30001/targets
```

Перевірте статус кожного target:
- ✅ **UP** - метрики збираються
- ❌ **DOWN** - метрики не збираються

**Очікувані targets:**
- `prometheus` (localhost:9090) - має бути UP
- `node-exporter` - має бути UP (по одному на кожну ноду)
- `kube-state-metrics` - має бути UP
- `cadvisor` - має бути UP (по одному на кожну ноду)
- `kubernetes-nodes` - має бути UP
- `kubernetes-pods` - має бути UP

### 2. Перевірка метрик через PromQL

В Prometheus UI (`http://<node-ip>:30001/graph`) виконайте запити:

```promql
# Перевірка Node Exporter
up{job="node-exporter"}

# Перевірка kube-state-metrics
up{job="kube-state-metrics"}

# Перевірка кількості нод
count(kube_node_info)

# Перевірка CPU використання
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Перевірка пам'яті
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes
```

Якщо запити повертають дані - Prometheus збирає метрики правильно.

## Перевірка Grafana

### 1. Перевірка datasource

1. Відкрийте Grafana: `http://<node-ip>:30000`
2. Перейдіть до **Configuration** → **Data Sources**
3. Виберіть **Prometheus**
4. Перевірте:
   - **URL:** `http://prometheus:9090`
   - **Access:** `Server (default)`
5. Натисніть **Save & Test**
   - Має показати "Data source is working"

### 2. Перевірка дашборду

1. Відкрийте дашборд **Kubernetes Cluster (Prometheus)**
2. Перевірте фільтри:
   - **node:** `*` (всі ноди)
   - **namespace:** `*` (всі namespaces)
3. Перевірте time range (має бути останні 30 хвилин або більше)

### 3. Тестовий запит в Grafana

1. Відкрийте **Explore** в Grafana
2. Виберіть **Prometheus** як datasource
3. Виконайте запит:
   ```
   up{job="node-exporter"}
   ```
4. Якщо бачите дані - datasource працює правильно

## Troubleshooting

### Targets показують DOWN

**Причина:** Prometheus не може підключитися до targets

**Перевірка:**
```bash
# Перевірка сервісів
kubectl get svc -n monitoring

# Перевірка endpoints
kubectl get endpoints -n monitoring

# Перевірка network connectivity
kubectl exec -n monitoring -it deployment/prometheus -- wget -O- http://node-exporter:9100/metrics
kubectl exec -n monitoring -it deployment/prometheus -- wget -O- http://kube-state-metrics:8080/metrics
```

**Рішення:**
- Перевірте, що всі сервіси створені
- Перевірте, що поди працюють
- Перевірте network policies (якщо використовуються)

### Метрики не збираються з Node Exporter

**Перевірка:**
```bash
# Перевірка DaemonSet
kubectl get daemonset -n monitoring node-exporter

# Перевірка подів
kubectl get pods -n monitoring -l app=node-exporter

# Перевірка логів
kubectl logs -n monitoring -l app=node-exporter --tail=20

# Перевірка метрик напряму
kubectl port-forward -n monitoring svc/node-exporter 9100:9100
# Потім відкрийте http://localhost:9100/metrics
```

### Метрики не збираються з kube-state-metrics

**Перевірка:**
```bash
# Перевірка deployment
kubectl get deployment -n monitoring kube-state-metrics

# Перевірка подів
kubectl get pods -n monitoring -l app=kube-state-metrics

# Перевірка логів
kubectl logs -n monitoring -l app=kube-state-metrics --tail=20

# Перевірка метрик напряму
kubectl port-forward -n monitoring svc/kube-state-metrics 8080:8080
# Потім відкрийте http://localhost:8080/metrics
```

### Дашборд показує "No data" навіть якщо метрики є

**Причина:** Неправильні PromQL запити або labels не співпадають

**Рішення:**
1. Перевірте PromQL запити в дашборді
2. Перевірте labels в метриках:
   ```promql
   # Перевірка доступних labels
   {__name__=~".+"}
   ```
3. Оновіть дашборд або використайте інший дашборд, який підходить для k3s

## Рекомендовані дашборди для k3s

Оскільки k3s має деякі відмінності від стандартного Kubernetes, деякі дашборди можуть не працювати ідеально. Рекомендовані:

1. **Node Exporter Full** (ID: 1860) - найкраще працює
2. **Kubernetes Cluster Monitoring** (ID: 7249) - може потребувати налаштування
3. **Kubernetes Pod Monitoring** (ID: 6417) - може потребувати налаштування

Альтернативно, створіть власний дашборд з простими запитами для перевірки.

## Швидка перевірка

```bash
# 1. Перевірка всіх компонентів
kubectl get all -n monitoring

# 2. Перевірка targets в Prometheus
curl http://<node-ip>:30001/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# 3. Перевірка метрик
curl http://<node-ip>:30001/api/v1/query?query=up | jq

# 4. Перевірка datasource в Grafana
# Відкрийте Grafana → Configuration → Data Sources → Prometheus → Test
```
