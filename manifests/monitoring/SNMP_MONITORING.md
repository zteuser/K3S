# Моніторинг роутерів через SNMP

## Огляд

Додано SNMP Exporter для моніторингу роутерів:
- **vrn625** (UCG Ultra with UniFi OS): 192.168.2.1
- **syhiv17** (EdgeRouter-X): 192.168.1.1

SNMP Exporter збирає метрики через SNMP протокол і експортує їх у форматі Prometheus.

### Моделі роутерів

- **vrn625**: Ubiquiti Cloud Gateway Ultra (UCG Ultra) з UniFi OS
  - Підтримує SNMP v1/v2c та v3
  - Використовує стандартні SNMP MIB (IF-MIB, IP-MIB, ICMP-MIB, TCP-MIB, UDP-MIB)
  - Модуль: `unifi_ucg`

- **syhiv17**: Ubiquiti EdgeRouter-X
  - Підтримує SNMP v1/v2c
  - Використовує стандартні SNMP MIB
  - Модуль: `edgerouter_x`

## Компоненти

### 1. SNMP Exporter
- **Deployment**: `snmp-exporter/deployment.yaml`
- **Service**: `snmp-exporter/service.yaml`
- **ConfigMap**: `snmp-exporter/configmap.yaml` - конфігурація SNMP модулів
- **Secret**: `snmp-exporter/secret.yaml` - SNMP community string

### 2. Prometheus Configuration
- Додано job `snmp-routers` в `prometheus/configmap.yaml`

## Розгортання

### Крок 1: Налаштування SNMP Community

**Важливо:** Переконайтеся, що SNMP community string налаштований правильно.

1. Перевірте `snmp-exporter/secret.yaml` - community string вже налаштований: `dfktyrb1`
2. Переконайтеся, що на роутерах встановлено той самий community string:
   - **UCG Ultra (vrn625)**: Settings → System → SNMP Monitoring → Community String
   - **EdgeRouter-X (syhiv17)**: `set service snmp community dfktyrb1 authorization ro`

3. Якщо community strings різні для роутерів, оновіть модулі в `snmp-exporter/configmap.yaml`

### Крок 2: Розгортання через Portainer

#### 2.1. Створення Secret

1. Kubernetes → Applications → monitoring
2. Натисніть **Create** → **Secret**
3. Назва: `snmp-community`
4. Namespace: `monitoring`
5. Тип: `Opaque`
6. Додайте ключ `community` зі значенням вашого SNMP community string
7. Натисніть **Create**

Або використайте готовий файл `snmp-exporter/secret.yaml`:
- Kubernetes → Applications → monitoring
- Натисніть **Create from code**
- Скопіюйте вміст `snmp-exporter/secret.yaml`
- Натисніть **Create**

#### 2.2. Створення ConfigMap

1. Kubernetes → Applications → monitoring
2. Натисніть **Create from code**
3. Скопіюйте вміст `snmp-exporter/configmap.yaml`
4. Натисніть **Create**

#### 2.3. Створення Deployment

1. Kubernetes → Applications → monitoring
2. Натисніть **Create from code**
3. Скопіюйте вміст `snmp-exporter/deployment.yaml`
4. Натисніть **Create**

#### 2.4. Створення Service

1. Kubernetes → Applications → monitoring
2. Натисніть **Create from code**
3. Скопіюйте вміст `snmp-exporter/service.yaml`
4. Натисніть **Create**

### Крок 3: Оновлення Prometheus Configuration

1. Kubernetes → Applications → monitoring
2. Знайдіть ConfigMap **prometheus-config**
3. Натисніть **Editor**
4. Скопіюйте оновлений вміст з `prometheus/configmap.yaml`
5. Натисніть **Update**

### Крок 4: Перезапуск Prometheus

1. Kubernetes → Applications → monitoring
2. Знайдіть Deployment **prometheus**
3. Натисніть **Restart**

Або через kubectl:
```bash
kubectl delete pods -n monitoring -l app=prometheus
```

## Перевірка

### 1. Перевірка статусу SNMP Exporter

```bash
kubectl get pods -n monitoring -l app=snmp-exporter
kubectl logs -n monitoring -l app=snmp-exporter
```

### 2. Перевірка targets в Prometheus

Відкрийте Prometheus UI: `http://<node-ip>:30001/targets`

Перевірте targets:
- `snmp-routers` - має показувати 2 targets (vrn625 та syhiv17)
- Обидва мають бути **UP**

### 3. Тест SNMP Exporter вручну

```bash
# Отримайте IP адресу pod SNMP Exporter
kubectl get pods -n monitoring -l app=snmp-exporter -o wide

# Порт-forward до SNMP Exporter
kubectl port-forward -n monitoring svc/snmp-exporter 9116:9116

# В іншому терміналі, протестуйте збір метрик
curl "http://localhost:9116/snmp?target=192.168.2.1&module=router"
```

