# Архітектура SNMP моніторингу

## Як працює SNMP моніторинг

### Схема потоку даних

```
┌─────────────┐         ┌──────────────────┐         ┌──────────────┐
│ Prometheus  │────────▶│  SNMP Exporter   │────────▶│   Роутери    │
│             │ HTTP    │                  │  SNMP   │              │
│             │ GET     │                  │ GET     │              │
└─────────────┘         └──────────────────┘         └──────────────┘
     ▲                           │
     │                           │
     └───────────────────────────┘
          HTTP Response з метриками
          (Prometheus формат)
```

### Детальний процес

1. **Prometheus** (ініціатор)
   - За розкладом (кожні 15 секунд) робить HTTP GET запит до SNMP Exporter
   - Передає параметри: `target` (IP роутера) та `module` (модуль конфігурації)

2. **SNMP Exporter** (виконавець SNMP опитування)
   - Отримує HTTP запит від Prometheus
   - Виконує SNMP GET/WALK запити до роутера
   - Конвертує SNMP дані в формат Prometheus
   - Повертає метрики Prometheus через HTTP

3. **Роутери** (джерело даних)
   - Відповідають на SNMP запити
   - Надають метрики через SNMP протокол

## Де вказані IP адреси роутерів

### Файл: `prometheus/configmap.yaml`

IP адреси роутерів вказані в конфігурації Prometheus:

```yaml
# SNMP Exporter для моніторингу роутерів
- job_name: 'snmp-routers'
  static_configs:
    # Роутер vrn625 (UCG Ultra with UniFi OS)
    - targets:
      - 192.168.2.1    # ← IP адреса роутера vrn625
      labels:
        router_name: 'vrn625'
        router_ip: '192.168.2.1'
        router_model: 'UCG-Ultra'
        router_type: 'UniFi-OS'
    
    # Роутер syhiv17 (EdgeRouter-X)
    - targets:
      - 192.168.1.1    # ← IP адреса роутера syhiv17
      labels:
        router_name: 'syhiv17'
        router_ip: '192.168.1.1'
        router_model: 'EdgeRouter-X'
        router_type: 'EdgeOS'
```

**Розташування файлу:**
```
k3s/manifests/monitoring/prometheus/configmap.yaml
Рядки: 113-150
```

## Яка аплікація виконує SNMP опитування

### SNMP Exporter

**Аплікація:** `snmp-exporter` (Deployment в Kubernetes)

**Образ:** `prom/snmp-exporter:v0.25.0`

**Файли:**
- Deployment: `snmp-exporter/deployment.yaml`
- Service: `snmp-exporter/service.yaml`
- ConfigMap: `snmp-exporter/configmap.yaml` (SNMP конфігурація)
- Secret: `snmp-exporter/secret.yaml` (community string)

**Як працює:**

1. SNMP Exporter запускається як pod в namespace `monitoring`
2. Слухає HTTP запити на порту `9116`
3. Коли Prometheus робить запит типу:
   ```
   GET http://snmp-exporter:9116/snmp?target=192.168.2.1&module=unifi_ucg
   ```
4. SNMP Exporter:
   - Читає конфігурацію модуля `unifi_ucg` з ConfigMap
   - Виконує SNMP GET/WALK запити до `192.168.2.1`
   - Використовує community string `dfktyrb1` для аутентифікації
   - Конвертує SNMP дані в Prometheus метрики
   - Повертає метрики через HTTP

## Приклад HTTP запиту

### Запит від Prometheus до SNMP Exporter:

```
GET /snmp?target=192.168.2.1&module=unifi_ucg HTTP/1.1
Host: snmp-exporter:9116
```

### Відповідь від SNMP Exporter:

