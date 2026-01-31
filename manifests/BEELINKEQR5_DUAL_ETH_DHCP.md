# Два Ethernet на beelinkeqr5: DHCP на будь-якому інтерфейсі

На ноді **beelinkeqr5** (Ubuntu 24) два Ethernet-порти. Потрібно: при підключенні кабеля до **будь-якого** з них інтерфейс піднімався та отримував IP по DHCP.

Рішення: **netplan** з окремим описом обох інтерфейсів, `dhcp4: true` та `optional: true` (щоб завантаження не чекало на непідключений порт).

---

## 1. Дізнатися імена інтерфейсів

На beelinkeqr5 виконайте:

```bash
ip link show
# або
ls /sys/class/net/
```

Шукайте два ethernet-інтерфейси (не lo). Типові імена: `eth0`, `eth1` або `enp2s0`, `enp3s0` тощо. Далі в конфігу замініть `ETH0` та `ETH1` на реальні імена.

---

## 2. Поточний netplan (резервна копія)

```bash
ls /etc/netplan/
sudo cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak
# або якщо є інший файл — скопіюйте його
```

---

## 3. Конфігурація netplan

Створіть або відредагуйте файл в `/etc/netplan/` (наприклад `/etc/netplan/01-dual-eth-dhcp.yaml`):

```yaml
network:
  version: 2
  ethernets:
    ETH0:
      dhcp4: true
      optional: true
    ETH1:
      dhcp4: true
      optional: true
```

**Замініть `ETH0` та `ETH1`** на фактичні імена інтерфейсів (наприклад `enp2s0` та `enp3s0`).

- **dhcp4: true** — отримувати IPv4 по DHCP.
- **optional: true** — інтерфейс не блокує завантаження, якщо кабель не підключено.

Якщо потрібен і IPv6 по DHCP:

```yaml
network:
  version: 2
  ethernets:
    ETH0:
      dhcp4: true
      dhcp6: true
      optional: true
    ETH1:
      dhcp4: true
      dhcp6: true
      optional: true
```

---

## 4. Застосувати зміни

```bash
sudo netplan apply
```

Якщо є помилка — netplan покаже її; конфіг не застосується. Перевірте синтаксис та імена інтерфейсів.

---

## 5. Перевірка

Підключіть кабель до одного порту:

```bash
ip -4 addr show
ip route
```

Інтерфейс з кабелем має отримати IP та default route від DHCP. Переключіть кабель на другий порт — там має з’явитися адреса на другому інтерфейсі.

Якщо обидва кабелі підключені — обидва інтерфейси матимуть IP (два default route; система використовує один за метрикою).

---

## 6. Готовий конфіг для beelinkeqr5 (enp1s0, eno1)

На beelinkeqr5 два Ethernet: **enp1s0** та **eno1**. Файл `beelinkeqr5-netplan-dual-eth-dhcp.yaml` у репо вже містить ці імена — скопіюйте його на ноду в `/etc/netplan/01-dual-eth-dhcp.yaml` та виконайте `sudo netplan apply`.

---

## 7. Вимкнення Wi‑Fi при переході на Ethernet

Якщо Ethernet вже налаштований і потрібно лише вимкнути Wi‑Fi на beelinkeqr5.

### Одразу (до перезавантаження)

```bash
# М’яке блокування Wi‑Fi (rfkill)
sudo rfkill block wifi
```

Перевірка: `rfkill list` — Wi‑Fi має бути з `Soft blocked: yes`. Увімкнути знову: `sudo rfkill unblock wifi`.

### Постійно (після перезавантаження)

**Варіант A — rfkill при завантаженні (systemd):**

```bash
sudo tee /etc/systemd/system/disable-wifi.service <<'EOF'
[Unit]
Description=Disable WiFi radio
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/rfkill block wifi
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now disable-wifi.service
```

**Варіант B — NetworkManager (якщо Wi‑Fi керується NM):**

```bash
nmcli radio wifi off
# Зберегти стан: у більшості дистрибутивів NM зберігає це сам
```

**Варіант C — netplan:** у вашому netplan лише `ethernets`; якщо Wi‑Fi описується в іншому файлі в `/etc/netplan/` (наприклад `00-installer-config.yaml` з `wifis:`), можна видалити або закоментувати секцію `wifis:` в тому файлі, потім `sudo netplan apply`. Після цього Wi‑Fi не буде підніматися через netplan (але rfkill block wifi надійніше, якщо інші сервіси не піднімають його знову).