### 4. Перевірка метрик в Prometheus

В Prometheus UI (`http://<node-ip>:30001/graph`) виконайте запити:

```promql
# Перевірка доступності роутерів
up{job="snmp-routers"}

# Системна інформація роутерів
snmp_sysUpTime{job="snmp-routers"}

# Стан інтерфейсів
snmp_ifOperStatus{job="snmp-routers"}

# Швидкість інтерфейсів
snmp_ifSpeed{job="snmp-routers"}

# Трафік на інтерфейсах (для стандартних інтерфейсів)
rate(snmp_ifInOctets{job="snmp-routers"}[5m])
rate(snmp_ifOutOctets{job="snmp-routers"}[5m])

# Трафік на високошвидкісних інтерфейсах (64-bit counters)
rate(snmp_ifHCInOctets{job="snmp-routers"}[5m])
rate(snmp_ifHCOutOctets{job="snmp-routers"}[5m])

# Метрики по конкретному роутеру
up{job="snmp-routers", router_name="vrn625"}
up{job="snmp-routers", router_name="syhiv17"}
```

## Налаштування SNMP Community

### Поточна конфігурація

За замовчуванням обидва роутери використовують community string `dfktyrb1`, який налаштований в:
- `snmp-exporter/secret.yaml` (для довідки)
- `snmp-exporter/configmap.yaml` (в модулях `unifi_ucg` та `edgerouter_x`)

### Якщо community string різний для кожного роутера

Якщо роутери мають різні community strings, оновіть модулі в `snmp-exporter/configmap.yaml`:

```yaml
modules:
  unifi_ucg:
    # ... інші налаштування ...
    auth:
      community: community_for_vrn625  # Замініть на реальний
  
  edgerouter_x:
    # ... інші налаштування ...
    auth:
      community: community_for_syhiv17  # Замініть на реальний
```

Prometheus конфігурація вже налаштована для використання правильних модулів через `snmp_module` label.

### Використання SNMP v3

Якщо роутери використовують SNMP v3, оновіть `snmp-exporter/configmap.yaml`:

```yaml
modules:
  router:
    walk:
      - 1.3.6.1.2.1.1
      - 1.3.6.1.2.1.2
    version: 3
    auth:
      username: monitoring
      security_level: authPriv
      password: your_password
      auth_protocol: SHA
      priv_protocol: AES
      priv_password: your_priv_password
```

## Доступні метрики

SNMP Exporter збирає наступні метрики для обох роутерів (UCG Ultra та EdgeRouter-X):

### Системні метрики (SNMPv2-MIB)
- `snmp_sysDescr` - опис системи
- `snmp_sysUpTime` - час роботи системи (в сотих частках секунди)
- `snmp_sysContact` - контактна інформація
- `snmp_sysName` - ім'я системи
- `snmp_sysLocation` - місцезнаходження

### Метрики інтерфейсів (IF-MIB)
- `snmp_ifDescr` - опис інтерфейсу
- `snmp_ifType` - тип інтерфейсу
- `snmp_ifSpeed` - швидкість інтерфейсу (bps)
- `snmp_ifOperStatus` - операційний стан (1=up, 2=down, 3=testing, etc.)
- `snmp_ifAdminStatus` - адміністративний стан (1=up, 2=down, 3=testing)
- `snmp_ifInOctets` - вхідні байти (32-bit counter)
- `snmp_ifOutOctets` - вихідні байти (32-bit counter)
- `snmp_ifInErrors` - вхідні помилки
- `snmp_ifOutErrors` - вихідні помилки
- `snmp_ifInDiscards` - відкинуті вхідні пакети
- `snmp_ifOutDiscards` - відкинуті вихідні пакети
- `snmp_ifHCInOctets` - вхідні байти (64-bit counter, для високошвидкісних інтерфейсів)
- `snmp_ifHCOutOctets` - вихідні байти (64-bit counter, для високошвидкісних інтерфейсів)

### IP метрики (IP-MIB)
- `snmp_ipInReceives` - вхідні IP пакети
- `snmp_ipOutRequests` - вихідні IP запити
- `snmp_ipInDiscards` - відкинуті вхідні пакети
- `snmp_ipOutDiscards` - відкинуті вихідні пакети
- `snmp_ipInDelivers` - доставлені IP пакети
- `snmp_ipOutForwDatagrams` - переслані IP пакети

### ICMP метрики (ICMP-MIB)
- `snmp_icmpInMsgs` - вхідні ICMP повідомлення
- `snmp_icmpOutMsgs` - вихідні ICMP повідомлення
- `snmp_icmpInErrors` - вхідні ICMP помилки
- `snmp_icmpOutErrors` - вихідні ICMP помилки

