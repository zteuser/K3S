# Система моніторингу k3s кластера

Цей каталог містить конфігурації для розгортання системи моніторингу k3s кластера через Portainer UI.

## Варіанти моніторингу

### Варіант 1: Повний стек (Prometheus + Grafana) - Рекомендовано

**Компоненти:**
- **Prometheus** - збір та зберігання метрик
- **Grafana** - візуалізація метрик та дашборди
- **Node Exporter** - метрики вузлів (CPU, Memory, Disk, Network)
- **Kube-state-metrics** - метрики стану кластера (pods, deployments, services)
- **Alertmanager** - управління алертами (опціонально)

**Переваги:**
- Повний контроль над метриками
- Богата екосистема дашбордів
- Гнучка конфігурація алертів
- Стандартний стек для Kubernetes

**Вимоги до ресурсів:**
- Prometheus: ~500MB RAM, 1 CPU
- Grafana: ~200MB RAM, 0.5 CPU
- Node Exporter: ~50MB RAM на ноду
- Kube-state-metrics: ~100MB RAM

**Розгортання:**
1. Розгорнути компоненти в порядку: namespace → node-exporter → kube-state-metrics → prometheus → grafana
2. Всі manifests знаходяться в підкаталогах

---

### Варіант 2: Lightweight (Grafana + Node Exporter)

**Компоненти:**
- **Grafana** - візуалізація
- **Node Exporter** - метрики вузлів
- Використання вбудованих метрик k3s (cAdvisor)

**Переваги:**
- Мінімальне споживання ресурсів
- Швидке розгортання
- Достатньо для базового моніторингу

**Недоліки:**
- Обмежена історія метрик
- Менше можливостей для алертів

---

### Варіант 3: Loki Stack (Логи)

**Компоненти:**
- **Loki** - збір логів
- **Promtail** - агент для збору логів
- **Grafana** - візуалізація логів

**Призначення:**
- Централізований збір логів з подів
- Пошук та аналіз логів
- Інтеграція з Grafana

---

## Розгортання через Portainer UI

### Крок 1: Створення Namespace

1. Відкрийте Portainer UI
2. Перейдіть до **Kubernetes** → **Namespaces**
3. Натисніть **Add namespace**
4. Введіть назву: `monitoring`
5. Натисніть **Create the namespace**

Або використайте YAML:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
```

### Крок 2: Розгортання компонентів

#### 2.1 Node Exporter (DaemonSet)

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **Deploy from manifest**
3. Скопіюйте вміст файлу `node-exporter/daemonset.yaml`
4. Натисніть **Deploy**

#### 2.2 Kube-state-metrics

1. Розгорніть ServiceAccount: `kube-state-metrics/serviceaccount.yaml`
2. Розгорніть Deployment: `kube-state-metrics/deployment.yaml`
3. Розгорніть Service: `kube-state-metrics/service.yaml`

#### 2.3 Prometheus

1. Створіть ConfigMap з конфігурацією: `prometheus/configmap.yaml`
2. Створіть ServiceAccount: `prometheus/serviceaccount.yaml`
3. Створіть ClusterRole та ClusterRoleBinding: `prometheus/rbac.yaml`
4. Створіть PersistentVolumeClaim: `prometheus/pvc.yaml`
5. Розгорніть Deployment: `prometheus/deployment.yaml`
6. Розгорніть Service: `prometheus/service.yaml`

#### 2.4 Grafana

1. Створіть ConfigMap з дашбордами: `grafana/configmap-dashboards.yaml`
2. Створіть ConfigMap з конфігурацією: `grafana/configmap.yaml`
3. Створіть Secret для адміністратора: `grafana/secret.yaml`
4. Створіть PersistentVolumeClaim: `grafana/pvc.yaml`
5. Розгорніть Deployment: `grafana/deployment.yaml`
6. Розгорніть Service: `grafana/service.yaml`

### Крок 3: Налаштування доступу

#### NodePort (для тестування)

Сервіси налаштовані як NodePort для доступу ззовні:
- Grafana: `http://<node-ip>:30000` (default login: admin/admin)
- Prometheus: `http://<node-ip>:30001`

