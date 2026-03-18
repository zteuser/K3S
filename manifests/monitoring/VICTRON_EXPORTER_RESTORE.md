# Відновлення Victron MultiPlus (BLE) дашбоарду в Grafana

## Архітектура

- **beelinkeqr5** (192.168.1.19) — хост on-prem, поруч з Victron MultiPlus
- **victron-prometheus-exporter** — systemd-сервіс на beelinkeqr5, слухає порт **9091**
- **Prometheus** (в кластері, master-node) — scrape job `victron-inverter` → `192.168.1.19:9091`
- **Grafana** — дашбоард "Victron MultiPlus (BLE)", запити до Prometheus (`victron_*` метрики)

## Чеклист відновлення

### 1. Перевірити exporter на beelinkeqr5

```bash
ssh malex@192.168.1.19

# Статус сервісу
sudo systemctl status victron-prometheus-exporter

# Якщо inactive — запустити
sudo systemctl start victron-prometheus-exporter
sudo systemctl enable victron-prometheus-exporter

# Метрики локально
curl -s http://localhost:9091/metrics | grep -E '^victron_(last_success|soc|battery_voltage)'
```

### 2. Якщо D-Bus/Bluetooth AccessDenied (victron_last_success 0)

Див. **victron-exporter-dbus-fix.md**. Швидкий фікс:

```bash
# Додати malex у групу bluetooth
sudo usermod -aG bluetooth malex

# Рестарт bluetooth → exporter
sudo systemctl restart bluetooth
sleep 3
sudo systemctl restart victron-prometheus-exporter
```

### 3. Якщо exporter не встановлений

Деплой через Ansible (з каталогу ORACLE Free Tier):

```bash
cd /Users/omartyny/WORK/"ORACLE Free Tier"
ansible-playbook victron-deploy-custom.yml
```

Потім переконатися, що venv і залежності є:

```bash
ssh malex@192.168.1.19
ls -la /opt/victron-custom/
# Має бути: venv/, victron_prometheus_exporter.py, read_victron_instant.py

# Якщо venv немає:
python3 -m venv /opt/victron-custom/venv
/opt/victron-custom/venv/bin/pip install victron-ble bleak pycryptodome
```

### 4. Перевірити мережі: Prometheus → 192.168.1.19

Prometheus працює на master-node (OCI). Щоб scrape 192.168.1.19, потрібен мережевий шлях (WireGuard, VPN тощо).

```bash
# З поду Prometheus:
kubectl exec -n monitoring deploy/prometheus -- wget -qO- --timeout=5 http://192.168.1.19:9091/metrics

# Або з іншого поду в кластері:
kubectl run curl-test --rm -i --restart=Never --image=curlimages/curl -- curl -s --connect-timeout 5 http://192.168.1.19:9091/metrics | head -5
```

Якщо timeout — перевірити маршрутизацію OCI ↔ 192.168.1.x.

### 5. Перевірити Prometheus scrape target

Grafana → Explore → Prometheus → запит:

```promql
victron_battery_voltage
```

Якщо результат порожній — перевірити Targets у Prometheus: Status → Targets → `victron-inverter` (UP/DOWN).

### 6. Оновити unit для BindsTo bluetooth (опційно)

Щоб exporter завжди стартував після bluetooth і перезапускався разом із ним, додати в unit:

```ini
[Unit]
After=network.target bluetooth.service
BindsTo=bluetooth.service
```

Сервіс оновлений у `ORACLE Free Tier/scripts/victron-prometheus-exporter.service`.

## Швидкий restart

```bash
ssh malex@192.168.1.19 'sudo systemctl restart bluetooth && sleep 3 && sudo systemctl restart victron-prometheus-exporter'
```

Через 1–2 хв дані мають з’явитися в Grafana.
