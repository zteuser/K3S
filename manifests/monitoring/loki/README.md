# Loki (namespace: monitoring)

Loki деплоїться в **namespace `monitoring`** поруч з Prometheus та Grafana.

## Volume

- **PVC:** `loki-data`
- **Розмір:** 10 ГіБ
- **StorageClass:** `ocfs2-shared` (файл `manifests/storage/storageclass-ocfs2.yaml`)

Для no-provisioner (OCFS2) у репозиторії є **PV** `manifests/monitoring/loki/persistentvolume.yaml` (10 ГіБ, шлях `/sharedata1/loki` на нодах master-node/work-node). Застосуйте його **перед** PVC: `kubectl apply -f manifests/monitoring/loki/persistentvolume.yaml`.

## Деплой

Через Kustomize (разом з усім monitoring stack):

```bash
kubectl apply -k manifests/monitoring
```

Або окремо:

```bash
# 1. PV (щоб PVC міг прив'язатися)
kubectl apply -f manifests/monitoring/loki/persistentvolume.yaml
# 2. Решта
kubectl apply -f manifests/monitoring/loki/pvc.yaml
kubectl apply -f manifests/monitoring/loki/configmap.yaml
kubectl apply -f manifests/monitoring/loki/deployment.yaml
kubectl apply -f manifests/monitoring/loki/service.yaml
```

## Перевірка

```bash
kubectl -n monitoring get pods -l app=loki
kubectl -n monitoring get svc loki
kubectl -n monitoring logs -l app=loki --tail=20
```

## Permission denied у tsdb-shipper-cache (CrashLoopBackOff)

Якщо Loki падає з помилкою **permission denied** на `/loki/tsdb-shipper-cache/...`, файли на томі мають неправильного власника (наприклад root). Виправлення:

1. Запустити одноразовий Job, який змінить власника всього в `/loki` на UID 10001:
   ```bash
   kubectl apply -f manifests/monitoring/loki/job-fix-permissions.yaml
   kubectl -n monitoring get jobs
   kubectl -n monitoring logs job/loki-fix-permissions -f
   ```
2. Після успішного завершення Job (COMPLETIONS 1/1) перезапустити под Loki:
   ```bash
   kubectl -n monitoring delete pod -l app=loki
   ```
3. Перевірити: `kubectl -n monitoring get pods -l app=loki` — под має перейти в Running.

**Логи в Grafana:** datasource **Loki** додано в `configmap-datasources.yaml` (URL: `http://loki:3100`). Після застосування ConfigMap перезапустіть Grafana, щоб підхопити новий datasource.

Як переглядати логи:
1. Відкрийте **Explore** (іконка компаса зліва) → виберіть datasource **Loki**.
2. **Режим Code (рекомендовано):** натисніть **Code** праворуч у панелі запиту й уведіть LogQL у полі, наприклад:
   - `{namespace="monitoring"}` — логи з namespace monitoring
   - `{namespace="kube-system"}` — системні логи
   - `{app="loki"}` — логи самого Loki
   - `{pod=~"prometheus.+"}` — логи подів, ім’я яких містить prometheus (у LogQL потрібен хоча б один непорожній матчер, тому краще `.+` замість `.*`).
3. **Режим Builder:** у блоці **Label filters** оберіть **Select label** → `namespace`, **Select value** → `monitoring`. Не вводьте `{namespace="monitoring"}` у поле **Line contains** — це фільтр по тексту рядка, а не по мітці; порожній селектор `{}` викликає помилку.
4. Натисніть **Run query**. Для потокових логів увімкніть **Live** (якщо підтримується).

**Якщо показує «No logs found»:** Loki сам логів не збирає. Щоб у Explore з’явилися логи подів і нод, потрібно розгорнути **Promtail** (DaemonSet), який читає логи з нод і відправляє їх у Loki. План і кроки — у `manifests/logging/LOGGING_PLAN.md` (Фаза 3: Promtail).

## Якщо PVC лишається Pending після створення PV

При `volumeBindingMode: WaitForFirstConsumer` PVC прив’язується до PV, коли под, який його використовує, планується на ноду. Після того як PV з’явився, перезапустіть под Loki — scheduler і volume binder знову спробують прив’язати PVC і запланувати под:

```bash
kubectl -n monitoring delete pod -l app=loki
```

Потім перевірте: `kubectl get pv pv-loki-10gi` (STATUS має бути Bound), `kubectl -n monitoring get pvc loki-data`, `kubectl -n monitoring get pods -l app=loki`.