#### Ingress (для production)

Можна налаштувати Ingress для доступу через доменне ім'я.

---

## Перевірка розгортання

### Перевірка подів

```bash
kubectl get pods -n monitoring
```

Очікуваний результат:
```
NAME                                  READY   STATUS    RESTARTS   AGE
grafana-xxxxxxxxxx-xxxxx             1/1     Running   0          5m
node-exporter-xxxxx                   1/1     Running   0          5m
node-exporter-xxxxx                   1/1     Running   0          5m
prometheus-xxxxxxxxxx-xxxxx           1/1     Running   0          5m
kube-state-metrics-xxxxxxxxxx-xxxxx  1/1     Running   0          5m
```

### Перевірка сервісів

```bash
kubectl get svc -n monitoring
```

### Перевірка логів

```bash
kubectl logs -n monitoring deployment/prometheus
kubectl logs -n monitoring deployment/grafana
```

---

## Налаштування Grafana

### 1. Перший вхід

1. Відкрийте Grafana: `http://<node-ip>:30000`
2. Логін: `admin`
3. Пароль: `admin` (змініть при першому вході)

### 2. Додавання Prometheus як джерела даних

1. Перейдіть до **Configuration** → **Data Sources**
2. Натисніть **Add data source**
3. Виберіть **Prometheus**
4. URL: `http://prometheus:9090` (внутрішній сервіс)
5. Натисніть **Save & Test**

### 3. Імпорт дашбордів

Рекомендовані дашборди:
- **Node Exporter Full**: ID `1860` - метрики вузлів
- **Kubernetes Cluster Monitoring**: ID `7249` - метрики кластера
- **Kubernetes Pod Monitoring**: ID `6417` - метрики подів

Для імпорту:
1. Перейдіть до **Dashboards** → **Import**
2. Введіть ID дашборду
3. Виберіть Prometheus як джерело даних
4. Натисніть **Import**

---

## Налаштування алертів (опціонально)

### Alertmanager

1. Розгорніть Alertmanager: `alertmanager/deployment.yaml`
2. Налаштуйте правила в Prometheus: `prometheus/configmap-alerts.yaml`
3. Налаштуйте отримувачів алертів в Alertmanager

---

## Troubleshooting

### Prometheus не збирає метрики

1. Перевірте логи: `kubectl logs -n monitoring deployment/prometheus`
2. Перевірте конфігурацію: `kubectl get configmap -n monitoring prometheus-config -o yaml`
3. Перевірте доступ до сервісів: `kubectl get endpoints -n monitoring`

### Grafana не підключається до Prometheus

1. Перевірте, що Prometheus працює: `kubectl get pods -n monitoring -l app=prometheus`
2. Перевірте URL в Grafana (має бути `http://prometheus:9090`)
3. Перевірте network policies (якщо використовуються)

### Node Exporter не збирає метрики

1. Перевірте, що DaemonSet запущений на всіх нодах: `kubectl get daemonset -n monitoring`
2. Перевірте логи: `kubectl logs -n monitoring -l app=node-exporter`

---

## Оновлення компонентів

Для оновлення через Portainer:
1. Відкрийте Deployment в Portainer
2. Натисніть **Editor**
3. Оновіть версію образу
4. Натисніть **Update the deployment**

---

## Рекомендації

1. **Резервне копіювання**: Регулярно робіть backup PVC для Prometheus та Grafana
2. **Ресурси**: Моніторте споживання ресурсів компонентами моніторингу
3. **Зберігання**: Налаштуйте retention policy в Prometheus для контролю розміру даних
4. **Безпека**: Змініть дефолтні паролі та налаштуйте RBAC
5. **Оновлення**: Регулярно оновлюйте образи до останніх стабільних версій

---

## Корисні посилання

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [Kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)
- [K3s Documentation](https://docs.k3s.io/)