```
HTTP/1.1 200 OK
Content-Type: text/plain

# HELP snmp_sysUpTime The time (in hundredths of a second) since the network management portion of the system was last re-initialized.
# TYPE snmp_sysUpTime gauge
snmp_sysUpTime{instance="192.168.2.1"} 12345678

# HELP snmp_ifOperStatus The current operational state of the interface.
# TYPE snmp_ifOperStatus gauge
snmp_ifOperStatus{instance="192.168.2.1",ifIndex="1"} 1
snmp_ifOperStatus{instance="192.168.2.1",ifIndex="2"} 1
...
```

## Як додати новий роутер

### Крок 1: Додайте IP адресу в Prometheus конфігурацію

Відредагуйте `prometheus/configmap.yaml`:

```yaml
- job_name: 'snmp-routers'
  static_configs:
    # Існуючі роутери...
    - targets:
      - 192.168.2.1
      labels:
        router_name: 'vrn625'
        # ...
    
    # НОВИЙ роутер
    - targets:
      - 192.168.3.1    # ← Додайте IP адресу нового роутера
      labels:
        router_name: 'new-router'
        router_ip: '192.168.3.1'
        router_model: 'Router-Model'
        router_type: 'Router-Type'
```

### Крок 2: Оновіть Prometheus ConfigMap

1. Через Portainer:
   - Kubernetes → Applications → monitoring
   - Знайдіть ConfigMap **prometheus-config**
   - Натисніть **Editor**
   - Вставте оновлений вміст
   - Натисніть **Update**

2. Перезапустіть Prometheus:
   ```bash
   kubectl delete pods -n monitoring -l app=prometheus
   ```

### Крок 3: Перевірка

В Prometheus UI (`http://<node-ip>:30001/targets`) перевірте:
- Новий target з'явився в job `snmp-routers`
- Target показує статус **UP**

## Як працює relabel_configs

Prometheus використовує `relabel_configs` для перетворення конфігурації:

1. **Вихідна конфігурація:**
   ```yaml
   targets: ['192.168.2.1']
   ```

2. **Після relabel_configs:**
   - `__address__` (192.168.2.1) → `__param_target` (192.168.2.1)
   - `router_name` (vrn625) → `__param_module` (unifi_ucg)
   - `__address__` → `snmp-exporter:9116` (адреса SNMP Exporter)

3. **Результатний HTTP запит:**
   ```
   GET http://snmp-exporter:9116/snmp?target=192.168.2.1&module=unifi_ucg
   ```

## Перевірка роботи

### 1. Перевірка SNMP Exporter

```bash
# Статус pod
kubectl get pods -n monitoring -l app=snmp-exporter

# Логи
kubectl logs -n monitoring -l app=snmp-exporter

# Тест вручну
kubectl port-forward -n monitoring svc/snmp-exporter 9116:9116
curl "http://localhost:9116/snmp?target=192.168.2.1&module=unifi_ucg"
```

### 2. Перевірка Prometheus targets

Відкрийте: `http://<node-ip>:30001/targets`

Перевірте:
- Job `snmp-routers` має 2 targets
- Обидва targets показують **UP**
- Last Scrape показує останній успішний запит

### 3. Перевірка метрик

В Prometheus UI (`http://<node-ip>:30001/graph`):

```promql
# Перевірка доступності
up{job="snmp-routers"}

# Метрики роутерів
snmp_sysUpTime{job="snmp-routers"}
snmp_ifOperStatus{job="snmp-routers"}
```

## Підсумок

| Компонент | Роль | Де знаходиться |
|-----------|------|----------------|
| **Prometheus** | Ініціює запити, зберігає метрики | `prometheus/deployment.yaml` |
| **SNMP Exporter** | Виконує SNMP опитування | `snmp-exporter/deployment.yaml` |
| **IP адреси роутерів** | Вказані в конфігурації | `prometheus/configmap.yaml` (рядки 117-131) |
| **SNMP конфігурація** | Модулі та community string | `snmp-exporter/configmap.yaml` |

**Відповідь на питання:**
- **Яка аплікація виконує опитування?** → SNMP Exporter (`snmp-exporter` pod)
- **Де вказані IP адреси?** → `prometheus/configmap.yaml`, секція `snmp-routers` job, поле `targets`
