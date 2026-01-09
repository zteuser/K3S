# Інструкція з розгортання моніторингу через Portainer UI

Цей документ містить покрокові інструкції для розгортання системи моніторингу k3s кластера через Portainer UI.

## Передумови

- Працюючий k3s кластер
- Portainer UI встановлений та налаштований
- Доступ до Portainer UI з правами адміністратора
- Мінімум 2GB вільної пам'яті та 20GB вільного дискового простору

## Порядок розгортання

### Крок 1: Створення Namespace

1. Відкрийте Portainer UI
2. Перейдіть до **Kubernetes** → **Namespaces**
3. Натисніть **Add namespace**
4. Виберіть **Editor** (YAML mode)
5. Скопіюйте вміст файлу `namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    name: monitoring
```

6. Натисніть **Create the namespace**

---

### Крок 2: Розгортання Node Exporter

Node Exporter збирає метрики з вузлів кластера (CPU, Memory, Disk, Network).

#### 2.1 Service для Node Exporter

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **Services** → **Add service**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `node-exporter/service.yaml`
5. Натисніть **Create the service**

#### 2.2 DaemonSet для Node Exporter

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **DaemonSets** → **Add DaemonSet**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `node-exporter/daemonset.yaml`
5. Натисніть **Create the DaemonSet**

**Перевірка:**
```bash
kubectl get daemonset -n monitoring node-exporter
kubectl get pods -n monitoring -l app=node-exporter
```

---

### Крок 3: Розгортання Kube-state-metrics

Kube-state-metrics збирає метрики стану кластера (pods, deployments, services).

#### 3.1 ServiceAccount

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **Service accounts** → **Add service account**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `kube-state-metrics/serviceaccount.yaml`
5. Натисніть **Create the service account**

#### 3.2 ClusterRole

1. Перейдіть до **Kubernetes** → **Cluster roles**
2. Натисніть **Add cluster role**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `kube-state-metrics/clusterrole.yaml`
5. Натисніть **Create the cluster role**

#### 3.3 ClusterRoleBinding

1. Перейдіть до **Kubernetes** → **Cluster role bindings**
2. Натисніть **Add cluster role binding**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `kube-state-metrics/clusterrolebinding.yaml`
5. Натисніть **Create the cluster role binding**

#### 3.4 Deployment

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **Deployments** → **Add deployment**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `kube-state-metrics/deployment.yaml`
5. Натисніть **Create the deployment**

#### 3.5 Service

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **Services** → **Add service**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `kube-state-metrics/service.yaml`
5. Натисніть **Create the service**

**Перевірка:**
```bash
kubectl get deployment -n monitoring kube-state-metrics
kubectl get pods -n monitoring -l app=kube-state-metrics
```

---

### Крок 4: Розгортання Prometheus

Prometheus збирає та зберігає метрики.

#### 4.1 ServiceAccount

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **Service accounts** → **Add service account**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `prometheus/serviceaccount.yaml`
5. Натисніть **Create the service account**

#### 4.2 ClusterRole

1. Перейдіть до **Kubernetes** → **Cluster roles**
2. Натисніть **Add cluster role**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `prometheus/clusterrole.yaml`
5. Натисніть **Create the cluster role**

#### 4.3 ClusterRoleBinding

1. Перейдіть до **Kubernetes** → **Cluster role bindings**
2. Натисніть **Add cluster role binding**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `prometheus/clusterrolebinding.yaml`
5. Натисніть **Create the cluster role binding**

#### 4.4 ConfigMap з конфігурацією Prometheus

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **ConfigMaps** → **Add configmap**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `prometheus/configmap.yaml`
5. Натисніть **Create the configmap**

#### 4.5 PersistentVolumeClaim для даних Prometheus

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **PVCs** → **Add PVC**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `prometheus/pvc.yaml`
5. **Важливо:** Якщо використовуєте OCFS2, розкоментуйте рядок `storageClassName: ocfs2`
6. Натисніть **Create the PVC**

#### 4.6 Deployment

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **Deployments** → **Add deployment**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `prometheus/deployment.yaml`
5. Натисніть **Create the deployment**

#### 4.7 Service

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **Services** → **Add service**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `prometheus/service.yaml`
5. Натисніть **Create the service**

**Перевірка:**
```bash
kubectl get deployment -n monitoring prometheus
kubectl get pods -n monitoring -l app=prometheus
kubectl logs -n monitoring -l app=prometheus
```

**Доступ до Prometheus UI:**
- URL: `http://<node-ip>:30001`
- Перевірте targets: `http://<node-ip>:30001/targets`

---

### Крок 5: Розгортання Grafana

Grafana для візуалізації метрик.

#### 5.1 ConfigMap з конфігурацією Grafana

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **ConfigMaps** → **Add configmap**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `grafana/configmap.yaml`
5. Натисніть **Create the configmap**

#### 5.2 ConfigMap з datasources

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **ConfigMaps** → **Add configmap**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `grafana/configmap-datasources.yaml`
5. Натисніть **Create the configmap**

#### 5.3 Secret з credentials

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **Secrets** → **Add secret**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `grafana/secret.yaml`
5. **ВАЖЛИВО:** Змініть `admin-password` на безпечний пароль!
6. Натисніть **Create the secret**

#### 5.4 PersistentVolumeClaim для даних Grafana

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **PVCs** → **Add PVC**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `grafana/pvc.yaml`
5. **Важливо:** Якщо використовуєте OCFS2, розкоментуйте рядок `storageClassName: ocfs2`
6. Натисніть **Create the PVC**

