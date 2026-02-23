# Victron BLE Exporter: дані не надходять (D-Bus AccessDenied)

## Симптоми

- `victron_last_success_unixtime 0`
- У логах: `BLE scan failed: [org.freedesktop.DBus.Error.AccessDenied] Client tried to send a message other than Hello without being registered`
- Після рестарту `victron-prometheus-exporter.service` помилка не зникає

## Причина

Експортер зчитує Victron по BLE через D-Bus (BlueZ). Повідомлення «without being registered» означає одне з двох:

1. **Втрата реєстрації на D-Bus** — після перезапуску `bluetooth.service` або `dbus.service` старе з’єднання процесу стає невалідним; рестарт експортера іноді допомагає, але якщо bluetoothd знову перезапускався або є обмеження з’єднань — помилка повертається.
2. **Права доступу** — сервіс не має права використовувати org.bluez на system bus (користувач не в групі `bluetooth` або політика D-Bus).

## Перевірено на beelinkeqr5

- Сервіс: **User=malex**, **Group=malex**.
- Користувач **malex не в групі bluetooth** (`groups malex` → немає `bluetooth`) — це типова причина AccessDenied.
- Після `restart bluetooth` → `restart victron-prometheus-exporter` метрики тимчасово з’являються; щоб проблема не повторювалась, потрібно: додати malex у групу `bluetooth` і в unit додати залежність від `bluetooth.service`.

## Кроки вирішення на beelinkeqr5

### 1. Під яким користувачем запускається сервіс

```bash
systemctl show victron-prometheus-exporter.service -p User -p Group
```

- Якщо `User=root` — переходимо до кроку 2 (bluetooth + D-Bus).
- Якщо `User=malex` (або інший не-root) — цей користувач **має** бути в групі `bluetooth`, інакше D-Bus може повертати AccessDenied.

Додати користувача в групу bluetooth (якщо сервіс не root):

```bash
sudo usermod -aG bluetooth malex   # замість malex — користувач з systemctl show
# Для сервісу достатньо перезапустити сервіс; новий процес вже матиме групу bluetooth.
# Для поточного SSH-сеансу — перелогін або reboot.
sudo systemctl restart victron-prometheus-exporter
```

### 2. Перезапустити Bluetooth і лише потім експортер

Часто після перезапуску bluetoothd D-Bus-з’єднання експортера «відживають» після чистого циклу bluetooth → exporter:

```bash
sudo systemctl restart bluetooth
sleep 3
sudo systemctl restart victron-prometheus-exporter
```

Через хвилину перевірити:

```bash
curl -s http://localhost:9091/metrics | grep -E '^victron_(last_success|soc)'
journalctl -u victron-prometheus-exporter -n 20 --no-pager
```

### 3. Залежність unit: запуск після Bluetooth і рестарт разом з ним

Щоб експортер завжди стартував після bluetooth і перезапускався разом із ним (тоді D-Bus-реєстрація буде свіжа після кожного рестарту bluetooth), у секції **\[Unit]** додайте (можна поруч із існуючим `After=network.target`):

```ini
[Unit]
Description=Victron MultiPlus Prometheus exporter (BLE)
After=network.target bluetooth.service
BindsTo=bluetooth.service

[Service]
# ... решта без змін (User=malex, ExecStart=...) ...
```

Перезавантажити unit і сервіс:

```bash
sudo systemctl daemon-reload
sudo systemctl restart victron-prometheus-exporter
```

(Якщо unit зараз не в репозиторії, його можна відредагувати локально: `sudo systemctl edit --full victron-prometheus-exporter.service`.)

### 4. Обмеження кількості D-Bus-з’єднань (Raspberry Pi / вбудовані системи)

Якщо в журналі **dbus** (не тільки victron) з’являється щось на кшталт «maximum number of active connections for UID … reached», то експортер або бібліотека (bleak) може не закривати з’єднання між скануваннями. Тоді варто:

- перевірити, чи немає дубльованих сервісів/скриптів, що тримають BLE;
- оновити експортер/bleak, якщо є фікс «reconnect on DBus disconnect» або коректне закриття з’єднань.

### 5. Швидка перевірка BlueZ і адаптера

```bash
# Адаптер увімкнений і видно
bluetoothctl show

# Сканування з консолі (якщо є права)
bluetoothctl scan on
# (через кілька секунд Ctrl+C)
```

Якщо тут теж помилки — спочатку вирішити bluetooth/адаптер, потім експортер.

## Підсумок

| Що зробити | Команда / дія |
|------------|----------------|
| Користувач сервісу не root (на beelinkeqr5: malex) | `sudo usermod -aG bluetooth malex` → потім `sudo systemctl restart victron-prometheus-exporter` (для сеансу malex — перелогін) |
| Один раз «оживити» | `systemctl restart bluetooth` → через 3 с → `systemctl restart victron-prometheus-exporter` |
| Назавжди: старт після bluetooth і рестарт разом з ним | У unit: `After=network.target bluetooth.service` та `BindsTo=bluetooth.service`, потім `daemon-reload` і restart експортера |

Після змін перевірити метрики та логи як у кроці 2.
