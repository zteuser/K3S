# Виправлення «parse error» та некоректного Severity на дашборді Cluster Logs (Loki)

## Симптоми

- Дашборд **Cluster Logs (Loki)** показує **No data** або червоне попередження на панелі «Logs (content)».
- У **Inspect → Error**: `Status: 500. Message: parse error at line 1, col 73: syntax error: unexpected IDENTIFIER`.
- Фільтр **Severity** не показує логи при виборі debug/info/warn/error (логи в форматі logfmt не підходили під старий regex).

Причини: (1) у ConfigMap для опції **All** було подвійне екранування лапок (`\\\"{{__line__}}\\\"`), через що в запит потрапляли літеральні `\"` і Loki повертав parse error; (2) regex для severity враховував лише JSON `"level":"..."`, а не logfmt `level=info`.

## Що зроблено в репо

- **Severity = All:** значення задано як no-op pipeline ` | line_format "{{__line__}}"` (подвійне підкреслення `__line__`). У **ConfigMap** виправлено екранування: у вбудованому JSON використовується `\"`, а не `\\\"`, щоб підставлялось коректне LogQL. У запиті панелі використовується **${severity_pipeline:raw}**, щоб Grafana не екранувала та не інтерполювала вміст змінної (наприклад `{{ }}`).
- **Severity = debug/info/warn/error:** використовується один regex, який підтримує і **JSON** (`"level":"info"`), і **logfmt** (`level=info`):  
  `(?:level=|\"level\"\s*:\s*\")(?P<level>debug|info|warn|error)`.

## Що зробити у вас

1. **Застосувати оновлений дашборд із репо**
   ```bash
   kubectl apply -f manifests/monitoring/grafana/configmap-dashboards.yaml
   kubectl -n monitoring rollout restart deployment/grafana
   ```
   Після перезапуску Grafana підхопить оновлений ConfigMap.

2. **Перезавантажити дашборд з provisioning (якщо в UI досі `_line_` або No data)**  
   Якщо дашборд колись зберігали вручну, у БД може лишитись стара версія. Щоб підхопити актуальний JSON з ConfigMap:
   - Відкрийте **Dashboards** → папка (наприклад SNMP) → **Cluster Logs (Loki)**.
   - Якщо зверху є кнопка **Discard changes** / **Revert** — натисніть її, щоб повернути версію з файлу.
   - Або **Dashboard settings** (шестерня) → **Versions** → виберіть останню **provisioned** версію і **Restore**.
   - Якщо дашборд у списку має іконку замка (read-only) — це версія з ConfigMap; після рестарту пода вона має оновитись. Перезавантажте сторінку (F5) або зайдіть у дашборд заново зі списку.

3. **Швидке виправлення в UI (коли в Variables видно `_line_` або Inspect показує parse error at col 73)**  
   Це означає, що в дашборді збережена версія з **одним** підкресленням (`_line_`). Loki очікує **два** (`__line__`).
   - Відкрийте **Dashboard settings** (шестерня) → **Variables** → змінна **severity_pipeline**.
   - У блоці **Custom options** у полі «Values separated by comma» знайдіть `line_format "{{_line_}}"` і замініть на `line_format "{{__line__}}"` (два підкреслення перед і після `line`).
   - Збережіть дашборд (**Save dashboard**). Після цього панель «Logs (content)» має перестати показувати помилку.

4. **Якщо помилка лишилась** (наприклад, після збереження зміни зникли):
   - Переконайтесь, що дашборд завантажується з provisioning: закрийте дашборд, знову відкрийте **Dashboards** → **SNMP** → **Cluster Logs (Loki)** (без збережених змін).
   - Або в **Variables** для опції **All** вручну вставте повне значення: ` | line_format "{{__line__}}"` (пробіл на початку, **два** підкреслення в `__line__`), збережіть.
   - Щоб побачити, який запит реально йде в Loki: на панелі «Logs (content)» відкрийте **Inspect** → вкладка **Query** / **Data** — там буде повний LogQL; якщо в ньому `_line_` або зайві лапки/backslash — виправте значення змінної відповідно.

Після цього запит у панелі логів має бути валідним, попередження зникне, а фільтр по severity працюватиме і для JSON, і для logfmt-логів.
