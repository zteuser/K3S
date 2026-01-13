# Швидке виправлення "No data" в Grafana

## Проблема

Grafana дашборд показує "N/A" або "No data" для всіх метрик.

## Швидка перевірка (5 хвилин)

### Крок 1: Перевірка targets в Prometheus

Відкрийте Prometheus UI:
```
http://<node-ip>:30001/targets
```

**Очікувані targets (мають бути UP):**
- ✅ `prometheus` - має бути UP
- ✅ `node-exporter` - має бути UP (по одному на кожну ноду)
- ✅ `kube-state-metrics` - має бути UP
- ✅ `cadvisor` - має бути UP (по одному на кожну ноду)
- ✅ `kubernetes-nodes` - має бути UP
- ✅ `kubernetes-pods` - має бути UP

**Якщо targets показують DOWN:**
- Перевірте, що всі поди працюють: `kubectl get pods -n monitoring`
- Перевірте сервіси: `kubectl get svc -n monitoring`
- Перевірте endpoints: `kubectl get endpoints -n monitoring`

### Крок 2: Перевірка метрик через PromQL

В Prometheus UI (`http://<node-ip>:30001/graph`) виконайте тестові запити:

```promql
# Перевірка Node Exporter
up{job="node-exporter"}

# Перевірка kube-state-metrics
up{job="kube-state-metrics"}

# Перевірка кількості нод
count(kube_node_info)

# Перевірка CPU
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Якщо запити повертають дані** - Prometheus збирає метрики правильно, проблема в дашборді.

**Якщо запити не повертають дані** - Prometheus не збирає метрики, див. Крок 3.

### Крок 3: Перевірка компонентів

```bash
# Перевірка всіх подів
kubectl get pods -n monitoring

# Перевірка Node Exporter
kubectl get pods -n monitoring -l app=node-exporter
kubectl logs -n monitoring -l app=node-exporter --tail=10

# Перевірка kube-state-metrics
kubectl get pods -n monitoring -l app=kube-state-metrics
kubectl logs -n monitoring -l app=kube-state-metrics --tail=10

# Перевірка Prometheus
kubectl logs -n monitoring -l app=prometheus --tail=20
```

### Крок 4: Перевірка datasource в Grafana

1. Відкрийте Grafana: `http://<node-ip>:30000`
2. Перейдіть до **Configuration** → **Data Sources**
3. Виберіть **Prometheus**
4. Перевірте:
   - **URL:** `http://prometheus:9090`
   - **Access:** `Server (default)`
5. Натисніть **Save & Test**
   - Має показати "Data source is working"

### Крок 5: Тестовий запит в Grafana Explore

1. Відкрийте **Explore** в Grafana (значок компаса зліва)
2. Виберіть **Prometheus** як datasource
3. Виконайте запит:
   ```
   up{job="node-exporter"}
   ```
4. Натисніть **Run query**

**Якщо бачите дані** - datasource працює, проблема в дашборді.

**Якщо не бачите даних** - проблема в зборі метрик, див. Troubleshooting нижче.

## Troubleshooting

### Targets показують DOWN

**Причина:** Prometheus не може підключитися до targets

**Рішення:**

1. Перевірте сервіси:
   ```bash
   kubectl get svc -n monitoring
   ```

2. Перевірте endpoints:
   ```bash
   kubectl get endpoints -n monitoring
   ```

3. Перевірте network connectivity з Prometheus:
   ```bash
   kubectl exec -n monitoring -it deployment/prometheus -- wget -O- http://node-exporter:9100/metrics
   kubectl exec -n monitoring -it deployment/prometheus -- wget -O- http://kube-state-metrics:8080/metrics
   ```

4. Якщо connectivity не працює, перевірте network policies або перезапустіть поди:
   ```bash
   kubectl delete pods -n monitoring -l app=prometheus
   ```

### Node Exporter не збирає метрики

**Перевірка:**
```bash
# Перевірка DaemonSet
kubectl get daemonset -n monitoring node-exporter

# Перевірка подів
kubectl get pods -n monitoring -l app=node-exporter

# Перевірка метрик напряму
kubectl port-forward -n monitoring svc/node-exporter 9100:9100
# Потім відкрийте http://localhost:9100/metrics
```

**Якщо метрики доступні напряму, але Prometheus не бачить:**
- Перевірте конфігурацію Prometheus: `kubectl get configmap -n monitoring prometheus-config -o yaml`
- Перезапустіть Prometheus: `kubectl delete pods -n monitoring -l app=prometheus`

### Kube-state-metrics не збирає метрики

**Перевірка:**
```bash
# Перевірка deployment
kubectl get deployment -n monitoring kube-state-metrics

# Перевірка подів
kubectl get pods -n monitoring -l app=kube-state-metrics

# Перевірка метрик напряму
kubectl port-forward -n monitoring svc/kube-state-metrics 8080:8080
# Потім відкрийте http://localhost:8080/metrics
```

**Якщо метрики доступні напряму, але Prometheus не бачить:**
- Перевірте конфігурацію Prometheus
- Перезапустіть Prometheus

### Дашборд показує "No data" навіть якщо метрики є

**Причина:** Неправильні PromQL запити або labels не співпадають з k3s

**Рішення:**

1. Перевірте доступні labels в метриках:
   ```promql
   # В Grafana Explore
   {__name__=~".+"}
   ```

2. Перевірте, які labels використовуються:
   ```promql
   # Перевірка labels для нод
   kube_node_info
   
   # Перевірка labels для подів
   kube_pod_info
   ```

3. Оновіть дашборд або використайте інший дашборд, який підходить для k3s:
   - **Node Exporter Full** (ID: 1860) - найкраще працює
   - **Kubernetes Cluster Monitoring** (ID: 7249) - може потребувати налаштування

4. Або створіть власний дашборд з простими запитами:
   ```promql
   # CPU використання
   100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
   
   # Пам'ять
   (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100
   
   # Кількість подів
   count(kube_pod_info)
   ```

## Рекомендовані дашборди для k3s

Оскільки k3s має деякі відмінності від стандартного Kubernetes, деякі дашборди можуть не працювати ідеально.

**Найкращі дашборди:**
1. **Node Exporter Full** (ID: 1860) - найкраще працює з k3s
2. **Kubernetes Cluster Monitoring** (ID: 7249) - може потребувати налаштування labels
3. **Kubernetes Pod Monitoring** (ID: 6417) - може потребувати налаштування labels

**Для імпорту:**
1. Dashboards → Import
2. Введіть ID дашборду
3. Виберіть Prometheus як джерело даних
4. Налаштуйте фільтри (node, namespace)
5. Натисніть Import

## Швидка команда для перевірки

```bash
# Перевірка всіх компонентів
kubectl get all -n monitoring

# Перевірка targets в Prometheus
curl -s http://<node-ip>:30001/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Перевірка метрик
curl -s http://<node-ip>:30001/api/v1/query?query=up | jq '.data.result[] | {metric: .metric, value: .value}'
```