#### 5.5 Deployment

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **Deployments** → **Add deployment**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `grafana/deployment.yaml`
5. Натисніть **Create the deployment**

#### 5.6 Service

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. Виберіть **Services** → **Add service**
3. Виберіть **Editor**
4. Скопіюйте вміст файлу `grafana/service.yaml`
5. Натисніть **Create the service**

**Перевірка:**
```bash
kubectl get deployment -n monitoring grafana
kubectl get pods -n monitoring -l app=grafana
kubectl logs -n monitoring -l app=grafana
```

**Доступ до Grafana UI:**
- URL: `http://<node-ip>:30000`
- Логін: `admin`
- Пароль: (той, який ви вказали в Secret)

---

## Налаштування Grafana

### 1. Додавання Prometheus як джерела даних

1. Відкрийте Grafana: `http://<node-ip>:30000`
2. Увійдіть з credentials з Secret
3. Перейдіть до **Configuration** → **Data Sources**
4. Натисніть **Add data source**
5. Виберіть **Prometheus**
6. URL: `http://prometheus:9090`
7. Натисніть **Save & Test**

### 2. Імпорт дашбордів

#### Node Exporter Full (ID: 1860)

1. Перейдіть до **Dashboards** → **Import**
2. Введіть ID: `1860`
3. Натисніть **Load**
4. Виберіть Prometheus як джерело даних
5. Натисніть **Import**

#### Kubernetes Cluster Monitoring (ID: 7249)

1. Перейдіть до **Dashboards** → **Import**
2. Введіть ID: `7249`
3. Натисніть **Load**
4. Виберіть Prometheus як джерело даних
5. Натисніть **Import**

#### Kubernetes Pod Monitoring (ID: 6417)

1. Перейдіть до **Dashboards** → **Import**
2. Введіть ID: `6417`
3. Натисніть **Load**
4. Виберіть Prometheus як джерело даних
5. Натисніть **Import**

---

## Перевірка роботи системи

### Перевірка всіх компонентів

```bash
# Перевірка подів
kubectl get pods -n monitoring

# Перевірка сервісів
kubectl get svc -n monitoring

# Перевірка метрик Prometheus
curl http://<node-ip>:30001/api/v1/targets

# Перевірка логів
kubectl logs -n monitoring -l app=prometheus --tail=50
kubectl logs -n monitoring -l app=grafana --tail=50
```

### Очікуваний результат

Всі пода мають бути в статусі `Running`:

```
NAME                                  READY   STATUS    RESTARTS   AGE
grafana-xxxxxxxxxx-xxxxx             1/1     Running   0          5m
node-exporter-xxxxx                   1/1     Running   0          5m
node-exporter-xxxxx                   1/1     Running   0          5m
prometheus-xxxxxxxxxx-xxxxx           1/1     Running   0          5m
kube-state-metrics-xxxxxxxxxx-xxxxx  1/1     Running   0          5m
```

---

## Troubleshooting

### Prometheus не збирає метрики

1. Перевірте логи:
   ```bash
   kubectl logs -n monitoring -l app=prometheus
   ```

2. Перевірте конфігурацію:
   ```bash
   kubectl get configmap -n monitoring prometheus-config -o yaml
   ```

3. Перевірте targets в Prometheus UI: `http://<node-ip>:30001/targets`

### Grafana не підключається до Prometheus

1. Перевірте, що Prometheus працює:
   ```bash
   kubectl get pods -n monitoring -l app=prometheus
   ```

2. Перевірте URL в Grafana (має бути `http://prometheus:9090`)

3. Перевірте network connectivity:
   ```bash
   kubectl exec -n monitoring -it deployment/grafana -- wget -O- http://prometheus:9090/api/v1/status/config
   ```

### Node Exporter не збирає метрики

1. Перевірте, що DaemonSet запущений на всіх нодах:
   ```bash
   kubectl get daemonset -n monitoring
   ```

2. Перевірте логи:
   ```bash
   kubectl logs -n monitoring -l app=node-exporter
   ```

### Проблеми з PVC

Якщо PVC не створюється:

1. Перевірте доступні StorageClasses:
   ```bash
   kubectl get storageclass
   ```

2. Для k3s використовуйте `local-path` або `ocfs2`

3. Перевірте статус PVC:
   ```bash
   kubectl get pvc -n monitoring
   kubectl describe pvc -n monitoring prometheus-data
   ```

---

## Оновлення компонентів

Для оновлення через Portainer:

1. Відкрийте Deployment в Portainer
2. Натисніть **Editor**
3. Оновіть версію образу (наприклад, `prom/prometheus:v2.49.0`)
4. Натисніть **Update the deployment**

---

## Видалення моніторингу

Якщо потрібно видалити систему моніторингу:

1. Видаліть всі ресурси через Portainer UI або:
   ```bash
   kubectl delete namespace monitoring
   ```

2. **Увага:** Це видалить всі дані, включаючи історію метрик та дашборди Grafana!

---

## Корисні команди

```bash
# Перезапуск компонентів
kubectl rollout restart deployment/prometheus -n monitoring
kubectl rollout restart deployment/grafana -n monitoring

# Масштабування (якщо потрібно)
kubectl scale deployment/prometheus --replicas=2 -n monitoring

# Перевірка використання ресурсів
kubectl top pods -n monitoring
kubectl top nodes

# Експорт конфігурації
kubectl get configmap prometheus-config -n monitoring -o yaml > prometheus-config-backup.yaml
```

---

## Додаткові ресурси

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [Kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)
