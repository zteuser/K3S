# Як оновити ConfigMap через Portainer UI

## Покрокова інструкція

### Крок 1: Відкрийте ConfigMap в Portainer

1. Перейдіть до **Kubernetes** → **Applications** → **monitoring**
2. Знайдіть **ConfigMap** в списку ресурсів
3. Натисніть на **prometheus-config**
4. Переконайтеся, що вибрана вкладка **"ConfigMap"** (не "Events" або "YAML")

### Крок 2: Підготуйте новий вміст

1. Відкрийте файл `k3s/manifests/monitoring/prometheus/configmap.yaml`
2. Знайдіть секцію `data:` → `prometheus.yml: |`
3. Скопіюйте **весь вміст** після `prometheus.yml: |` (всі рядки з відступами)

**Важливо:** Скопіюйте весь YAML вміст, включаючи:
- `global:`
- `scrape_configs:`
- Всі jobs (prometheus, kubernetes-apiservers, node-exporter, cadvisor, kube-state-metrics, snmp-routers)

### Крок 3: Оновіть поле Value в Portainer

1. В секції **"Data"** знайдіть поле **"Value"** (велике текстове поле)
2. **Виділіть весь поточний вміст** в полі Value (Ctrl+A або Cmd+A)
3. **Вставте** скопійований новий вміст (Ctrl+V або Cmd+V)

**Перевірте:**
- Вміст починається з `global:`
- Вміст містить всі jobs, включаючи `snmp-routers`
- Відступи збережені (YAML чутливий до відступів)

### Крок 4: Перевірте Summary

В секції **"Summary"** має бути написано:
- "Portainer will execute the following Kubernetes actions."
- "Update the ConfigMap named prometheus-config"

### Крок 5: Збережіть зміни

1. Прокрутіть сторінку вниз до секції **"Actions"**
2. Натисніть кнопку **"Update ConfigMap"** (темно-сіра кнопка)

### Крок 6: Перевірте результат

1. Після оновлення ви побачите повідомлення про успіх
2. Перевірте, що вміст оновився:
   - Відкрийте ConfigMap знову
   - Перевірте, що в полі Value є новий вміст з `snmp-routers` job

### Крок 7: Перезапустіть Prometheus

Після оновлення ConfigMap потрібно перезапустити Prometheus, щоб він завантажив нову конфігурацію:

**Через Portainer (рекомендовано):**
1. Kubernetes → Applications → monitoring
2. Знайдіть **Deployment** → **prometheus**
3. Натисніть **Restart** (або три крапки → Restart)

**Або через kubectl (якщо налаштований):**
```bash
# Спочатку налаштуйте kubectl для k3s:
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Потім перезапустіть:
kubectl delete pods -n monitoring -l app=prometheus
```

**Якщо kubectl не працює:**
- Використовуйте Portainer UI для перезапуску
- Або налаштуйте kubectl (див. `FIX_KUBECTL_K3S.md`)

## Альтернативний спосіб: Використання вкладки YAML

Якщо зручніше редагувати YAML напряму:

1. В ConfigMap натисніть вкладку **"<> YAML"**
2. Знайдіть секцію `data:` → `prometheus.yml:`
3. Замініть весь вміст після `prometheus.yml: |`
4. Натисніть **"Update ConfigMap"**

## Що перевірити після оновлення

### 1. Перевірка Prometheus pod

```bash
kubectl get pods -n monitoring -l app=prometheus
kubectl logs -n monitoring -l app=prometheus --tail=50
```

Має бути без помилок типу "Error loading config" або "Error parsing config".

### 2. Перевірка targets в Prometheus UI

1. Відкрийте Prometheus UI: `http://<node-ip>:30001/targets`
2. Знайдіть job **`snmp-routers`**
3. Перевірте, що є 2 targets:
   - `192.168.2.1` (vrn625)
   - `192.168.1.1` (syhiv17)
4. Обидва мають бути **UP** (зелений статус)

### 3. Перевірка метрик

В Prometheus UI (`http://<node-ip>:30001/graph`) виконайте:

```promql
# Перевірка доступності роутерів
up{job="snmp-routers"}

# Системна інформація
snmp_sysUpTime{job="snmp-routers"}
```

## Troubleshooting

### Проблема: ConfigMap не оновлюється

**Рішення:**
- Переконайтеся, що ви натиснули "Update ConfigMap", а не просто закрили сторінку
- Перевірте, чи немає помилок валідації YAML (червоні підкреслення)

### Проблема: Prometheus не завантажує нову конфігурацію

**Рішення:**
- Перезапустіть Prometheus pod
- Перевірте логи Prometheus на наявність помилок

### Проблема: YAML синтаксис помилка

**Рішення:**
- Переконайтеся, що відступи правильні (пробіли, не таби)
- Перевірте, що всі двокрапки та дефіси на місці
- Використайте валідатор YAML онлайн для перевірки

## Примітки

- **Відступи важливі:** YAML чутливий до відступів. Використовуйте пробіли, не таби
- **Копіювання:** Скопіюйте весь вміст від `global:` до кінця останнього job
- **Перезапуск:** Завжди перезапускайте Prometheus після оновлення ConfigMap
