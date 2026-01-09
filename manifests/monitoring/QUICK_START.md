# Швидкий старт моніторингу

## Варіанти моніторингу

### ✅ Варіант 1: Повний стек (Рекомендовано)

**Компоненти:**
- Prometheus (збір метрик)
- Grafana (візуалізація)
- Node Exporter (метрики вузлів)
- Kube-state-metrics (метрики кластера)

**Час розгортання:** ~15-20 хвилин

**Ресурси:**
- CPU: ~1.5 cores
- Memory: ~2GB
- Storage: ~15GB (10GB Prometheus + 5GB Grafana)

**Порядок розгортання через Portainer:**

1. **Namespace** → `namespace.yaml`
2. **Node Exporter** → `node-exporter/service.yaml` → `node-exporter/daemonset.yaml`
3. **Kube-state-metrics** → `kube-state-metrics/serviceaccount.yaml` → `kube-state-metrics/clusterrole.yaml` → `kube-state-metrics/clusterrolebinding.yaml` → `kube-state-metrics/deployment.yaml` → `kube-state-metrics/service.yaml`
4. **Prometheus** → `prometheus/serviceaccount.yaml` → `prometheus/clusterrole.yaml` → `prometheus/clusterrolebinding.yaml` → `prometheus/configmap.yaml` → `prometheus/pvc.yaml` → `prometheus/deployment.yaml` → `prometheus/service.yaml`
5. **Grafana** → `grafana/configmap.yaml` → `grafana/configmap-datasources.yaml` → `grafana/secret.yaml` (змініть пароль!) → `grafana/pvc.yaml` → `grafana/deployment.yaml` → `grafana/service.yaml`

**Доступ:**
- Grafana: `http://<node-ip>:30000` (admin/admin - змініть!)
- Prometheus: `http://<node-ip>:30001`

---

### ⚡ Варіант 2: Lightweight (Мінімальний)

**Компоненти:**
- Grafana (візуалізація)
- Node Exporter (метрики вузлів)
- Використання вбудованих метрик k3s

**Час розгортання:** ~5-10 хвилин

**Ресурси:**
- CPU: ~0.5 cores
- Memory: ~500MB
- Storage: ~5GB

**Порядок розгортання:**

1. **Namespace** → `namespace.yaml`
2. **Node Exporter** → `node-exporter/service.yaml` → `node-exporter/daemonset.yaml`
3. **Grafana** (без Prometheus, використовує вбудовані метрики k3s)

**Обмеження:**
- Немає історії метрик
- Обмежені можливості алертів

---

### 📊 Варіант 3: Тільки Prometheus (для розробки)

**Компоненти:**
- Prometheus (збір метрик)
- Node Exporter
- Kube-state-metrics

**Час розгортання:** ~10 хвилин

**Ресурси:**
- CPU: ~1 core
- Memory: ~1GB
- Storage: ~10GB

**Доступ:**
- Prometheus UI: `http://<node-ip>:30001`
- PromQL запити для аналізу

---

## Швидка перевірка

Після розгортання перевірте:

```bash
# Перевірка подів
kubectl get pods -n monitoring

# Перевірка сервісів
kubectl get svc -n monitoring

# Перевірка логів Prometheus
kubectl logs -n monitoring -l app=prometheus --tail=20

# Перевірка логів Grafana
kubectl logs -n monitoring -l app=grafana --tail=20
```

---

## Налаштування Grafana (після розгортання)

1. Відкрийте `http://<node-ip>:30000`
2. Логін: `admin`, Пароль: (з Secret)
3. **Configuration** → **Data Sources** → **Add** → **Prometheus**
4. URL: `http://prometheus:9090`
5. **Save & Test**
6. **Dashboards** → **Import** → ID: `1860` (Node Exporter)

---

## Важливі нотатки

⚠️ **Безпека:**
- Обов'язково змініть пароль Grafana в `grafana/secret.yaml`
- Для production налаштуйте Ingress замість NodePort
- Налаштуйте RBAC для обмеження доступу

💾 **Storage:**
- Якщо використовуєте OCFS2, розкоментуйте `storageClassName: ocfs2` в PVC
- Для k3s default storage використовується `local-path`

🔧 **Налаштування:**
- Retention Prometheus: 30 днів (можна змінити в `prometheus/deployment.yaml`)
- Розмір PVC можна змінити в `prometheus/pvc.yaml` та `grafana/pvc.yaml`
