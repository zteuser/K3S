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

## 4. Чи можна спростити: AllowedIPs = 0.0.0.0/0? Чи тунель стане default route?

**Так.** Якщо в [Peer] вказати **AllowedIPs = 0.0.0.0/0**, WireGuard додасть маршрут **0.0.0.0/0** через цей інтерфейс — тобто **тунель стане default route**: весь IPv4-трафік клієнта піде через цей peer (до Amper).

### 4.1 Наслідки

| Аспект | AllowedIPs = конкретні мережі (як зараз) | AllowedIPs = 0.0.0.0/0 |
|--------|------------------------------------------|-------------------------|
| **Маршрути** | У тунель йде лише трафік до 10.0.10.x, 192.168.100.x, 192.168.200.x, інша LAN | У тунель йде **весь** трафік (default route) |
| **Інтернет з клієнта** | Через **локальний** шлюз (VRN625/Syhiv17) | Через **Amper** — потрібно, щоб на Amper був NAT і forward у інтернет (enp0s6) |
| **Складність конфігу** | Потрібно перераховувати мережі | Один рядок: `AllowedIPs = 0.0.0.0/0` |

Тобто **0.0.0.0/0** спрощує конфіг, але перетворює тунель у **повний VPN** (full tunnel): і кластер, і інтернет йдуть через Amper.

### 4.2 Коли варто використовувати 0.0.0.0/0

- Потрібен **full tunnel**: весь трафік (включно з інтернетом) через Amper.
- На **Amper** для трафіку з wg2/wg3 у бік інтернету увімкнений **NAT** (MASQUERADE) і **FORWARD** (як для wg0/wg1 у helper-скриптах), і політика дозволяє такий трафік.
- На клієнті достатньо **одного** інтерфейсу з **одним** peer (наприклад тільки до master): два peer з 0.0.0.0/0 дадуть два default routes, ядро обере один — частина трафіку піде в один тунель, частина в інший або все в один залежно від метрики.

### 4.3 Коли краще залишити конкретні AllowedIPs (split tunnel)

- Потрібен лише **доступ до кластера** (10.0.10.x, 192.168.x, тунельні /30), а **інтернет** — як раніше через локальний шлюз (VRN625/Syhiv17).
- Не потрібно налаштовувати на Amper NAT/FORWARD для трафіку з macmini7/beelinkeqr5 у інтернет.
- Два peer (master і worker): кожен з конкретними AllowedIPs — маршрути розподіляються коректно (до master — wg0, до worker — wg1).

### 4.4 Приклад спрощеного варіанту з 0.0.0.0/0 (один peer, full tunnel)

Якщо потрібен саме full tunnel і достатньо **одного** з’єднання (наприклад тільки до master):

```ini
[Interface]
PrivateKey = ...
Address = 192.168.100.10/30
MTU = 1412
SaveConfig = false

[Peer]
PublicKey = <публічний_ключ_master_wg2>
Endpoint = 141.144.254.42:51824
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

Після `wg-quick up wg0` на клієнті з’явиться **default route через wg0**; весь трафік піде на Amper. На Amper для wg2 потрібно дозволити FORWARD і (якщо потрібен вихід у інтернет) NAT для підмережі 192.168.100.8/30 у бік enp0s6.

**Підсумок:** так, **AllowedIPs = 0.0.0.0/0** спрощує конфіг і робить тунель **default route**. Це доречно, якщо потрібен full tunnel і на Amper налаштовано відповідний NAT/forward. Для доступу лише до кластера зі збереженням локального інтернету краще залишити конкретні AllowedIPs (split tunnel).

---

## 5. Table = off: маршрути формує лише FRR/OSPF

За замовчуванням **wg-quick** за **AllowedIPs** додає маршрути в основну таблицю. У схемі з FRR/OSPF **джерелом маршрутів** має бути OSPF, а не WireGuard.

### 5.1 Роль Table та AllowedIPs

| Параметр | Що робить |
|----------|-----------|
| **Table = off** (у `[Interface]`) | **wg-quick не додає** жодних маршрутів у таблицю. Таблицю заповнює лише FRR (zebra) з OSPF. |
| **AllowedIPs** (у `[Peer]`) | Не маршрути для ядра, а **критерій для модуля WireGuard**: який трафік шифрувати і відправляти якому peer. Ядро вже вирішило (за OSPF), що пакет йде через wg0; WireGuard перевіряє AllowedIPs і шифрує пакет для відповідного peer. |

Послідовність: **OSPF** встановлює маршрут (наприклад, 10.0.10.10/32 via 192.168.100.9 dev wg0) → пакет йде на wg0 → **WireGuard** дивиться AllowedIPs для peer з next-hop 192.168.100.9 → якщо destination в AllowedIPs, шифрує і відправляє. Тому **AllowedIPs мають містити всі підмережі, які доступні в OSPF і йдуть через цей peer** — інакше трафік не буде зашифрований для цього тунелю.

### 5.2 AllowedIPs під OSPF (ті самі мережі, що в Area 0)

Мережі Area 0 у нашій топології: **10.0.10.0/24**, **192.168.100.0/24**, **192.168.200.0/24**, **192.168.1.0/24**, **192.168.2.0/24**. У кожному peer у **AllowedIPs** вказуємо ті з них, які **доступні через цей тунель** (той самий набір, який OSPF може віддати через цей лінк).

### 5.3 macmini7 з Table = off

**wg0** (до master): через цей тунель доступні 192.168.100.8/30, 10.0.10.0/24, 192.168.100.0/24, 192.168.200.0/24, 192.168.1.0/24, 192.168.2.0/24 (все, що OSPF оголошує і до чого можна дістатися через master). Для мінімального набору достатньо: підмережа /30 цього лінка + мережі, які не на локальному LAN (192.168.2.0/24 у macmini7 — локальна, її можна не тягнути в тунель, якщо не потрібно).

**Приклад wg0.conf (macmini7, Table = off):**

```ini
[Interface]
PrivateKey = <приватний_ключ_macmini7_wg0>
Address = 192.168.100.10/30
MTU = 1412
Table = off
SaveConfig = false

