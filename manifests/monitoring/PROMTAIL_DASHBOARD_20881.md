# Дашборд Grafana 20881 — Promtail Monitoring (Metrics and Logs)

Дашборд [Promtail Monitoring - Metrics and Logs](https://grafana.com/grafana/dashboards/20881-promtail-monitoring-metrics-and-logs/) показує метрики та логи **самого Promtail**. Щоб він заповнився даними, потрібні:

1. **Prometheus** скрапить метрики Promtail на порту 9080 з **job=promtail**.
2. **Loki** отримує логи **Promtail** з мітками **job=promtail** та **instance=** (ім’я ноди).

Документація автора: [voidquark — Promtail Grafana dashboard](https://voidquark.com/blog/promtail-grafana-dashboard/).

## Що зроблено в цьому репо

- **Prometheus:** додано scrape job `promtail` (Kubernetes endpoints discovery у namespace `monitoring`, порт 9080, мітки `job=promtail`, `instance=<node_name>`).
- **Promtail:** Service на порту 9080 для discovery; у конфігу Promtail для логів подів з namespace=monitoring та іменем `promtail-*` встановлюються `job=promtail` та `instance=<node>`, щоб власні логи Promtail потрапляли в Loki з потрібними мітками.
- **Kustomization:** додано `promtail/service.yaml`.

## Після деплою

1. Застосуйте зміни (ConfigMap Prometheus, ConfigMap Promtail, Service Promtail, перезапуск подів за потреби):

   ```bash
   kubectl apply -k manifests/monitoring
   kubectl -n monitoring apply -f manifests/monitoring/prometheus/configmap.yaml
   kubectl -n monitoring apply -f manifests/monitoring/promtail/configmap.yaml
   kubectl -n monitoring apply -f manifests/monitoring/promtail/service.yaml
   kubectl -n monitoring delete pod -l app=prometheus  # перезавантажити Prometheus для нового конфігу
   kubectl -n monitoring delete pod -l app=promtail  # щоб нові логи йшли з job=promtail
   ```

2. Переконайтеся, що Prometheus бачить targets з job=promtail:
   - **Prometheus → Status → Targets** — має бути job **promtail** (статус UP).
   - У **Explore (Prometheus)** запит `promtail_build_info{job="promtail"}` має повертати рядки.

3. Переконайтеся, що в Loki є логи Promtail з job=promtail:
   - **Grafana → Explore → Loki** — запит `{job="promtail"}` має показувати логи (через 1–2 хв після перезапуску Promtail).

4. У дашборді **20881** у верхніх змінних виберіть:
   - **Datasource Loki** — ваш Loki.
   - **Datasource Prometheus** — ваш Prometheus.
   - **Job** — `promtail` (з Prometheus).
   - **Instance** — потрібна нода або All (значення беруться з Loki/Prometheus для job=promtail).
   - **Label Name** / **Label Value** — за потреби для вашого кластера (часто можна залишити за замовчуванням).

Після цього панелі метрик (Promtail Version, Active Files, Current Sent Bytes тощо) та панель «Promtail Recent Logs» мають показувати дані.

## Якщо все ще «No data»

- Перевірте, що поди Promtail слухають 9080: `kubectl -n monitoring get pods -l app=promtail -o wide` і що Service існує: `kubectl -n monitoring get svc promtail`.
- У Prometheus перевірте, що конфіг завантажився: **Status → Configuration** — має бути job `promtail` з `kubernetes_sd_configs` (role: endpoints).
- У Loki перевірте запит `{job="promtail"}` за останні 15 хвилин; якщо логів немає — перезапустіть Promtail і дочекайтеся 1–2 хв.
