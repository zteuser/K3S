# Міграція з Promtail на Grafana Alloy для логів (Loki)

## Чи можна замінити Promtail на Alloy?

**Так.** Grafana Alloy — рекомендована заміна Promtail для збору логів у Loki. Promtail досягне **End of Life 2 березня 2026**. Alloy — єдиний агент для metrics, logs, traces і profiles (на базі OpenTelemetry Collector).

## Для початку міграції: чи потрібно інсталювати Alloy?

**У кластері — ще ні.** Для першого кроку (конвертація конфігу Promtail → Alloy) достатньо мати **CLI Alloy** на своїй машині (або в Docker). Після того як отримаєте файл `.alloy`, можна додати манифести й розгорнути Alloy у Kubernetes.

### Як отримати Alloy CLI (для команди `alloy convert`)

- **Бінарник (рекомендовано):** [Releases · grafana/alloy](https://github.com/grafana/alloy/releases) — завантажити архів під вашу ОС (Linux/macOS/Windows), розпакувати й викликати `alloy convert ...`.
- **Docker:** якщо не хочете ставити бінарник локально:
  ```bash
  docker run --rm -v "$(pwd):/cfg" grafana/alloy:latest convert --source-format=promtail --output=/cfg/alloy.alloy /cfg/promtail.yaml
  ```
  (файл `promtail.yaml` має лежати в поточній директорії.)

Після конвертації Alloy **інсталюється в кластер** лише коли додаєте DaemonSet і застосовуєте манифести — це вже крок 3 міграції.

## Що дає міграція

- Один агент замість окремого Promtail (потім можна об’єднати з Grafana Agent для метрик, якщо використовується).
- Офіційна підтримка та розвиток з боку Grafana.
- Конвертація конфігу: **Alloy вміє перетворювати конфіг Promtail у свій формат** однією командою.

## Кроки міграції (коротко)

### 1. Конвертувати конфіг Promtail → Alloy

На машині з встановленим Alloy (або Docker):

```bash
# Приклад: конвертувати поточний promtail.yaml у Alloy-формат
alloy convert --source-format=promtail --output=alloy-config.alloy manifests/monitoring/promtail/configmap.yaml
```

Конфіг у репо зберігається всередині ConfigMap у ключі `promtail.yaml`. Потрібно спочатку витягнути YAML у окремий файл (або передати вміст). Приклад для локального файлу `promtail.yaml`:

```bash
alloy convert --source-format=promtail --output=alloy.alloy promtail.yaml
```

Отриманий `.alloy` — це конфіг у форматі Alloy (компоненти `loki.source.kubernetes`, `loki.source.file`, `loki.write` тощо).

### 2. Особливості нашого Promtail-конфігу

Поточний конфіг у `promtail/configmap.yaml` містить:

- **kubernetes_pods** — Kubernetes service discovery (поди), `relabel_configs`, шляхи `/var/log/pods/...`
- **promtail** — окремий job для логів самого Promtail (Kubernetes discovery + fallback)
- **promtail-static** — workaround з `static_configs` і `__path__: /var/log/pods/monitoring_promtail-*_*/promtail/*.log`, змінна середовища `NODE_NAME`
- **journal** — логи systemd journal з `/var/log/journal`

Після `alloy convert` треба перевірити:

- Чи є в Alloy еквівалент **Kubernetes discovery** для подів (компонент типу `discovery.kubernetes` + `loki.source.kubernetes` або `loki.source.file` з `local.file_match`). Якщо конвертер згенерує лише `local.file_match` з статичними шляхами — потрібно додати/підставити динамічні шляхи для подів і journal.
- **Journal**: в Alloy є `loki.source.journal` — варто перевірити, чи конвертер його використав, чи потрібно дописати вручну.
- **Змінна середовища** `NODE_NAME` (для promtail-static): у Alloy-конфігу можна використовувати змінні середовища через синтаксис Alloy (наприклад, атрибути з env).

### 3. Деployment у Kubernetes

- Замість DaemonSet Promtail — розгорнути **DaemonSet Alloy** з образом `grafana/alloy` (актуальний тег з [Docker Hub](https://hub.docker.com/r/grafana/alloy/tags)).
- Ті самі volumeMounts: `/var/log`, `/var/run/promtail` (або аналог для positions), `/etc/machine-id` для journal; ConfigMap з конвертованим `.alloy` конфігом.
- Той самий **ServiceAccount** і RBAC (ClusterRole/ClusterRoleBinding) можна перевикористати або взяти [офіційний приклад Alloy для Kubernetes](https://grafana.com/docs/alloy/latest/set-up/install-alloy/install-alloy-kubernetes/).
- Сервіс (Service) для метрик/здоров’я — порт Alloy за замовчуванням інший (наприклад 12345); якщо дашборди/алерти дивляться на Promtail-metrics на 9080, їх треба оновити (див. нижче).

### 4. Метрики та дашборди

- **Метрики Alloy відрізняються від метрик Promtail.** Якщо є алерти або дашборди (наприклад, Promtail Monitoring 20881), що покладаються на метрики Promtail (наприклад `promtail_*`), їх потрібно оновити під метрики Alloy або тимчасово зберегти старі запити, якщо Alloy в режимі сумісності щось емітить.
- Перевірити дашборд **Cluster Logs (Loki)**: він фільтрує по `job=~"kubernetes-pods|journal"`. Після міграції потрібно зберегти ті самі значення `job` у лейблах, щоб запити в Loki залишились валідними.

### 5. Ресурси в репо

| Зараз (Promtail)              | Після міграції (Alloy)     |
|------------------------------|----------------------------|
| `promtail/configmap.yaml`    | `alloy/configmap.yaml` з `.alloy` |
| `promtail/daemonset.yaml`    | `alloy/daemonset.yaml` (образ Alloy) |
| `promtail/service.yaml`      | `alloy/service.yaml` (порти Alloy) |
| `promtail/clusterrole*.yaml` | аналог для Alloy (або офіційний маніфест) |
| `promtail/README.md`         | `alloy/README.md`           |

У `kustomization.yaml` замість ресурсів `promtail/*` підключити ресурси `alloy/*` після їх додавання.

### Конвертований конфіг у репо

У **`manifests/monitoring/alloy/alloy.alloy`** збережено результат `alloy convert` з ручними виправленнями для Kubernetes:

- **Discovery по ноді:** у `discovery.kubernetes` для обмеження подів поточним вузлом використовується `sys.env("NODE_NAME")` (fallback — `HOSTNAME`, потім `constants.hostname`). У DaemonSet Alloy потрібно задати змінну середовища `NODE_NAME` з `valueFrom.fieldRef.fieldPath: spec.nodeName`.
- **promtail_static:** замість літерального `"${NODE_NAME}"` (який Alloy не підставляє) використано `instance = sys.env("NODE_NAME")`.

## Корисні посилання

- [Migrate from Promtail to Grafana Alloy](https://grafana.com/docs/alloy/latest/set-up/migrate/from-promtail/)
- [Install Alloy on Kubernetes](https://grafana.com/docs/alloy/latest/set-up/install-alloy/install-alloy-kubernetes/)
- [Alloy components (loki.source.*, loki.write)](https://grafana.com/docs/alloy/latest/reference/components/)

## Рекомендація

Міграція **можлива і доцільна** до EOL Promtail. Найменш ризикований варіант:

1. Згенерувати Alloy-конфіг командою `alloy convert`.
2. Розгорнути Alloy DaemonSet поруч із Promtail (інший namespace або інші лейбли), перевірити, що логи з’являються в Loki з очікуваними лейблами.
3. Оновити дашборди/алерти під метрики Alloy (якщо використовуються).
4. Вимкнути Promtail (прибрати з kustomization або масштабувати до 0) і залишити лише Alloy.

Якщо потрібно, можна окремо підготувати макети маніфестів Alloy (ConfigMap + DaemonSet + RBAC) під поточний конфіг Promtail у репо.
