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

## Помилка «Datasource … was not found» (UID P8E80F9AEF21F6940 або інший)

Якщо панелі показують **0** / **No data**, а в **Inspect → Error** з’являється **«Datasource P8E80F9AEF21F6940 was not found»** (або інший UID) — дашборд імпортовано з посиланням на датасорси автора шаблону (їх UID у вашій Grafana немає).

**Що зробити (обов’язково збережіть дашборд):**

1. Відкрийте дашборд **Promtail Monitoring - Metrics and Logs**.
2. Натисніть **Dashboard settings** (іконка шестерні зверху справа) → вкладка **Variables**.
3. У списку змінних знайдіть змінну з попередженням (жовтий трикутник) і натисніть на неї:
   - **`datasource`** (Label: Datasource Loki): у блоці **Data source options** поле **Instance name filter** за замовчуванням заповнене regex на кшталт `/.*-(.*)-.*/` — він відфільтровує лише назви з двома дефісами, тому ваш датасорс **Loki** не потрапляє в список. **Очистіть це поле** (залиште порожнім), збережіть змінну — у списку з’явиться **Loki**; виберіть його як значення і знову збережіть змінну.
   - **`datasourceProm`** (Label: Datasource Prometheus): те саме — **очистіть Instance name filter** (залиште порожнім), збережіть змінну, виберіть **Prometheus** і збережіть.
   Інші назви в інших версіях шаблону: «Datasource Loki» / «Datasource Prometheus» — суть та сама.
4. Натисніть **Save dashboard** (синя кнопка зверху). Без збереження після оновлення сторінки попередження й помилки повернуться.

Після збереження попередження біля `datasource` і `datasourceProm` мають зникнути, панелі — показувати дані. У фільтрах дашборду виберіть **Label Value** = **promtail** для логових панелей.

**Якщо після очищення Instance name filter прев’ю показує «No data sources found»:** переконайтеся, що в **Connections → Data sources** є датасорс **Loki** (Type: Loki). Якщо його немає — застосуйте provisioning і перезапустіть Grafana: `kubectl apply -f manifests/monitoring/grafana/configmap-datasources.yaml`, `kubectl -n monitoring rollout restart deployment/grafana`. Якщо Loki є в списку датасорсів — натисніть **Apply** у формі змінної, потім **Save dashboard**; іноді прев’ю оновлюється після збереження. Можна також вийти з облікового запису і увійти знову, потім повторити вибір датасорсу в змінній.

## Помилка LogQL: «unexpected <op:->» / «unexpected character inside braces»

Якщо панелі (наприклад **Promtail Log Lines**, **Promtail Recent Logs**, **Error Requests and Logs Count - Overtime**) показують **0**, **No data** і червону іконку, а в **Inspect → Error** з’являється одна з помилок:
- `parse error: unexpected <op:-> in label matching, expected identifier or "}"`
- `parse error: unexpected character inside braces: ''` (порожній символ)
- `parse error: unexpected character inside braces: '!'`
- `parse error: unexpected character inside braces: ':'`

— у запит потрапляє некоректне значення змінної (**Label Name**, **Label Value** або **Instance**): порожнє, «None», `-`, або некоректний символ. У LogQL у **селекторі** (всередині `{ }`) **ім’я лейбла** (ліворуч від `=`) має бути **ідентифікатором** (наприклад `job`, `instance`), а не regex — тому значення **`.+`** для **Label Name** дає помилку (наприклад `unexpected character inside braces: ':'`).

**Швидке виправлення:**

1. **Job** = `promtail`.
2. **Instance** — можна ввести **`.+`** у "Enter variable value" (у запиті це потрапляє в `instance=~".+"`, regex допустимий).
3. **Label Name** і **Label Value** — **не** використовуйте `.+` для Label Name. Виберіть **конкретні значення**: наприклад **Label Name** = `job`, **Label Value** = `promtail` (дублює фільтр Job, але дає валідний запит). Якщо в списку є лише "None", спробуйте вручну ввести для Label Name — `job`, для Label Value — `promtail`.

**Детальніше:**

