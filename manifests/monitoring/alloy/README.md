# Grafana Alloy (збір логів у Loki)

Alloy деплоїться **поруч із Promtail** для тестування; після перевірки логів у Loki можна вимкнути Promtail.

## Deploy

З кореня репо (де є `manifests/monitoring/kustomization.yaml`):

```bash
kubectl apply -k manifests/monitoring
```

Після цього дашборди Grafana (включно з **Alloy (Metrics and Logs)** та фільтрами **Severity (journal)** / **Severity (pods)**) підтягуються з `grafana/configmap-dashboards.yaml`. Якщо фільтри або панелі не з’явились — перезапустіть Grafana: `kubectl -n monitoring rollout restart deployment grafana`.

Або лише Alloy (якщо namespace `monitoring` вже є):

```bash
kubectl apply -f manifests/monitoring/alloy/
```

## Перевірка

- Поди: `kubectl -n monitoring get pods -l app=alloy`
- Логи пода: `kubectl -n monitoring logs -l app=alloy -f --tail=50`
- UI Alloy (метрики/стан): `kubectl -n monitoring port-forward svc/alloy 12345:12345` → http://localhost:12345

У Loki (Grafana Explore або дашборд Cluster Logs) перевірте, що з’являються логи з тими самими лейблами `job=kubernetes-pods`, `job=journal`, `job=promtail`.

## Вимкнути Promtail після міграції

У `manifests/monitoring/kustomization.yaml` закоментуйте або видаліть блок з `promtail/*`, залиште лише `alloy/*`. Потім:

```bash
kubectl apply -k manifests/monitoring
kubectl -n monitoring delete daemonset promtail
```

Конфіг: `alloy.alloy` (джерело) та ConfigMap `alloy-config` (ключ `config.alloy`).

## Дашборд Grafana

Дашборд **Alloy (Metrics and Logs)** підключається через provisioning (папка **Dashboards**): метрики з Prometheus (job=alloy, порт 12345) та логи подів Alloy з Loki. Щоб з’явились метрики, у Prometheus має бути scrape job `alloy` (додано в `prometheus/configmap.yaml`). Після `kubectl apply -k manifests/monitoring` та перезапуску Prometheus дашборд заповниться. Панель «Alloy components health» використовує метрику `alloy_runtime_component_health_state`; якщо її немає у вашій версії Alloy, панель буде порожньою — решта працює.

### Якщо дашборд показує «No data»

1. **Поди Alloy** — мають бути в статусі Running: `kubectl -n monitoring get pods -l app=alloy`
2. **Endpoints** — `kubectl -n monitoring get endpoints alloy` (мають бути адреси подів).
3. **Prometheus** — у Prometheus (Status → Targets) job `alloy` має мати targets у стані UP. Якщо ні: перезастосуйте `prometheus/configmap.yaml` і `kubectl -n monitoring rollout restart deployment prometheus`.
4. **Loki** — панель логів шукає `{job="kubernetes-pods", ...}`. Перевірте в Explore → Loki, чи є такі логи; у дашборді виберіть datasource **Loki** для панелі логів.
5. **Datasources** — у шапці дашборду виберіть **Prometheus** (для метрик) і **Loki** (для логів), якщо підставилось не те джерело.

**«Alloy components health» — No data:** панель використовує `alloy_runtime_component_health_state` та (як fallback) `alloy_component_controller_running_components`. Якщо обидві метрики відсутні у вашій збірці Alloy, панель буде порожньою — це нормально для деяких версій.

**«Alloy pods logs» / «Cluster pod logs» — No data:** логи подів збираються через **loki.source.kubernetes** (Kubernetes API), не з файлової системи ноди. Переконайтесь, що: (1) Alloy має права на `pods/log` (ClusterRole у `alloy/clusterrole.yaml`); (2) після зміни конфігу виконано `kubectl -n monitoring rollout restart daemonset alloy`; (3) у Grafana обрано datasource **Loki** для панелей логів; (4) у Explore → Loki є потік `{job="kubernetes-pods"}`. Якщо логів немає — перевірте логи Alloy: `kubectl -n monitoring logs -l app=alloy --tail=100`.
