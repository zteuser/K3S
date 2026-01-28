# Виправлення "No data" / "N/A" на дашборді Kubernetes Cluster (Prometheus)

## Симптоми

- У Prometheus **усі targets UP** (node-exporter, kube-state-metrics, cadvisor, prometheus тощо).
- У Grafana дашборд **"Kubernetes Cluster (Prometheus)"** показує **N/A** для Usage і **No data** для Capacity (CPU, Memory, Disk).

## Можливі причини

1. **Дашборд розрахований на kube-state-metrics v1** — у вас kube-state-metrics **v2** (v2.10.1), метрики мають інші назви або лейбли.
2. **Змінна $node** — дашборд фільтрує по лейблу `node`, а node-exporter віддає `instance` (IP:port); панелі очікують `node=~"$node"` і не знаходять рядків.
3. **Datasource** — Grafana підключена не до того Prometheus або з неправильним URL.

---

## Крок 1: Перевірити метрики в Prometheus

У Prometheus UI (`http://<node-ip>:30001` або через Ingress) відкрийте **Graph** і виконайте:

```promql
# Мають повертати рядки (не порожній результат)
up{job="node-exporter"}
up{job="kube-state-metrics"}
kube_pod_info
# kube-state-metrics v2 — allocatable/capacity з лейблом resource (не _cpu_cores / _pods)
kube_node_status_allocatable{resource="cpu"}
kube_node_status_allocatable{resource="pods"}
kube_node_status_capacity{resource="cpu"}
node_cpu_seconds_total{mode="idle"}
node_memory_MemTotal_bytes
```

**Важливо:** Дашборди під v1 шукають метрики `kube_node_status_allocatable_cpu_cores`, `kube_node_status_allocatable_pods` — у **v2 цих назв немає**, тому ці запити будуть порожні. У v2 використовуються `kube_node_status_allocatable{resource="cpu"}`, `kube_node_status_allocatable{resource="pods"}` тощо. Якщо ці (v2) запити повертають дані — Prometheus збирає все правильно, проблема лише в тому, що дашборд розрахований на v1.

Якщо **всі запити (v2) повертають дані** — Prometheus збирає метрики, проблема в дашборді (потрібен дашборд 16520 або зміна запитів на v2).

Якщо **деякі порожні** — перевірте відповідний target (kube-state-metrics / node-exporter) і конфіг Prometheus.

---

## Крок 2: Перевірити datasource у Grafana

1. Grafana → **Connections** → **Data sources** → **Prometheus**.
2. **URL:** має бути `http://prometheus:9090` (або `http://prometheus.monitoring.svc.cluster.local:9090`).
3. **Save & test** — має бути "Data source is working".

Якщо тест не проходить — перевірте, що под Grafana може доступитися до сервісу Prometheus (поди в тому ж кластері, без мережевих політик, що блокують).

---

## Крок 3: Дашборд сумісний з kube-state-metrics v2

Дашборд **"Kubernetes Cluster (Prometheus)"** (часто імпортований з Grafana.com, ID 7249) був зроблений під **kube-state-metrics v1**. У вас **v2.10.1** — метрики та лейбли відрізняються, тому панелі можуть показувати "No data".

| v1 (дашборд 7249) | v2 (у вашому кластері) |
|-------------------|-------------------------|
| `kube_node_status_allocatable_cpu_cores` | `kube_node_status_allocatable{resource="cpu"}` |
| `kube_node_status_allocatable_pods` | `kube_node_status_allocatable{resource="pods"}` |
| `kube_node_status_capacity_*` | `kube_node_status_capacity{resource="..."}` |

Якщо в Prometheus `kube_pod_info` є, а `kube_node_status_allocatable_pods` і `kube_node_status_allocatable_cpu_cores` — порожні, це очікувано: у v2 такі метрики не експортуються, використовуйте запити вище або дашборд 16520.

**Варіант A: Імпортувати дашборд під v2**

1. Grafana → **Dashboards** → **New** → **Import**.
2. Введіть ID: **16520** (Kube-state-metrics v2) або знайдіть дашборд з підписом "kube-state-metrics v2".
3. Виберіть Prometheus datasource, **Import**.

Після імпорту перевірте панелі — мають з’явитися дані по нодах/подах/ресурсах.

**Варіант B: Змінити змінну $node на дашборді 7249**

Якщо залишаєте дашборд "Kubernetes Cluster (Prometheus)" (7249):

1. Відкрийте дашборд → **Dashboard settings** (іконка шестерні) → **Variables**.
2. Знайдіть змінну **node** (або подібну).
3. Якщо в **Query** використовується щось на кшталт `label_values(kube_node_info, node)` — залиште; якщо змінна порожня, перевірте в **Explore**, що `kube_node_info` повертає рядки з лейблом `node`.
4. Для панелей, що беруть дані з **node-exporter**, дашборд часто фільтрує по `instance` (наприклад `node_cpu_seconds_total{instance=~"$node"}`). У node-exporter лейбл `instance` = `IP:9100`, а не ім’я ноди. Тому змінна **node** має містити значення типу `10.0.10.10:9100`, `10.0.10.20:9100`, `192.168.2.19:9100`. Якщо змінна заповнена з `kube_node_info` (master-node, work-node, macmini7), то запити на node-exporter з `node=~"$node"` не збігаються — потрібно або змінити Query змінної на `label_values(up{job="node-exporter"}, instance)`, або в панелях використовувати відповідність node name ↔ instance (наприклад через recording rules або інший лейбл).

Найпростіше — імпортувати дашборд **16520** (v2) і використовувати його замість 7249.

---

## Крок 4: kube-state-metrics — статична IP у Prometheus

У `prometheus/configmap.yaml` job **kube-state-metrics** використовує статичний target `10.42.2.24:8080` (pod IP). Після перезапуску пода IP змінюється і target стає DOWN.

**Краще:** використовувати **Service** замість статичної IP:

```yaml
# Замість static_configs з IP використати:
      - job_name: 'kube-state-metrics'
        static_configs:
          - targets: ['kube-state-metrics.monitoring.svc.cluster.local:8080']
        scrape_interval: 30s
        scrape_timeout: 20s
```

Після зміни застосуйте ConfigMap і перезапустіть Prometheus:

```bash
kubectl apply -f manifests/monitoring/prometheus/configmap.yaml
kubectl rollout restart deployment prometheus -n monitoring
```

Тоді target kube-state-metrics залишатиметься UP навіть після перезапуску пода.

---

## Підсумок

| Крок | Дія |
|------|-----|
| 1 | У Prometheus перевірити, що є дані по `up`, `kube_node_info`, `kube_node_status_capacity`, `node_cpu_seconds_total`, `node_memory_*`. |
| 2 | У Grafana перевірити Prometheus datasource (URL, Save & test). |
| 3 | Імпортувати дашборд **16520** (Kube-state-metrics v2) або виправити змінні/запити на поточному дашборді. |
| 4 | У конфігу Prometheus замінити статичний IP kube-state-metrics на `kube-state-metrics.monitoring.svc.cluster.local:8080`. |

Після цього панелі "Kubernetes Cluster" мають показувати дані по нодах, подах і ресурсах.
