# Виправлення: Пропали всі targets в Prometheus

## Проблема

Після оновлення Prometheus конфігурації пропали всі targets.

## Причина

Можливо, при оновленні ConfigMap через Portainer була втрачена частина конфігурації або неправильно скопійований вміст.

## Рішення

### Крок 1: Перевірте поточну конфігурацію Prometheus

1. Kubernetes → Applications → monitoring
2. ConfigMap → prometheus-config
3. Перевірте, що в полі Value є всі jobs:
   - `prometheus`
   - `kubernetes-apiservers`
   - `kubernetes-nodes`
   - `node-exporter`
   - `cadvisor`
   - `kube-state-metrics`
   - `snmp-routers`

### Крок 2: Відновіть повну конфігурацію

Якщо якихось jobs немає, оновіть ConfigMap:

1. Відкрийте файл `prometheus/configmap.yaml`
2. Скопіюйте весь вміст після `prometheus.yml: |` (від рядка 10 до кінця)
3. В Portainer замініть весь вміст в полі Value
4. Натисніть Update ConfigMap

### Крок 3: Перезапустіть Prometheus

1. Application containers → prometheus pod
2. Натисніть на pod → Delete
3. Deployment автоматично створить новий pod

### Крок 4: Перевірка

1. Відкрийте Prometheus UI: `http://<node-ip>:30001/targets`
2. Перевірте, що всі jobs з'явилися
3. Перевірте статус кожного target

## Якщо targets все ще не з'являються

### Перевірте логи Prometheus

1. Application containers → prometheus pod → Logs
2. Шукайте помилки типу:
   - "Error loading config"
   - "Error parsing config"
   - "invalid scrape config"

### Перевірте синтаксис YAML

Переконайтеся, що:
- Всі відступи правильні (пробіли, не таби)
- Всі двокрапки на місці
- Всі дефіси правильні
- Немає зайвих символів

### Відновіть з резервної копії

Якщо є резервна копія робочої конфігурації, використайте її.