[Peer]
PublicKey = <публічний_ключ_master_wg2>
Endpoint = 141.144.254.42:51824
AllowedIPs = 192.168.100.8/30, 192.168.100.0/24, 192.168.200.0/24, 10.0.10.0/24, 192.168.1.0/24, 192.168.2.0/24
PersistentKeepalive = 25
```

**Приклад wg1.conf (macmini7, Table = off):**

```ini
[Interface]
PrivateKey = <приватний_ключ_macmini7_wg1>
Address = 192.168.200.10/30
MTU = 1412
Table = off
SaveConfig = false

[Peer]
PublicKey = <публічний_ключ_worker_wg2>
Endpoint = 141.147.58.119:51825
AllowedIPs = 192.168.200.8/30, 192.168.100.0/24, 192.168.200.0/24, 10.0.10.0/24, 192.168.1.0/24, 192.168.2.0/24
PersistentKeepalive = 25
```

Маршрути (який peer використовувати для 10.0.10.10, 192.168.1.0/24 тощо) визначає **OSPF**, не WireGuard.

### 5.4 beelinkeqr5 з Table = off

Аналогічно: **Table = off** у обох інтерфейсах, **AllowedIPs** — ті самі мережі OSPF Area 0, що доступні через відповідний тунель.

**Приклад wg0.conf (beelinkeqr5, Table = off):**

```ini
[Interface]
PrivateKey = <приватний_ключ_beelinkeqr5_wg0>
Address = 192.168.100.14/30
MTU = 1412
Table = off
SaveConfig = false

[Peer]
PublicKey = <публічний_ключ_master_wg3>
Endpoint = 141.144.254.42:51826
AllowedIPs = 192.168.100.12/30, 192.168.100.0/24, 192.168.200.0/24, 10.0.10.0/24, 192.168.1.0/24, 192.168.2.0/24
PersistentKeepalive = 25
```

**Приклад wg1.conf (beelinkeqr5, Table = off):**

```ini
[Interface]
PrivateKey = <приватний_ключ_beelinkeqr5_wg1>
Address = 192.168.200.14/30
MTU = 1412
Table = off
SaveConfig = false

[Peer]
PublicKey = <публічний_ключ_worker_wg3>
Endpoint = 141.147.58.119:51827
AllowedIPs = 192.168.200.12/30, 192.168.100.0/24, 192.168.200.0/24, 10.0.10.0/24, 192.168.1.0/24, 192.168.2.0/24
PersistentKeepalive = 25
```

### 5.5 Amper (master-node, work-node)

На серверах теж можна вказати **Table = off** у кожному `[Interface]` (wg0–wg3) і залишити в **AllowedIPs** усі підмережі, які оголошуються в OSPF і йдуть через відповідний peer. Маршрути тоді формує лише FRR/OSPF.

**Підсумок:** **Table = off** + **AllowedIPs = (усі підмережі OSPF Area 0, доступні через цей peer)** — коректний варіант, коли route table має формувати FRR/OSPF, а WireGuard лише шифрує трафік за тим же списком мереж.

---

## 6. Що прибрати / не додавати на клієнтах

| Що | Чому |
|----|------|
| **ListenPort** у [Interface] | Клієнт не приймає вхідні WG-з'єднання; порт обирається автоматично |
| **SaveConfig = true** | Щоб після `wg down` не перезаписувати конфіг (endpoint, last handshake тощо) |
| **PostUp/PostDown** з NAT або FORWARD | На клієнті немає потреби в NAT для тунелю; маршрути дає AllowedIPs (або OSPF при Table = off) |

---

## 7. Запуск і перевірка на клієнтах

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

## 8. Підсумок

- **macmini7** і **beelinkeqr5** — WireGuard-**клієнти**: Endpoint на Amper, **без ListenPort**, **SaveConfig = false**, **PersistentKeepalive** у [Peer].
- Адресація та AllowedIPs залишаються як у **WIREGUARD_CORRECT_TOPOLOGY.md**; змінюються лише параметри, що стосуються ролі клієнта (ListenPort, SaveConfig, зайві PostUp/PostDown).
- Якщо маршрути має формувати **FRR/OSPF**, а не WireGuard: у кожному WG-інтерфейсі вказуйте **Table = off** і в **AllowedIPs** перераховуйте усі підмережі OSPF Area 0, доступні через цей peer (розділ 5).