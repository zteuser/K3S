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

## "Error querying loki" / "context canceled" у логах Grafana

Якщо в логах подів Grafana з’являються `level=error`, `msg="Error querying loki"` або `"Error received from Loki"` з причиною **context canceled** — це зазвичай не означає поломку Loki.

**Типові причини:**
- Користувач закрив панель або перейшов на інший дашборд до завершення запиту (Grafana скасовує контекст).
- Таймаут запиту: великий діапазон часу або `limit=1000` при повільному Loki призводять до таймауту, після чого контекст скасовується.

**Що зробити:** у datasource Loki (ConfigMap `grafana-datasources`, файл `loki.yaml`) додано `jsonData.timeout: 120` (секунд), щоб важкі запити мали більше часу. Після зміни конфігу: `kubectl apply -f manifests/monitoring/grafana/configmap-datasources.yaml` і `kubectl rollout restart deployment grafana -n monitoring`. Якщо помилки лише при переході між сторінками — їх можна ігнорувати.

## 502 Bad Gateway / connection refused у Grafana (Cluster Logs, Explore → Loki)

Якщо дашборд **Cluster Logs (Loki)** або **Explore → Loki** показує **502** і в помилці: `dial tcp ...:3100: connect: connection refused` — Grafana не може підключитися до Loki. Зазвичай це означає, що **под Loki не працює** або ще не слухає на порту 3100.

1. **Статус пода і endpoints:**
   ```bash
   kubectl -n monitoring get pods -l app=loki
   kubectl -n monitoring get endpoints loki
   ```
   - Под має бути **Running** і **Ready 1/1**. Якщо **Pending** — див. розділ «Якщо PVC лишається Pending» нижче.
   - Якщо под у **CrashLoopBackOff** або **Error** — див. логи: `kubectl -n monitoring logs -l app=loki --tail=50`. Часті причини: **permission denied** на томі (див. «Permission denied у tsdb-shipper-cache» нижче), помилка в конфігу, недостатньо пам’яті.
   - **Endpoints** для `loki` мають містити хоча б одну адресу (IP пода). Якщо endpoints порожні — под не Ready, Grafana отримує connection refused.

2. **Після виправлення** (под Running, endpoints не порожні) оновіть дашборд у Grafana або повторіть запит у Explore.

## Permission denied у tsdb-shipper-cache

Якщо в Grafana при запиті до Loki з’являється **"mkdir /loki/tsdb-shipper-cache/... permission denied"** або под Loki падає з такою ж помилкою — на томі неправильні права (наприклад root). Спочатку перезапустіть под, щоб init-контейнер знову виконав `chown`/`chmod`:

```bash
kubectl -n monitoring delete pod -l app=loki
```

Дочекайтеся нового Running-пода, потім повторите запит у Grafana. Якщо помилка лишається — виконайте кроки нижче (Job для примусового chown).

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
