# Підсумок: Система моніторингу k3s кластера

## Що було створено

Повна система моніторингу для k3s кластера з можливістю розгортання через Portainer UI.

### Структура файлів

```
monitoring/
├── README.md                    # Основна документація
├── DEPLOYMENT_GUIDE.md          # Покрокова інструкція для Portainer
├── QUICK_START.md               # Швидкий старт
├── VARIANTS_COMPARISON.md       # Порівняння варіантів
├── SUMMARY.md                   # Цей файл
├── kustomization.yaml           # Kustomize конфігурація
├── namespace.yaml               # Namespace для моніторингу
│
├── node-exporter/               # Метрики вузлів
│   ├── daemonset.yaml
│   └── service.yaml
│
├── kube-state-metrics/          # Метрики кластера
│   ├── serviceaccount.yaml
│   ├── clusterrole.yaml
│   ├── clusterrolebinding.yaml
│   ├── deployment.yaml
│   └── service.yaml
│
├── prometheus/                  # Збір та зберігання метрик
│   ├── serviceaccount.yaml
│   ├── clusterrole.yaml
│   ├── clusterrolebinding.yaml
│   ├── configmap.yaml          # Конфігурація Prometheus
│   ├── pvc.yaml                # PersistentVolumeClaim
│   ├── deployment.yaml
│   └── service.yaml
│
└── grafana/                     # Візуалізація
    ├── configmap.yaml          # Конфігурація Grafana
    ├── configmap-datasources.yaml  # Джерела даних
    ├── secret.yaml             # Credentials (змініть пароль!)
    ├── pvc.yaml                # PersistentVolumeClaim
    ├── deployment.yaml
    └── service.yaml
```

---

## Компоненти системи

### 1. Node Exporter
- **Тип:** DaemonSet (запускається на кожній ноді)
- **Призначення:** Збір метрик вузлів (CPU, Memory, Disk, Network)
- **Порт:** 9100
- **Ресурси:** ~50MB RAM на ноду

### 2. Kube-state-metrics
- **Тип:** Deployment
- **Призначення:** Метрики стану кластера (pods, deployments, services)
- **Порт:** 8080
- **Ресурси:** ~100MB RAM

### 3. Prometheus
- **Тип:** Deployment
- **Призначення:** Збір, зберігання та запит метрик
- **Порт:** 9090 (NodePort: 30001)
- **Ресурси:** ~500MB RAM, 1 CPU
- **Storage:** 10GB (retention: 30 днів)

### 4. Grafana
- **Тип:** Deployment
- **Призначення:** Візуалізація метрик та дашборди
- **Порт:** 3000 (NodePort: 30000)
- **Ресурси:** ~200MB RAM, 0.5 CPU
- **Storage:** 5GB

---

## Швидкий старт

### Через Portainer UI

1. **Створіть Namespace:**
   - Kubernetes → Namespaces → Add namespace
   - Скопіюйте `namespace.yaml`

2. **Розгорніть компоненти в порядку:**
   - Node Exporter (Service → DaemonSet)
   - Kube-state-metrics (ServiceAccount → ClusterRole → ClusterRoleBinding → Deployment → Service)
   - Prometheus (ServiceAccount → ClusterRole → ClusterRoleBinding → ConfigMap → PVC → Deployment → Service)
   - Grafana (ConfigMap → ConfigMap (datasources) → Secret → PVC → Deployment → Service)

3. **Налаштуйте Grafana:**
   - Відкрийте `http://<node-ip>:30000`
   - Логін: `admin`, Пароль: (з Secret)
   - Додайте Prometheus як джерело даних: `http://prometheus:9090`
   - Імпортуйте дашборди (ID: 1860, 7249, 6417)

### Через kubectl (альтернатива)

```bash
# Застосувати всі manifests
kubectl apply -k manifests/monitoring/

# Або окремо
kubectl apply -f manifests/monitoring/namespace.yaml
kubectl apply -f manifests/monitoring/node-exporter/
kubectl apply -f manifests/monitoring/kube-state-metrics/
kubectl apply -f manifests/monitoring/prometheus/
kubectl apply -f manifests/monitoring/grafana/
```