1. У фільтрах дашборду зверху перевірте змінні **Label Name**, **Label Value**, **Instance**.
2. **Label Name** має бути **ідентифікатором** (наприклад `job`, `instance`), а не regex. **Label Value** — конкретне значення або regex лише якщо шаблон запиту використовує його праворуч від `=~`.
3. Для **Instance** — одна з нод зі списку або regex **`.+`** у "Enter variable value" (для `instance=~".+"`).
4. Якщо опції порожні або «None» — у **Dashboard settings → Variables** для **Instance** встановіть **Custom all value** **`.+`**; для **Label Name** / **Label Value** не використовуйте regex як ім’я лейбла, краще задати фіксовані значення за замовчуванням (наприклад `job`, `promtail`).
5. Збережіть дашборд і оновіть сторінку.

Після цього запити до Loki не повинні містити невалідний символ у селекторі, і помилка парсингу зникне.

## Explore → Loki: «No logs found» для `{job="promtail"}`

Якщо **Prometheus** бачить Promtail (метрики є, дашборд показує Version / Current Sent Bytes), але в **Explore → Loki** запит `{job="promtail"}` повертає **No logs found** — логи з job=promtail не потрапляють у Loki.

**Кроки перевірки:**

1. **Чи взагалі є логи в Loki**  
   У Explore виконайте `{job=~"kubernetes-pods|journal"}` за **Last 1 hour**. Якщо є рядки — Promtail пушить у Loki, проблема лише в job **promtail**. Якщо нічого немає — перевірте доступ Promtail до Loki (URL `http://loki:3100`, логи пода Promtail на помилки push).

2. **Перезапустити Promtail**  
   Щоб перечитати позиції і знову відправити хвости логів:
   ```bash
   kubectl -n monitoring delete pod -l app=promtail
   ```
   Дочекайтеся 1–2 хв, потім знову запит `{job="promtail"}` за Last 15 minutes.

3. **Чи на нодах є файли логів Promtail**  
   На будь-якій ноді, де крутиться под Promtail, виконайте (шлях може відрізнятися на k3s):
   ```bash
   ls /var/log/pods/ | grep -i promtail
   ls /var/log/pods/monitoring_promtail-*/*/ 2>/dev/null   # піддиректорія = ім'я контейнера (promtail)
   ```
   Має з’явитися каталог типу `monitoring_promtail-<suffix>_<uid>/promtail/` з файлами `*.log`. Якщо каталогів подів немає — kubelet пише логи в інше місце; тоді в `promtail/configmap.yaml` у job `promtail` підправте `__path__` під фактичний шлях на ноді.

4. **Чи job «promtail» має активні targets у Promtail**  
   Promtail у цьому репо — **DaemonSet**. Образ Promtail зазвичай не містить `wget`/`curl`, тому надійний спосіб — порт-форвард і браузер:
   ```bash
   kubectl port-forward -n monitoring svc/promtail 9080:9080
   ```
   У браузері відкрийте **http://localhost:9080/targets**. Знайдіть job **promtail** і переконайтеся, що є targets у стані **Ready** / **up**; якщо всі **down** або job відсутній — перевірте path на ноді (крок 3). (Порт-форвард можна зупинити через Ctrl+C.)

   **Якщо в Targets показано promtail (0/0 ready) і kubernetes-pods (0/0 ready):** service discovery не бачить подів через Kubernetes API. Часто це буває на **воркер-нодах**, де немає маршруту до API (наприклад 10.43.0.1). Порт-форвард на `svc/promtail` відкриває випадковий под — якщо це под на воркері, він може мати 0 targets. Перевірте **конкретно под на ноді з доступом до API** (наприклад master-node):
   ```bash
   kubectl port-forward -n monitoring pod/$(kubectl -n monitoring get pods -l app=promtail --field-selector spec.nodeName=master-node -o jsonpath='{.items[0].metadata.name}') 9080:9080
   ```
   Відкрийте http://localhost:9080/targets — якщо там з’являться targets для promtail/kubernetes-pods, причина в мережі воркер → API. Рішення: налаштувати маршрути/файрвол так, щоб усі ноди могли досягти API, або в `promtail/daemonset.yaml` увімкнути `nodeSelector: kubernetes.io/hostname: master-node` (тоді логи збиратимуться лише з однієї ноди). Також перевірте логи пода: `kubectl -n monitoring logs -l app=promtail --tail=30` — шукайте помилки на кшталт `connection refused`, `no route to host` до API. Якщо й на master-node в Targets 0/0 — перевірте RBAC: `kubectl auth can-i list pods --as=system:serviceaccount:monitoring:promtail -n monitoring` (має бути `yes`) і логи того ж пода (шукайте помилки стосовно API). Якщо RBAC у порядку і в логах немає помилок API — у тому ж порт-форварді відкрийте вкладку **Service Discovery**: там мають з’являтися поди до relabel; якщо список порожній, discovery не повертає подів; якщо поди є, а в Targets 0/0 — relabel_configs (наприклад формула `__path__`) відкидають усі targets (перевірте формат шляху на ноді та змінні `__meta_kubernetes_*`). Якщо після додавання `namespaces.names` у конфіг discovery все ще 0/0 — перевірте доступ под→API: запустіть тимчасовий под з SA promtail і виклик API (див. нижче).

