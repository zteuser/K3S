# Помилка «Data source not found» для Loki в Grafana

## Симптоми

- У **Explore** при виборі Loki і запиті з’являється **Query error: Data source not found**.
- Дашборд **Cluster Logs (Loki)** показує **No data** на панелі логів, навіть при запиті `{job=~"kubernetes-pods|journal"}`.
- На сторінці **Connections → Data sources → Loki** датасорс відкривається (URL `http://loki:3100`), але запити з панелей/Explore не знаходять його.

Причина: посилання на датасорс (UID) у змінних дашборду або в кеші Explore не збігається з UID фактичного датасорсу Loki в Grafana.

## Що перевірити

1. **Скільки датасорсів Loki є в системі**  
   **Connections → Data sources** — переконайтеся, що є **один** датасорс з іменем **Loki**. Якщо їх два (наприклад, один з provisioning, один створений вручну), видаліть зайвий або той, у якого інший UID.

2. **UID датасорсу Loki**  
   На сторінці редагування Loki (де вказано URL `http://loki:3100`) перевірте **UID**:
   - у деяких версіях Grafana UID видно внизу сторінки або в розділі налаштувань;
   - або через API (замініть `admin:password` і `monitoring.lan` на свої):
     ```bash
     curl -s -u admin:YOUR_PASSWORD "http://monitoring.lan/api/datasources" | jq '.[] | select(.type=="loki") | {name, uid, id}'
     ```
   Очікується один запис з **uid: "loki"**. Якщо uid інший (наприклад, довий рядок), дашборди з `DS_LOKI = loki` його не знайдуть.

## Рішення

### Варіант 1: Provisioning (рекомендовано)

Щоб у Grafana був один Loki з **uid: loki** з нашого конфігу:

1. Застосуйте ConfigMap датасорсів і перезапустіть Grafana:
   ```bash
   kubectl apply -f manifests/monitoring/grafana/configmap-datasources.yaml
   kubectl -n monitoring rollout restart deployment/grafana
   ```

2. Дочекайтеся готовності пода:
   ```bash
   kubectl -n monitoring rollout status deployment/grafana
   ```

3. У браузері відкрийте **Connections → Data sources**. Має бути один **Loki** з URL `http://loki:3100`. Натисніть **Save & test** — має бути «Data source is working».

4. У **Explore** виберіть датасорс **Loki** і виконайте запит `{job=~"kubernetes-pods|journal"}` — помилка «Data source not found» має зникнути.

5. На дашборді **Cluster Logs (Loki)** у фільтрі **Datasource** виберіть **Loki** і збережіть дашборд. Панель логів має почати показувати дані (якщо в Loki вони є).

### Варіант 2: Якщо Loki створений вручну з іншим UID

Якщо після кроків вище у вас лишається один Loki, але з **іншим UID** (не `loki`):

1. На дашборді **Cluster Logs (Loki)**: **Dashboard settings** (шестерня) → **Variables** → **DS_LOKI** → у полі **Current** виберіть ваш датасорс **Loki** (за назвою). Збережіть дашборд.

2. У **Explore** знову виберіть **Loki** з випадаючого списку датасорсів і запустіть запит.

Якщо після цього все одно «Data source not found», перезавантажте сторінку Grafana (Ctrl+F5) або вийдіть із облікового запису та увійдіть знову — іноді кеш вибору датасорсу зберігає старий UID.

## Підсумок

| Крок | Дія |
|------|-----|
| 1 | `kubectl apply -f manifests/monitoring/grafana/configmap-datasources.yaml` |
| 2 | `kubectl -n monitoring rollout restart deployment/grafana` |
| 3 | Connections → Data sources → Loki → Save & test |
| 4 | Explore → вибрати Loki → запит `{job=~"kubernetes-pods|journal"}` |
| 5 | Cluster Logs: вибрати Datasource = Loki, зберегти дашборд |

Після цього посилання на Loki (uid `loki` з provisioning) і змінна `${DS_LOKI}` на дашборді будуть вказувати на один і той самий датасорс, і помилка «Data source not found» має зникнути.