---

## Доступ до сервісів

| Сервіс | URL | Примітки |
|--------|-----|----------|
| Grafana | `http://<node-ip>:30000` | Логін: admin, Пароль: (з Secret) |
| Prometheus | `http://<node-ip>:30001` | UI для PromQL запитів |

---

## Важливі налаштування

### ⚠️ Безпека

1. **Змініть пароль Grafana:**
   - Відредагуйте `grafana/secret.yaml`
   - Змініть `admin-password` на безпечний пароль
   - Перезапустіть Grafana deployment

2. **Для production:**
   - Налаштуйте Ingress замість NodePort
   - Додайте TLS/SSL сертифікати
   - Налаштуйте RBAC для обмеження доступу

### 💾 Storage

1. **Для OCFS2 storage:**
   - Розкоментуйте `storageClassName: ocfs2` в:
     - `prometheus/pvc.yaml`
     - `grafana/pvc.yaml`

2. **Для k3s default storage:**
   - Використовується `local-path` (за замовчуванням)

3. **Розмір storage:**
   - Prometheus: 10GB (можна змінити в `prometheus/pvc.yaml`)
   - Grafana: 5GB (можна змінити в `grafana/pvc.yaml`)

### 🔧 Конфігурація

1. **Retention Prometheus:**
   - За замовчуванням: 30 днів
   - Змінити в `prometheus/deployment.yaml`: `--storage.tsdb.retention.time=30d`

2. **Scrape interval:**
   - За замовчуванням: 15 секунд
   - Змінити в `prometheus/configmap.yaml`: `scrape_interval: 15s`

---

## Перевірка роботи

```bash
# Перевірка подів
kubectl get pods -n monitoring

# Перевірка сервісів
kubectl get svc -n monitoring

# Перевірка логів
kubectl logs -n monitoring -l app=prometheus
kubectl logs -n monitoring -l app=grafana

# Перевірка метрик Prometheus
curl http://<node-ip>:30001/api/v1/targets
```

---

## Рекомендовані дашборди Grafana

1. **Node Exporter Full** (ID: 1860)
   - Метрики вузлів (CPU, Memory, Disk, Network)

2. **Kubernetes Cluster Monitoring** (ID: 7249)
   - Метрики кластера (pods, deployments, services)

3. **Kubernetes Pod Monitoring** (ID: 6417)
   - Метрики подів

Для імпорту: Dashboards → Import → Введіть ID → Load → Import

---

## Troubleshooting

### Prometheus не збирає метрики
- Перевірте логи: `kubectl logs -n monitoring -l app=prometheus`
- Перевірте targets: `http://<node-ip>:30001/targets`
- Перевірте конфігурацію: `kubectl get configmap -n monitoring prometheus-config -o yaml`

### Grafana не підключається до Prometheus
- Перевірте URL: має бути `http://prometheus:9090`
- Перевірте, що Prometheus працює: `kubectl get pods -n monitoring -l app=prometheus`
- Перевірте network connectivity: `kubectl exec -n monitoring -it deployment/grafana -- wget -O- http://prometheus:9090/api/v1/status/config`

### Node Exporter не збирає метрики
- Перевірте DaemonSet: `kubectl get daemonset -n monitoring`
- Перевірте логи: `kubectl logs -n monitoring -l app=node-exporter`

---

## Оновлення

Для оновлення компонентів через Portainer:

1. Відкрийте Deployment в Portainer
2. Натисніть **Editor**
3. Оновіть версію образу (наприклад, `prom/prometheus:v2.49.0`)
4. Натисніть **Update the deployment**

---

## Додаткові ресурси

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [Kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)
- [K3s Documentation](https://docs.k3s.io/)

---

## Підтримка

Якщо виникли проблеми:

1. Перевірте логи всіх компонентів
2. Перевірте статус подів та сервісів
3. Перевірте конфігурації (ConfigMaps, Secrets)
4. Перевірте network connectivity між компонентами
5. Перевірте storage (PVC статус)

---

**Створено:** Система моніторингу для k3s кластера
**Версія:** 1.0
**Дата:** 2024