5. **Логи пода Promtail**  
   Переконайтеся, що немає помилок при push до Loki:
   ```bash
   kubectl -n monitoring logs -l app=promtail --tail=50
   ```
   Шукайте рядки на кшталт `error pushing`, `connection refused`, `context deadline exceeded` до `loki:3100`.

Після виправлення (перезапуск, виправлений path або мережа до Loki) запит `{job="promtail"}` у Explore і панелі дашборду 20881 мають показати логи.

### Перевірка доступу под→Kubernetes API (коли discovery 0/0)

Якщо Service Discovery і Targets показують 0/0 для kubernetes-pods і promtail навіть після явного `namespaces.names` у конфігу — перевірте, чи под у namespace monitoring може викликати API під ServiceAccount `promtail`:

```bash
kubectl run -it --rm debug-api --image=curlimages/curl --restart=Never -n monitoring --overrides='{"spec":{"serviceAccountName":"promtail"}}' -- sh -c 'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); curl -sS -H "Authorization: Bearer $TOKEN" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt https://kubernetes.default.svc/api/v1/namespaces/monitoring/pods | head -c 600'
```

Якщо в виводі з’явиться JSON з `"kind":"PodList"` і списком подів — API з подів доступний, причина 0/0 у Promtail (перевірено: 2.9.3 і 3.0.0, hostNetwork — без зміни). У конфіг додано **workaround** — job **promtail-static** (static_config з glob `/var/log/pods/monitoring_promtail-*_*/promtail/*.log` та `instance: ${NODE_NAME}`), щоб логи Promtail потрапляли в Loki з `job=promtail` для дашборду 20881 без discovery. Якщо помилка (`Connection refused`, `timed out`, `403 Forbidden`) — причина в мережі або політиках доступу под→API.

## Якщо все ще «No data»

Якщо змінні виставлено коректно (Label Name=job, Label Value=promtail, Instance=.+), parse error зник, але панелі логів (DEBUG/INFO/WARN/ERROR, Promtail Log Lines, Promtail Recent Logs) показують **0** або **No data** — у Loki немає логів з `job="promtail"`. У такому разі див. розділ **«Explore → Loki: No logs found для job=promtail»** вище. Зверніть увагу на панель **Active Files** на дашборді: якщо там **0** по всіх інстансах — Promtail не читає жодного файлу для job `promtail` (немає активних targets); допоможе перевірка **/targets** (крок 4 у тому розділі) та path логів на нодах (крок 3).

- Перевірте, що поди Promtail слухають 9080: `kubectl -n monitoring get pods -l app=promtail -o wide` і що Service існує: `kubectl -n monitoring get svc promtail`.
- У Prometheus перевірте, що конфіг завантажився: **Status → Configuration** — має бути job `promtail` з `kubernetes_sd_configs` (role: endpoints).
- У Loki перевірте запит `{job="promtail"}` за останні 15 хвилин; якщо логів немає — див. розділ «Explore → Loki: No logs found для job=promtail» вище.
