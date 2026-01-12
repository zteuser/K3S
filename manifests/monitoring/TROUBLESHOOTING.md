# Troubleshooting моніторингу

## Проблеми з Prometheus

### Помилка: "permission denied" для queries.active

**Симптоми:**
```
level=error component=activeQueryTracker msg="Error opening query log file" 
file=/prometheus/queries.active err="open /prometheus/queries.active: permission denied"
panic: Unable to create mmap-ed active query log
```

**Причина:**
Prometheus не може створити файли в директорії `/prometheus` через відсутність прав доступу.

**Рішення:**

#### Варіант 1: Використати оновлений deployment (рекомендовано)

Оновлений `prometheus/deployment.yaml` вже містить:
- `securityContext` з правильними UID/GID (65534 - nobody)
- `initContainer` для встановлення прав на директорію

Просто оновіть deployment через Portainer:
1. Відкрийте **Kubernetes** → **Applications** → **monitoring**
2. Знайдіть deployment **prometheus**
3. Натисніть **Editor**
4. Скопіюйте оновлений вміст `prometheus/deployment.yaml`
5. Натисніть **Update**

#### Варіант 2: Використати root права (якщо OCFS2 потребує)

Якщо initContainer не допомагає, використайте `deployment-fix-permissions.yaml`:

1. В Portainer відкрийте deployment **prometheus**
2. Замініть вміст на `prometheus/deployment-fix-permissions.yaml`
3. Оновіть deployment

#### Варіант 3: Встановити права вручну (якщо маєте доступ до ноди)

```bash
# Знайдіть pod
kubectl get pods -n monitoring -l app=prometheus

# Виконайте команду в pod
kubectl exec -n monitoring -it <pod-name> -- chown -R 65534:65534 /prometheus
kubectl exec -n monitoring -it <pod-name> -- chmod -R 755 /prometheus

# Перезапустіть pod
kubectl delete pod -n monitoring -l app=prometheus
```

#### Варіант 4: Використати initContainer з chmod

Якщо initContainer не працює, перевірте логи:

```bash
kubectl logs -n monitoring <pod-name> -c init-prometheus-dir
```

Якщо initContainer не запускається, переконайтеся що:
- Образ `busybox:1.36` доступний
- Volume правильно підключений
- Security context дозволяє root для initContainer

---

### Prometheus не збирає метрики

**Симптоми:**
- Targets показують статус "DOWN"
- Немає метрик в Prometheus UI

**Перевірка:**

1. **Перевірте логи:**
   ```bash
   kubectl logs -n monitoring -l app=prometheus
   ```

2. **Перевірте targets:**
   - Відкрийте Prometheus UI: `http://<node-ip>:30001/targets`
   - Перевірте статус кожного target

3. **Перевірте конфігурацію:**
   ```bash
   kubectl get configmap -n monitoring prometheus-config -o yaml
   ```

4. **Перевірте ServiceAccount та RBAC:**
   ```bash
   kubectl get serviceaccount -n monitoring prometheus
   kubectl get clusterrolebinding prometheus
   ```

**Рішення:**

- Перевірте, що ServiceAccount існує та має правильні права
- Перевірте, що ClusterRole та ClusterRoleBinding створені
- Перевірте network connectivity між Prometheus та targets

---

### Prometheus pod не запускається

**Симптоми:**
- Pod в статусі `CrashLoopBackOff` або `Error`

**Перевірка:**

1. **Перевірте опис поду:**
   ```bash
   kubectl describe pod -n monitoring -l app=prometheus
   ```

2. **Перевірте логи:**
   ```bash
   kubectl logs -n monitoring -l app=prometheus
   ```

3. **Перевірте events:**
   ```bash
   kubectl get events -n monitoring --sort-by='.lastTimestamp'
   ```

**Типові проблеми:**

- **Image pull error:** Перевірте доступність образу
- **PVC не прив'язаний:** Перевірте статус PVC
- **Resource limits:** Перевірте, чи достатньо ресурсів на ноді
- **Node selector:** Перевірте, чи pod може бути запланований на ноду

---

## Проблеми з Grafana

### Grafana не підключається до Prometheus

**Симптоми:**
- В Grafana показує помилку при підключенні до Prometheus
- "Data source is not working"

**Перевірка:**

1. **Перевірте URL в Grafana:**
   - Має бути: `http://prometheus:9090` (внутрішній сервіс)
   - НЕ: `http://<node-ip>:30001` (зовнішній NodePort)

2. **Перевірте, що Prometheus працює:**
   ```bash
   kubectl get pods -n monitoring -l app=prometheus
   kubectl get svc -n monitoring prometheus
   ```

3. **Перевірте network connectivity:**
   ```bash
   kubectl exec -n monitoring -it deployment/grafana -- wget -O- http://prometheus:9090/api/v1/status/config
   ```

**Рішення:**

- Перевірте ConfigMap з datasources: `grafana/configmap-datasources.yaml`
- Переконайтеся, що URL правильний: `http://prometheus:9090`
- Перезапустіть Grafana pod після зміни конфігурації

---

### Grafana не зберігає дані

**Симптоми:**
- Дашборди зникають після перезапуску
- Налаштування не зберігаються

**Причина:**
PVC не підключений або має неправильні права.

**Рішення:**

1. **Перевірте PVC:**
   ```bash
   kubectl get pvc -n monitoring grafana-data
   kubectl describe pvc -n monitoring grafana-data
   ```

