# Виправлення «parse error» та некоректного Severity на дашборді Cluster Logs (Loki)

## Симптоми

- Дашборд **Cluster Logs (Loki)** показує **No data** або червоне попередження на панелі «Logs (content)».
- У **Inspect → Error**: `Status: 500. Message: parse error at line 1, col 73: syntax error: unexpected IDENTIFIER`.
- Фільтр **Severity** не показує логи при виборі debug/info/warn/error (логи в форматі logfmt не підходили під старий regex).

Причини: (1) у ConfigMap для опції **All** було подвійне екранування лапок (`\\\"{{__line__}}\\\"`), через що в запит потрапляли літеральні `\"` і Loki повертав parse error; (2) regex для severity враховував лише JSON `"level":"..."`, а не logfmt `level=info`.

## Що зроблено в репо

- **Severity = All:** значення задано як no-op pipeline ` | line_format "{{__line__}}"` (подвійне підкреслення `__line__`). У **ConfigMap** виправлено екранування: у вбудованому JSON використовується `\"`, а не `\\\"`, щоб підставлялось коректне LogQL.
- **Severity = debug/info/warn/error:** використовується один regex, який підтримує і **JSON** (`"level":"info"`), і **logfmt** (`level=info`):  
  `(?:level=|\"level\"\s*:\s*\")(?P<level>debug|info|warn|error)`.

## Що зробити у вас

1. **Застосувати оновлений дашборд із репо**
   ```bash
   kubectl apply -f manifests/monitoring/grafana/configmap-dashboards.yaml
   kubectl -n monitoring rollout restart deployment/grafana
   ```
   Після перезапуску Grafana підхопить оновлений ConfigMap; дашборд Cluster Logs (Loki) буде з правильним значенням для Severity «All».

2. **Якщо помилка лишилась** (наприклад, дашборд змінювали вручну):
   - Відкрийте **Dashboard settings** (іконка шестерні) → **Variables**.
   - Виберіть змінну **Severity**.
   - Для опції **All** у полі значення має бути саме: ` | line_format "{{__line__}}"` (пробіл на початку, **два** підкреслення в `__line__`). Якщо там порожньо, текст «All» або `_line_` з одним підкресленням — виправте на ` | line_format "{{__line__}}"` і збережіть дашборд.
   - Для опцій debug/info/warn/error значення мають містити pipeline з regex, що підтримує і JSON, і logfmt (як у поточній версії дашборду в репо).

Після цього запит у панелі логів має бути валідним, попередження зникне, а фільтр по severity працюватиме і для JSON, і для logfmt-логів.
