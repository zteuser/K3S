# Корекція конфігурації WireGuard для macmini7 та beelinkeqr5 (роль клієнта)

macmini7 і beelinkeqr5 підключаються до Amper (master, work) як **WireGuard-клієнти**: вони **ініціюють** з'єднання до Endpoint сервера, не приймають вхідні WG-з'єднання. Нижче — рекомендації для клієнтської конфігурації.

---

## 1. Відмінності клієнта від сервера

| Параметр | Сервер (Amper master/work) | Клієнт (macmini7, beelinkeqr5) |
|----------|----------------------------|----------------------------------|
| **ListenPort** | Обов'язково (51824, 51825, 51826, 51827) | **Не вказувати** — клієнт не приймає вхідні з'єднання; WG обере ефемерний порт |
| **Endpoint** | Не потрібен (сервер слухає) | **Обов'язково** — IP:port Amper (master або work) |
| **SaveConfig** | За бажанням | **false** або не вказувати — щоб при `wg down` не перезаписати конфіг (handshake, endpoint) |
| **PostUp/PostDown** | NAT, FORWARD, відкриття порту | Якщо потрібно — лише маршрути або політики; **NAT не потрібен** |
| **PersistentKeepalive** | Часто на peer (роутери) | **Рекомендовано** у [Peer] (25–60 с) — клієнти за NAT/роутером зберігають сесію |

---

## 2. macmini7 (192.168.2.19) — клієнт до master wg2 та worker wg2

Два окремі інтерфейси: **wg0** → master (141.144.254.42:51824), **wg1** → worker (141.147.58.119:51825).

### 2.1 `/etc/wireguard/wg0.conf` (тунель до master)

```ini
[Interface]
PrivateKey = <приватний_ключ_macmini7_wg0>
Address = 192.168.100.10/30
MTU = 1412
# Клієнт: ListenPort не вказуємо
SaveConfig = false

[Peer]
PublicKey = <публічний_ключ_master_wg2>
Endpoint = 141.144.254.42:51824
AllowedIPs = 192.168.100.8/30, 10.0.10.10/32, 192.168.2.19/32
PersistentKeepalive = 25
```

### 2.2 `/etc/wireguard/wg1.conf` (тунель до worker)

```ini
[Interface]
PrivateKey = <приватний_ключ_macmini7_wg1>
Address = 192.168.200.10/30
MTU = 1412
SaveConfig = false

[Peer]
PublicKey = <публічний_ключ_worker_wg2>
Endpoint = 141.147.58.119:51825
AllowedIPs = 192.168.200.8/30, 10.0.10.20/32, 192.168.2.0/24
PersistentKeepalive = 25
```

**Примітки:**

- **AllowedIPs** — лише мережі, які мають йти в цей тунель (підмережа /30, OCI Amper, власна LAN за потреби). Решту трафіку клієнт відправляє звичайним шляхом (LAN/інтернет).
- Якщо потрібно тягнути в тунель додаткові мережі (наприклад 192.168.1.0/24 для доступу до beelinkeqr5), додайте їх у AllowedIPs у відповідному peer.
- **PostUp/PostDown** на клієнті зазвичай не потрібні: маршрути з’являються з AllowedIPs. Якщо використовуєте окрему таблицю маршрутизації або policy routing — додайте свої скрипти.

---

## 3. beelinkeqr5 (192.168.1.19) — клієнт до master wg3 та worker wg3

**wg0** → master (141.144.254.42:51826), **wg1** → worker (141.147.58.119:51827).

### 3.1 `/etc/wireguard/wg0.conf` (тунель до master)

```ini
[Interface]
PrivateKey = <приватний_ключ_beelinkeqr5_wg0>
Address = 192.168.100.14/30
MTU = 1412
SaveConfig = false

[Peer]
PublicKey = <публічний_ключ_master_wg3>
Endpoint = 141.144.254.42:51826
AllowedIPs = 192.168.100.12/30, 10.0.10.10/32, 192.168.1.19/32
PersistentKeepalive = 25
```

### 3.2 `/etc/wireguard/wg1.conf` (тунель до worker)

```ini
[Interface]
PrivateKey = <приватний_ключ_beelinkeqr5_wg1>
Address = 192.168.200.14/30
MTU = 1412
SaveConfig = false

[Peer]
PublicKey = <публічний_ключ_worker_wg3>
Endpoint = 141.147.58.119:51827
AllowedIPs = 192.168.200.12/30, 10.0.10.20/32, 192.168.1.0/24
PersistentKeepalive = 25
```

---

## 4. Що прибрати / не додавати на клієнтах

| Що | Чому |
|----|------|
| **ListenPort** у [Interface] | Клієнт не приймає вхідні WG-з'єднання; порт обирається автоматично |
| **SaveConfig = true** | Щоб після `wg down` не перезаписувати конфіг (endpoint, last handshake тощо) |
| **PostUp/PostDown** з NAT або FORWARD | На клієнті немає потреби в NAT для тунелю; маршрути дає AllowedIPs |

---

## 5. Запуск і перевірка на клієнтах

```bash
# Підняти інтерфейси
sudo wg-quick up wg0
sudo wg-quick up wg1

# Статус
sudo wg show

# Перевірка зв'язності (на macmini7)
ping -c 2 10.0.10.10
ping -c 2 10.0.10.20
# На beelinkeqr5 — аналогічно
```

Після змін конфігу:

```bash
sudo wg-quick down wg0
sudo wg-quick down wg1
# Внести правки в /etc/wireguard/wg0.conf, wg1.conf
sudo wg-quick up wg0
sudo wg-quick up wg1
```

---

## 6. Підсумок

- **macmini7** і **beelinkeqr5** — WireGuard-**клієнти**: Endpoint на Amper, **без ListenPort**, **SaveConfig = false**, **PersistentKeepalive** у [Peer].
- Адресація та AllowedIPs залишаються як у **WIREGUARD_CORRECT_TOPOLOGY.md**; змінюються лише параметри, що стосуються ролі клієнта (ListenPort, SaveConfig, зайві PostUp/PostDown).