2. **Перевірте права:**
   ```bash
   kubectl exec -n monitoring -it deployment/grafana -- ls -la /var/lib/grafana
   ```

3. **Встановіть права (якщо потрібно):**
   ```bash
   kubectl exec -n monitoring -it deployment/grafana -- chown -R 472:472 /var/lib/grafana
   ```

---

## Проблеми з Node Exporter

### Node Exporter не збирає метрики

**Симптоми:**
- Немає метрик вузлів в Prometheus
- Targets показують "DOWN"

**Перевірка:**

1. **Перевірте DaemonSet:**
   ```bash
   kubectl get daemonset -n monitoring node-exporter
   kubectl get pods -n monitoring -l app=node-exporter
   ```

2. **Перевірте, що поди запущені на всіх нодах:**
   ```bash
   kubectl get pods -n monitoring -l app=node-exporter -o wide
   ```

3. **Перевірте логи:**
   ```bash
   kubectl logs -n monitoring -l app=node-exporter
   ```

**Рішення:**

- Перевірте, що DaemonSet створено правильно
- Перевірте, що hostNetwork та hostPID дозволені
- Перевірте, що порт 9100 не зайнятий на нодах

---

## Проблеми з PVC/Storage

### PVC не прив'язується до PV

**Симптоми:**
- PVC в статусі `Pending`
- Помилка "no persistent volumes available"

**Перевірка:**

1. **Перевірте статус PVC:**
   ```bash
   kubectl get pvc -n monitoring
   kubectl describe pvc -n monitoring prometheus-data
   ```

2. **Перевірте доступні PV:**
   ```bash
   kubectl get pv
   ```

3. **Перевірте storage class:**
   ```bash
   kubectl get storageclass
   ```

**Рішення:**

- Перевірте, що storage class існує та доступний
- Перевірте, що access modes співпадають між PVC та PV
- Перевірте, що розмір PVC не перевищує розмір PV
- Якщо використовуєте `volumeName`, перевірте що PV існує та має статус "Available"

---

### Помилка: "volume is already bound"

**Причина:**
PV вже прив'язаний до іншого PVC.

**Рішення:**

1. **Знайдіть, який PVC використовує PV:**
   ```bash
   kubectl get pv pv-sharedata1 -o jsonpath='{.spec.claimRef.name}'
   ```

2. **Видаліть старий PVC (якщо не використовується):**
   ```bash
   kubectl delete pvc <old-pvc-name> -n <namespace>
   ```

3. **Перевірте, що PV звільнений:**
   ```bash
   kubectl get pv pv-sharedata1
   # Статус має бути "Available"
   ```

---

## Загальні проблеми

### Поди не запускаються

**Перевірка:**

1. **Опис поду:**
   ```bash
   kubectl describe pod -n monitoring <pod-name>
   ```

2. **Events:**
   ```bash
   kubectl get events -n monitoring --sort-by='.lastTimestamp'
   ```

3. **Ресурси ноди:**
   ```bash
   kubectl top nodes
   kubectl describe node <node-name>
   ```

**Типові причини:**

- Недостатньо ресурсів (CPU/Memory)
- Image pull errors
- PVC не прив'язаний
- Node selector не відповідає
- Taints/Tolerations

---

### Network connectivity проблеми

**Перевірка:**

1. **DNS:**
   ```bash
   kubectl exec -n monitoring -it deployment/prometheus -- nslookup prometheus
   kubectl exec -n monitoring -it deployment/grafana -- nslookup prometheus
   ```

2. **HTTP connectivity:**
   ```bash
   kubectl exec -n monitoring -it deployment/grafana -- wget -O- http://prometheus:9090/api/v1/status/config
   ```

3. **Service endpoints:**
   ```bash
   kubectl get endpoints -n monitoring
   ```

---

## Корисні команди для діагностики

```bash
# Загальний статус
kubectl get all -n monitoring

# Логи всіх компонентів
kubectl logs -n monitoring -l app=prometheus --tail=50
kubectl logs -n monitoring -l app=grafana --tail=50
kubectl logs -n monitoring -l app=node-exporter --tail=50

# Опис ресурсів
kubectl describe deployment -n monitoring prometheus
kubectl describe deployment -n monitoring grafana
kubectl describe daemonset -n monitoring node-exporter

# Перевірка RBAC
kubectl get serviceaccount -n monitoring
kubectl get clusterrole prometheus
kubectl get clusterrolebinding prometheus

# Перевірка storage
kubectl get pvc -n monitoring
kubectl get pv

# Перевірка сервісів
kubectl get svc -n monitoring
kubectl get endpoints -n monitoring

# Events
kubectl get events -n monitoring --sort-by='.lastTimestamp'
```

---

## Отримання допомоги

Якщо проблема не вирішена:

1. Зберіть інформацію:
   ```bash
   kubectl get all -n monitoring -o yaml > monitoring-status.yaml
   kubectl describe pods -n monitoring > monitoring-pods-describe.txt
   kubectl logs -n monitoring -l app=prometheus > prometheus-logs.txt
   ```

2. Перевірте документацію:
   - [Prometheus Documentation](https://prometheus.io/docs/)
   - [Grafana Documentation](https://grafana.com/docs/)
   - [K3s Documentation](https://docs.k3s.io/)

3. Перевірте GitHub issues:
   - [Prometheus](https://github.com/prometheus/prometheus/issues)
   - [Grafana](https://github.com/grafana/grafana/issues)
