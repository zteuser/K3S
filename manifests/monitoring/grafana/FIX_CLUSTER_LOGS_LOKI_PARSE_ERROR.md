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

3. **Якщо помилка лишилась** (наприклад, дашборд змінювали вручну):
   - Відкрийте **Dashboard settings** (іконка шестерні) → **Variables**.
   - Виберіть змінну **Severity**.
   - Для опції **All** у полі значення має бути саме: ` | line_format "{{__line__}}"` (пробіл на початку, **два** підкреслення в `__line__`). Якщо там порожньо, текст «All» або `_line_` з одним підкресленням — виправте на ` | line_format "{{__line__}}"` і збережіть дашборд.
   - Для опцій debug/info/warn/error значення мають містити pipeline з regex, що підтримує і JSON, і logfmt (як у поточній версії дашборду в репо).

Після цього запит у панелі логів має бути валідним, попередження зникне, а фільтр по severity працюватиме і для JSON, і для logfmt-логів.