### TCP метрики (TCP-MIB)
- `snmp_tcpInSegs` - вхідні TCP сегменти
- `snmp_tcpOutSegs` - вихідні TCP сегменти
- `snmp_tcpCurrEstab` - поточні встановлені з'єднання
- `snmp_tcpRetransSegs` - повторно передані сегменти

### UDP метрики (UDP-MIB)
- `snmp_udpInDatagrams` - вхідні UDP датаграми
- `snmp_udpOutDatagrams` - вихідні UDP датаграми
- `snmp_udpInErrors` - вхідні UDP помилки

### Приклади PromQL запитів

```promql
# Трафік на інтерфейсах (використовуйте ifHCInOctets для високошвидкісних інтерфейсів)
rate(snmp_ifHCInOctets{job="snmp-routers"}[5m]) * 8 / 1024 / 1024  # Mbps
rate(snmp_ifHCOutOctets{job="snmp-routers"}[5m]) * 8 / 1024 / 1024  # Mbps

# Стан інтерфейсів
snmp_ifOperStatus{job="snmp-routers"} == 1  # UP
snmp_ifOperStatus{job="snmp-routers"} == 2  # DOWN

# Помилки на інтерфейсах
rate(snmp_ifInErrors{job="snmp-routers"}[5m])
rate(snmp_ifOutErrors{job="snmp-routers"}[5m])

# Uptime роутерів (в годинах)
snmp_sysUpTime{job="snmp-routers"} / 360000  # конвертація з сотих часток секунди

# TCP з'єднання
snmp_tcpCurrEstab{job="snmp-routers"}
```

## Troubleshooting

### Проблема: Targets показують DOWN

**Перевірте:**

1. **SNMP доступність з кластера:**
   ```bash
   # Запустіть pod для тестування
   kubectl run -it --rm snmp-test --image=prom/snmp-exporter:v0.25.0 --restart=Never -- sh
   
   # Всередині pod
   snmpwalk -v2c -c public 192.168.2.1 1.3.6.1.2.1.1.1
   ```

2. **Логи SNMP Exporter:**
   ```bash
   kubectl logs -n monitoring -l app=snmp-exporter
   ```

3. **Перевірте community string:**
   - Переконайтеся, що community string правильний
   - Перевірте, чи SNMP увімкнено на роутерах
   - Перевірте firewall правила

4. **Перевірте конфігурацію модуля:**
   - Відкрийте `snmp-exporter/configmap.yaml`
   - Переконайтеся, що модуль `router` правильно налаштований

### Проблема: Немає метрик в Prometheus

1. **Перевірте targets:**
   - Відкрийте `http://<node-ip>:30001/targets`
   - Переконайтеся, що `snmp-routers` targets показують UP

2. **Перевірте PromQL запити:**
   ```promql
   # Має повернути метрики
   up{job="snmp-routers"}
   snmp_sysUpTime{job="snmp-routers"}
   ```

3. **Перевірте логи Prometheus:**
   ```bash
   kubectl logs -n monitoring -l app=prometheus | grep snmp
   ```

### Проблема: Timeout при зборі метрик

1. **Збільште timeout в ConfigMap:**
   ```yaml
   modules:
     router:
       timeout: 10s  # Збільште з 5s до 10s
   ```

2. **Перевірте мережеву доступність:**
   - Переконайтеся, що роутери доступні з кластера
   - Перевірте firewall правила

## Додаткові ресурси

- [SNMP Exporter Documentation](https://github.com/prometheus/snmp_exporter)
- [SNMP Exporter Configuration Generator](https://github.com/prometheus/snmp_exporter/tree/main/generator)
- [Prometheus SNMP Monitoring Guide](https://prometheus.io/docs/guides/snmp/)

## Grafana dashboards (імпорт)

### Варіант 1: Автопровіжнінг (рекомендовано)

1. Створіть/оновіть ConfigMap `grafana-dashboard-providers` та `grafana-dashboards-json`:
   - файл: `grafana/configmap-dashboards.yaml`
2. Оновіть Grafana deployment (додані volume mounts):
   - файл: `grafana/deployment.yaml`
3. Перезапустіть Grafana pod.

Після перезапуску в Grafana з’явиться папка **SNMP** з дашбордом **SNMP Routers (vrn625 / syhiv17)**.

### Варіант 2: Імпорт через UI

1. Grafana → **Dashboards** → **New** → **Import**
2. Вставте JSON з файлу:
   - `grafana/dashboards/snmp-routers.json`
3. Виберіть datasource **Prometheus** → **Import**.
