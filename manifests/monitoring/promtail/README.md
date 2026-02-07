# Promtail (Фаза 3 з LOGGING_PLAN)

DaemonSet на кожній ноді: збирає логи контейнерів з `/var/log/pods` та логи systemd journal з `/var/log/journal`, відправляє в Loki.

## Що збирається

- **kubernetes-pods:** логи всіх контейнерів (namespace, pod, container, node) з `/var/log/pods`.
- **journal:** логи systemd (k3s, k3s-agent тощо) з мітками `job=journal`, `unit`, `nodename`.

## Планування на нодах

За замовчуванням Promtail планується **лише на master-node** (nodeSelector), бо на worker-нодах часто немає маршруту до API (10.43.0.1) та Loki — виникають "no route to host" і "context deadline exceeded". Loki теж на master-node. Логи збираються з master-node (поди + journal). Щоб збирати логи з усіх нод — налаштуйте доступ до ClusterIP з worker-нод за інструкцією **`manifests/FIX_CLUSTERIP_ACCESS_FROM_ALL_NODES.md`**, потім приберіть nodeSelector з DaemonSet.

## Вимоги на нодах

- Каталог `/var/log/pods` (стандартний шлях логів подів у k3s).
- Каталог `/var/log/journal` (journald, для логів k3s).
- Файл `/etc/machine-id` (для читання journal).

## Деплой

Разом з усім monitoring stack:

```bash
kubectl apply -k manifests/monitoring
```

Або окремо:

```bash
kubectl apply -f manifests/monitoring/promtail/serviceaccount.yaml
kubectl apply -f manifests/monitoring/promtail/clusterrole.yaml
kubectl apply -f manifests/monitoring/promtail/clusterrolebinding.yaml
kubectl apply -f manifests/monitoring/promtail/configmap.yaml
kubectl apply -f manifests/monitoring/promtail/daemonset.yaml
kubectl apply -f manifests/monitoring/promtail/service.yaml
```

Service потрібен для дашборду Grafana 20881 (Promtail Monitoring): Prometheus скрапить метрики Promtail через endpoints discovery. Детальніше — **`manifests/monitoring/PROMTAIL_DASHBOARD_20881.md`**.

## Перевірка

```bash
kubectl -n monitoring get pods -l app=promtail
kubectl -n monitoring logs -l app=promtail --tail=30
```

У Grafana Explore (Loki) через кілька хвилин мають з’явитися логи за мітками `namespace`, `pod`, `container`, `job=journal`, `unit`.

## Якщо Promtail показує "context deadline exceeded" при POST до Loki

1. **Таймаут клієнта:** у конфігу встановлено `timeout: 30s` і `batchwait: 2s`. Після оновлення ConfigMap перезапустіть поди: `kubectl -n monitoring apply -f manifests/monitoring/promtail/configmap.yaml` і `kubectl -n monitoring delete pod -l app=promtail`.

2. **DNS/мережа між нодами:** якщо Loki на одній ноді, а Promtail на інших — спробуйте URL через ClusterIP: `kubectl -n monitoring get svc loki -o wide`, потім у ConfigMap змініть `url` на `http://<ClusterIP>:3100/loki/api/v1/push`.

3. **Навантаження на Loki:** перевірте `kubectl -n monitoring logs -l app=loki --tail=50`; при потребі збільште ресурси або retention у Loki.

## Якщо в Grafana Explore (Loki) "No logs found" для `{namespace="monitoring"}`

1. **Де запущені поди monitoring:** Promtail зараз тільки на master-node, тому в Loki потрапляють **лише логи з подів, що працюють на master-node**. Якщо Grafana, Loki тощо заплановані на **macmini7** або **beelinkeqr5**, їхні логи не збираються — тому `{namespace="monitoring"}` порожній, а `{job=~".+"}` показує логи з інших namespace або з journal на master-node. Перевірка:
   ```bash
   kubectl -n monitoring get pods -o wide
   ```
   Якщо колонка NODE для grafana/loki не **master-node** — це і є причина. Варіанти: залишити як є (логи з master-node достатні); або налаштувати scheduling так, щоб частина monitoring-подів була на master-node; або виправити мережу й знову запустити Promtail на всіх нодах (прибрати nodeSelector).

2. **Чи Promtail взагалі щось відправляє:** у Grafana Explore спробуйте запит з мінімальним фільтром (Loki не приймає порожній `{}`). Наприклад: `{namespace=~".+"}` або `{job=~".+"}` (time range "Last 1 hour"). Якщо з’являться логи з інших namespace або `job="journal"`, значить Promtail працює.

3. **Логи самого Promtail:** перевірте, чи немає помилок читання або push:
   ```bash
   kubectl -n monitoring logs -l app=promtail --tail=100
   ```
   Шукайте помилки типу "permission denied", "no such file", "context deadline exceeded", "connection refused".

4. **Loki приймає push:** перевірте логи Loki на наявність помилок прийому:
   ```bash
   kubectl -n monitoring logs -l app=loki --tail=50
   ```

5. **Час:** переконайтеся, що в Grafana обрано коректний time range (наприклад "Last 1 hour" або "Last 15 minutes") — логи з’являються з невеликою затримкою.

## Помилки: "connection refused" до API (10.43.0.1), "empty ring" / "connection refused" до Loki

Ці помилки в логах Promtail означають:

- **`dial tcp 10.43.0.1:443: connect: connection refused`** — под не може досягти Kubernetes API (кланстерний ClusterIP). На worker-нодах це типова ситуація, якщо мережа між нодами не налаштована (див. **`manifests/FIX_CLUSTERIP_ACCESS_FROM_ALL_NODES.md`**).
- **`lookup loki on 10.43.0.10:53: read: connection refused`** або **`i/o timeout`** — з worker-ноди не працює DNS або досяжність до Loki.
- **`empty ring`**, **`dial tcp 10.43.x.x:3100: connect: connection refused`** — Loki перезапускався або ще не готовий приймати push.

**Що зробити:**

1. **Залишити Promtail лише на master-node**, щоб уникнути помилок на worker-нодах. Перевірте, скільки подів Promtail і на яких нодах:
   ```bash
   kubectl -n monitoring get pods -l app=promtail -o wide
   ```
   Має бути **один** под, на ноді з hostname, який збігається з `nodeSelector` у DaemonSet. Якщо нода master має інший hostname (наприклад `macmini7` або `beelinkeqr5`), оновіть nodeSelector у `daemonset.yaml`:
   ```yaml
   nodeSelector:
     kubernetes.io/hostname: macmini7   # або фактичний hostname master-ноди
   ```
   Перевірка hostname нод: `kubectl get nodes -o custom-columns=NAME:.metadata.name`. Потім застосуйте маніфест і перезапустіть: `kubectl apply -f manifests/monitoring/promtail/daemonset.yaml`, `kubectl -n monitoring delete pod -l app=promtail`.

2. **Переконатися, що Loki працює.** Помилки "empty ring" або "connection refused" до IP Loki часто з’являються під час рестарту Loki. Перевірте стан пода і при потребі перезапустіть:
   ```bash
   kubectl -n monitoring get pods -l app=loki
   kubectl -n monitoring logs -l app=loki --tail=30
   kubectl -n monitoring delete pod -l app=loki
   ```

3. Після того як залишиться один Promtail на master і Loki буде в стані Running, почекайте 1–2 хвилини і повторіть запит у Grafana (наприклад `{namespace="monitoring"}` або `{job=~".+"}`).
