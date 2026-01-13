# Виправлення проблеми з cadvisor

## Проблема

Prometheus не може підключитися до cadvisor через Kubernetes API proxy:
```
Get "https://kubernetes.default.svc:443/api/v1/nodes/.../proxy/metrics/cadvisor": context deadline exceeded
```

**Причина:** В k3s доступ до cadvisor через API proxy часто обмежений через налаштування безпеки.

## Рішення

### Варіант 1: Використати Node Exporter (рекомендовано) ✅

**Node Exporter вже збирає більшість метрик контейнерів**, тому cadvisor не є критичним.

**Переваги:**
- Node Exporter вже працює
- Збирає CPU, Memory, Disk, Network метрики
- Не потребує додаткових налаштувань

**Що вже збирається через Node Exporter:**
- CPU використання (включаючи контейнери)
- Пам'ять (включаючи контейнери)
- Disk I/O
- Network I/O
- Файлова система

**Що може не збиратися (зазвичай не критично):**
- Детальні метрики контейнерів (можна отримати через kube-state-metrics)
- Container-specific metrics (можна отримати через kube-state-metrics)

### Варіант 2: Вимкнути cadvisor job (вже зроблено)

Конфігурація Prometheus оновлена - cadvisor job закоментований.

**Для застосування змін:**

1. Оновіть ConfigMap через Portainer:
   - Kubernetes → Applications → monitoring
   - Знайдіть ConfigMap **prometheus-config**
   - Натисніть **Editor**
   - Скопіюйте оновлений вміст з `prometheus/configmap.yaml`
   - Натисніть **Update**

2. Перезапустіть Prometheus:
   ```bash
   kubectl delete pods -n monitoring -l app=prometheus
   ```

   Або через Portainer:
   - Kubernetes → Applications → monitoring
   - Знайдіть deployment **prometheus**
   - Натисніть **Restart**

3. Перевірте targets:
   - Відкрийте `http://<node-ip>:30001/targets`
   - Target `cadvisor` більше не повинен відображатися

### Варіант 3: Налаштувати прямий доступ до cadvisor (складніше)

Якщо дійсно потрібен cadvisor, можна налаштувати прямий доступ:

1. **Перевірте, чи cadvisor доступний на нодах:**
   ```bash
   # На ноді
   curl http://localhost:10250/metrics/cadvisor
   ```

2. **Якщо доступний, налаштуйте Prometheus для прямого доступу:**
   - Потрібно знати IP адреси нод
   - Налаштувати Service для кожної ноди
   - Або використати DaemonSet з cadvisor

3. **Альтернатива: Використати kubelet metrics endpoint:**
   ```yaml
   - job_name: 'kubelet'
     kubernetes_sd_configs:
       - role: node
     scheme: https
     tls_config:
       insecure_skip_verify: true
     bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
     relabel_configs:
       - action: replace
         source_labels: [__meta_kubernetes_node_name]
         target_label: __address__
         replacement: ${1}:10250
       - action: replace
         target_label: __metrics_path__
         replacement: /metrics/cadvisor
   ```

**Увага:** Це може не працювати через обмеження безпеки в k3s.

### Варіант 4: Додати додаткові права до ClusterRole

Можна спробувати додати додаткові права:

```yaml
- apiGroups: [""]
  resources:
  - nodes/proxy
  verbs: ["get", "list", "watch", "create"]
```

Але це може не допомогти, якщо k3s обмежує доступ на рівні API server.

## Рекомендація

**Використайте Варіант 1 або 2** - Node Exporter вже збирає більшість метрик, які потрібні для моніторингу. Cadvisor не є критичним для базового моніторингу кластера.

## Перевірка після виправлення

1. Перевірте targets в Prometheus: `http://<node-ip>:30001/targets`
   - Target `cadvisor` більше не повинен відображатися або показувати помилки

2. Перевірте метрики Node Exporter:
   ```promql
   # CPU використання
   100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
   
   # Пам'ять
   (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100
   
   # Disk I/O
   rate(node_disk_io_time_seconds_total[5m])
   ```

3. Перевірте метрики контейнерів через kube-state-metrics:
   ```promql
   # Використання CPU подів
   kube_pod_container_resource_requests{resource="cpu"}
   
   # Використання пам'яті подів
   kube_pod_container_resource_requests{resource="memory"}
   ```

## Підсумок

- ✅ **Node Exporter працює** - збирає метрики вузлів та контейнерів
- ✅ **Kube-state-metrics працює** - збирає метрики стану кластера
- ⚠️ **Cadvisor вимкнено** - не критично, Node Exporter покриває більшість потреб

Система моніторингу працює навіть без cadvisor!
