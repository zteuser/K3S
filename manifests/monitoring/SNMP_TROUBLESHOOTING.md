# Troubleshooting SNMP Exporter

## Проблема: "context deadline exceeded"

Ця помилка означає, що SNMP Exporter не може підключитися до роутерів або отримати відповідь.

## Крок 1: Перевірка доступності роутерів з кластера

### Через Portainer Console

1. Application containers → snmp-exporter pod
2. Натисніть **Console**
3. Виконайте тести:

```bash
# Перевірка доступності роутерів
ping -c 3 192.168.2.1
ping -c 3 192.168.1.1

# Перевірка SNMP порту (161)
nc -zv -u 192.168.2.1 161
nc -zv -u 192.168.1.1 161
```

### Якщо ping не працює

- Перевірте мережеву доступність з кластера до роутерів
- Перевірте firewall правила на роутерах
- Перевірте, чи роутери в тій самій мережі

## Крок 2: Тест SNMP вручну

### Встановіть SNMP tools в pod (якщо потрібно)

```bash
# В консолі snmp-exporter pod
apk add net-snmp-tools  # для Alpine-based образів
# або
apt-get update && apt-get install -y snmp  # для Debian-based
```

### Тест SNMP запиту

```bash
# Тест SNMP v2c
snmpwalk -v2c -c dfktyrb1 192.168.2.1 1.3.6.1.2.1.1.1.0
snmpwalk -v2c -c dfktyrb1 192.168.1.1 1.3.6.1.2.1.1.1.0
```

**Якщо snmpwalk працює:**
- SNMP налаштований правильно на роутерах
- Проблема в конфігурації SNMP Exporter

**Якщо snmpwalk не працює:**
- Перевірте SNMP налаштування на роутерах
- Перевірте community string
- Перевірте firewall правила

## Крок 3: Тест SNMP Exporter вручну

### Через curl в pod

```bash
# В консолі snmp-exporter pod
curl "http://localhost:9116/snmp?target=192.168.2.1&module=unifi_ucg"
curl "http://localhost:9116/snmp?target=192.168.1.1&module=edgerouter_x"
```

**Якщо curl працює:**
- SNMP Exporter працює правильно
- Проблема в мережевій доступності або конфігурації Prometheus

**Якщо curl не працює або timeout:**
- Перевірте доступність роутерів з pod
- Перевірте SNMP налаштування на роутерах

## Крок 4: Перевірка SNMP на роутерах

### UCG Ultra (vrn625) - UniFi OS

1. Відкрийте UniFi Network Controller
2. Settings → System → SNMP Monitoring
3. Перевірте:
   - SNMP увімкнено
   - Community String: `dfktyrb1`
   - Версія: v2c
   - Дозволені IP адреси (якщо налаштовано)

### EdgeRouter-X (syhiv17)

Підключіться через SSH:

```bash
ssh admin@192.168.1.1

# Перевірте SNMP налаштування
show service snmp

# Якщо не налаштовано, налаштуйте:
configure
set service snmp community dfktyrb1 authorization ro
commit
save
exit
```

## Крок 5: Перевірка firewall

### На роутерах

Переконайтеся, що порт 161 UDP відкритий для кластера:

- UCG Ultra: Перевірте firewall rules в UniFi Controller
- EdgeRouter-X: Перевірте firewall rules через CLI

### З кластера

```bash
# В консолі snmp-exporter pod
nc -zv -u 192.168.2.1 161
nc -zv -u 192.168.1.1 161
```

## Крок 6: Перевірка логів SNMP Exporter

1. Application containers → snmp-exporter pod → Logs
2. Шукайте помилки типу:
   - "timeout"
   - "connection refused"
   - "no route to host"

## Крок 7: Збільшення timeout

Якщо роутери відповідають, але повільно, збільште timeout:

Оновіть `prometheus/configmap.yaml`:

```yaml
- job_name: 'snmp-routers'
  scrape_interval: 60s
  scrape_timeout: 60s  # Збільште з 30s до 60s
```

## Крок 8: Тест з простішим модулем

Спробуйте використати простий модуль `router` замість специфічних:

Оновіть `prometheus/configmap.yaml`:

```yaml
params:
  module: [router]  # Замість динамічного вибору
```

## Типові проблеми та рішення

### Проблема 1: Роутери недоступні з кластера

**Рішення:**
- Перевірте мережеву маршрутизацію
- Перевірте firewall правила
- Перевірте, чи роутери в тій самій мережі

### Проблема 2: SNMP не налаштований на роутерах

**Рішення:**
- Налаштуйте SNMP на обох роутерах
- Перевірте community string
- Перевірте версію SNMP (має бути v2c)

### Проблема 3: Community string неправильний

**Рішення:**
- Перевірте community string на роутерах
- Оновіть `snmp-exporter/configmap.yaml` якщо потрібно

### Проблема 4: Firewall блокує SNMP

**Рішення:**
- Дозвольте UDP порт 161 з кластера до роутерів
- Перевірте firewall rules на роутерах

## Швидка перевірка

```bash
# 1. Перевірка доступності
ping 192.168.2.1
ping 192.168.1.1

# 2. Перевірка SNMP порту
nc -zv -u 192.168.2.1 161
nc -zv -u 192.168.1.1 161

# 3. Тест SNMP (якщо snmpwalk встановлений)
snmpwalk -v2c -c dfktyrb1 192.168.2.1 1.3.6.1.2.1.1.1.0
snmpwalk -v2c -c dfktyrb1 192.168.1.1 1.3.6.1.2.1.1.1.0
```

Якщо всі тести проходять, але Prometheus все ще показує DOWN, перевірте конфігурацію Prometheus та логи SNMP Exporter.
