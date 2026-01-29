# Виправлення "No data" у розділі Pods дашборду kube-state-metrics-v2

## Симптоми

- Дашборд **kube-state-metrics-v2** (Grafana) у розділі **Pods** показує "No data" для панелей:
  - Container CPU Usage %
  - Container Memory Usage %
  - Container File Descriptors
  - Container FS Usage %

## Причина

Ці панелі використовують **метрики контейнерів** (CPU/memory usage у реальному часі), які постачає **cAdvisor** (через kubelet), а **не** kube-state-metrics. kube-state-metrics дає лише стан об’єктів (requests/limits, статус подів), а не фактичне використання CPU/пам’яті контейнерами.

## Крок 1: Перевірити target cadvisor у Prometheus

1. Відкрийте Prometheus → **Status** → **Targets** (`http://<node-ip>:30001/targets` або через Ingress).
2. Знайдіть job **cadvisor** (або **kubernetes-cadvisor**).
3. Перевірте стан:
   - **UP** — Prometheus успішно скрапить cAdvisor; перейдіть до кроку 2.
   - **DOWN** або помилка — Prometheus не може отримати метрики; перейдіть до кроку 3.

## Крок 2: Перевірити наявність метрик у Prometheus

У Prometheus → **Graph** виконайте:

```promql
# Мають повертати рядки (контейнери на нодах)
container_cpu_usage_seconds_total
container_memory_usage_bytes
```

Якщо **є дані** — проблема може бути у часі/фільтрах дашборду або в іменах метрик (нові версії kubelet іноді змінюють назви). Спробуйте змінити time range на "Last 15 minutes" і оновити дашборд.

Якщо **немає даних** при UP target — перевірте, чи не відфільтровані метрики (metric_relabel_configs), і чи правильний scrape path (`/metrics/cadvisor`).

## Якщо cadvisor і kube-state-metrics обидва DOWN (DNS timeout)

**Помилки в Targets:** `lookup kubernetes.default.svc on 10.43.0.10:53: i/o timeout` та `context deadline exceeded` для kube-state-metrics.

**Причина:** Под Prometheus запланований на ноду (наприклад work-node), з якої немає маршруту до CoreDNS/API, тому DNS не відповідає вчасно.

**Що зробити:**

1. **Прив’язати Prometheus до ноди, де працює DNS:** у `prometheus/deployment.yaml` додати (або розкоментувати) `nodeSelector: kubernetes.io/hostname: master-node` (або `macmini7`, якщо CoreDNS там). Після apply і перезапуску пода Prometheus буде на master-node/macmini7 і targets стануть UP.
2. **Повний FQDN для API:** у `prometheus/configmap.yaml` у job cadvisor для `__address__` використовувати `kubernetes.default.svc.cluster.local:443` замість `kubernetes.default.svc:443`.

У репозиторії вже застосовано обидва варіанти (nodeSelector master-node і FQDN у configmap).

---

## Крок 3: Якщо target cadvisor DOWN — виправити scrape

Поточна конфігурація в `prometheus/configmap.yaml` скрапить kubelet **напряму** по IP (`https://10.0.10.10:10250/metrics/cadvisor` тощо) з bearer token. У k3s kubelet може не приймати цей token при прямому з’єднанні, тому краще використовувати **API server proxy**: Prometheus звертається до API сервера, який проксує запити до kubelet (RBAC у вас уже є: `nodes/proxy` для Prometheus).

### Варіант A: cAdvisor через API server proxy (рекомендовано для k3s)

Замініть job `cadvisor` у ConfigMap на:

```yaml
      - job_name: 'cadvisor'
        kubernetes_sd_configs:
          - role: node
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          # Проксувати через API server, щоб bearer token приймався
          - source_labels: [__meta_kubernetes_node_name]
            target_label: __metrics_path__
            replacement: /api/v1/nodes/$1/proxy/metrics/cadvisor
            regex: (.+)
          - target_label: __address__
            replacement: kubernetes.default.svc:443
          - source_labels: [__meta_kubernetes_node_name]
            target_label: node
            replacement: $1
            regex: (.+)
          - source_labels: [__meta_kubernetes_node_name]
            target_label: instance
            replacement: $1
            regex: (.+)
        scrape_interval: 30s
        scrape_timeout: 20s
```

**Важливо:** У першому relabel має бути `regex: (.+)`, щоб `$1` підставив ім’я ноди.

Після зміни:

```bash
kubectl apply -f manifests/monitoring/prometheus/configmap.yaml -n monitoring
kubectl rollout restart deployment/prometheus -n monitoring
```

Перевірте Targets — cadvisor має стати UP для кожної ноди.

### Варіант B: Прямий scrape по IP (якщо API proxy недоступний)

У репозиторії за замовчуванням тепер використовується **API proxy** (варіант A). Якщо потрібно повернути прямий scrape по IP — приклад у **FIX_CADVISOR.md**. Переконайтеся, що поди Prometheus можуть досягти IP нод на порту 10250; у k3s при прямому з’єднанні kubelet часто не приймає bearer token, тому рекомендовано API proxy.

## Крок 4: Перевірити RBAC

Для доступу через API proxy потрібні права на `nodes/proxy`. У `prometheus/clusterrole.yaml` має бути:

```yaml
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - ...
  verbs: ["get", "list", "watch"]
```

У вас це вже є.

## Підсумок

| Крок | Дія |
|------|-----|
| 1 | Prometheus → Targets: cadvisor має бути UP. |
| 2 | Prometheus → Graph: перевірити `container_cpu_usage_seconds_total`, `container_memory_usage_bytes`. |
| 3 | Якщо cadvisor DOWN — замінити job на scrape через API proxy (приклад вище). |
| 4 | Після apply ConfigMap — restart Prometheus, перевірити Targets і дашборд Pods. |

Після того як cadvisor стане UP і метрики з’являться в Prometheus, розділ **Pods** на дашборді kube-state-metrics-v2 має показувати дані (можливо, після оновлення часу "Last 5 minutes" / "Last 15 minutes").
