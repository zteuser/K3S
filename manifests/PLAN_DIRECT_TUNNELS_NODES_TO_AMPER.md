# План: прямий тунелі нод (macmini7, beelinkeqr5) ↔ Amper (master, worker)

Трафік кластера k3s між хостами **macmini7** (192.168.2.19), **beelinkeqr5** (192.168.1.19) та Amper (10.0.10.10, 10.0.10.20) йде **напряму** по WireGuard-тунелях **між нодами**, без участі роутерів VRN625/Syhiv17. У такій схемі **NAT на роутерах не застосовується** до цього трафіку — source IP залишаються 192.168.2.19 та 192.168.1.19, повна зв’язність між нодами зберігається, у **tls-san** достатньо лише LAN-адрес.

---

## 1. Ідея схеми

| Поточна схема | Нова схема (прямі тунелі) |
|---------------|----------------------------|
| macmini7 → шлюз 192.168.2.1 (VRN625) → WG на роутері → Amper | macmini7 → **власний WG-клієнт** → Amper master/worker |
| beelinkeqr5 → шлюз 192.168.1.1 (Syhiv17) → WG на роутері → Amper | beelinkeqr5 → **власний WG-клієнт** → Amper master/worker |
| Source IP на приймачі = тунель роутера (192.168.100.6, 192.168.100.2) | Source IP = **192.168.2.19**, **192.168.1.19** (без NAT) |

**Що робимо:**

- На **macmini7** і **beelinkeqr5** піднімаємо **WireGuard** з двома peer (Amper master і Amper worker). AllowedIPs = 10.0.10.0/24 та мережа іншого хоста (192.168.1.0/24 для macmini7, 192.168.2.0/24 для beelinkeqr5).
- На **Amper master** і **Amper worker** — **два окремі WG-інтерфейси:**
  - **wg2** — один peer: **macmini7** (AllowedIPs 192.168.2.0/24). Маршрут до 192.168.2.0/24 йде лише через wg2.
  - **wg3** — один peer: **beelinkeqr5** (AllowedIPs 192.168.1.0/24). Маршрут до 192.168.1.0/24 йде лише через wg3.
- Маршрутизація на Amper однозначна: 192.168.2.0/24 → wg2, 192.168.1.0/24 → wg3. Трафік macmini7 ↔ beelinkeqr5 йде через Amper (forward між wg2 і wg3).
- Для wg2 і wg3 потрібні **iptables**: дозволити INPUT на wg2/wg3 і **FORWARD** між wg2, wg3 та eth0 (LAN Amper), а також між wg2 і wg3. **Без NAT** для цих інтерфейсів.

Роутери VRN625/Syhiv17 і їх WG-клієнти можна залишити для інших цілей або вимкнути; для k3s використовуємо лише ці прямі тунелі.

---

## 2. Топологія та адресація

**Мережі:**

- 10.0.10.0/24 — Amper (master 10.0.10.10, worker 10.0.10.20). Інтерфейс на Amper — **eth0** або **enp0s6** (потрібно підставити фактичний).
- 192.168.2.0/24 — LAN macmini7 (шлюз VRN625 192.168.2.1).
- 192.168.1.0/24 — LAN beelinkeqr5 (шлюз Syhiv17 192.168.1.1).

**Два WG-інтерфейси на кожному Amper:**

| Інтерфейс | Призначення | Amper master (порт) | Amper worker (порт) |
|-----------|-------------|----------------------|----------------------|
| **wg2** | Тільки macmini7 (192.168.2.0/24) | ListenPort **51824** | ListenPort **51825** |
| **wg3** | Тільки beelinkeqr5 (192.168.1.0/24) | ListenPort **51826** | ListenPort **51827** |

Публічні IP Amper: master **141.144.254.42**, worker **141.147.58.119**.

**Маршрутизація на Amper:**

- 192.168.2.0/24 → інтерфейс **wg2** (з’являється з AllowedIPs peer macmini7).
- 192.168.1.0/24 → інтерфейс **wg3** (з’являється з AllowedIPs peer beelinkeqr5).

Один інтерфейс — один peer, однозначне відповідність мережа ↔ інтерфейс.

**Тунельні адреси (мінімально):** на кожному WG-інтерфейсі одна адреса для коректної роботи (наприклад wg2: 10.20.0.1/32 на master, 10.20.0.3/32 на worker; wg3: 10.20.0.2/32 на master, 10.20.0.4/32 на worker). На macmini7 і beelinkeqr5 — одна адреса на їхній WG-інтерфейс (наприклад 10.20.0.10/32, 10.20.0.11/32).

---

## 3. Конфігурація по пристроях

### 3.1 Amper master — два інтерфейси wg2 (macmini7) і wg3 (beelinkeqr5)

**Файл `/etc/wireguard/wg2.conf`** — тільки macmini7:

```ini
[Interface]
Address = 10.20.0.1/32
ListenPort = 51824
PrivateKey = <приватний_ключ_Amper_master_wg2>

[Peer]
PublicKey = <публічний_ключ_macmini7>
AllowedIPs = 192.168.2.0/24
```

**Файл `/etc/wireguard/wg3.conf`** — тільки beelinkeqr5:

```ini
[Interface]
Address = 10.20.0.2/32
ListenPort = 51826
PrivateKey = <приватний_ключ_Amper_master_wg3>

[Peer]
PublicKey = <публічний_ключ_beelinkeqr5>
AllowedIPs = 192.168.1.0/24
```

**Маршрутизація:** 192.168.2.0/24 з’являється через AllowedIPs на wg2 → трафік до macmini7 йде в wg2. 192.168.1.0/24 через wg3 → трафік до beelinkeqr5 йде в wg3. **NAT для wg2/wg3 не вмикати** — лише forward.

### 3.2 Amper worker — два інтерфейси wg2 і wg3

**`/etc/wireguard/wg2.conf`** (macmini7):

```ini
[Interface]
Address = 10.20.0.3/32
ListenPort = 51825
PrivateKey = <приватний_ключ_Amper_worker_wg2>

[Peer]
PublicKey = <публічний_ключ_macmini7>
AllowedIPs = 192.168.2.0/24
```

**`/etc/wireguard/wg3.conf`** (beelinkeqr5):

```ini
[Interface]
Address = 10.20.0.4/32
ListenPort = 51827
PrivateKey = <приватний_ключ_Amper_worker_wg3>

[Peer]
PublicKey = <публічний_ключ_beelinkeqr5>
AllowedIPs = 192.168.1.0/24
```

### 3.3 macmini7 — WG-клієнт до Amper (інтерфейси wg2 на master і worker)

Один WG-інтерфейс, **два peer** — обидва це **wg2** на Amper (різні endpoint: master :51824, worker :51825). Трафік до 10.0.10.0/24 та 192.168.1.0/24 йде в тунель.

```ini
[Interface]
PrivateKey = <приватний_ключ_macmini7>
Address = 10.20.0.10/32

[Peer]
PublicKey = <публічний_ключ_Amper_master_wg2>
Endpoint = 141.144.254.42:51824
AllowedIPs = 10.0.10.0/24, 192.168.1.0/24
PersistentKeepalive = 25

[Peer]
PublicKey = <публічний_ключ_Amper_worker_wg2>
Endpoint = 141.147.58.119:51825
AllowedIPs = 10.0.10.0/24, 192.168.1.0/24
PersistentKeepalive = 25
```

### 3.4 beelinkeqr5 — WG-клієнт до Amper (інтерфейси wg3 на master і worker)

Один WG-інтерфейс, два peer — обидва **wg3** на Amper (master :51826, worker :51827).

```ini
[Interface]
PrivateKey = <приватний_ключ_beelinkeqr5>
Address = 10.20.0.11/32

[Peer]
PublicKey = <публічний_ключ_Amper_master_wg3>
Endpoint = 141.144.254.42:51826
AllowedIPs = 10.0.10.0/24, 192.168.2.0/24
PersistentKeepalive = 25

[Peer]
PublicKey = <публічний_ключ_Amper_worker_wg3>
Endpoint = 141.147.58.119:51827
AllowedIPs = 10.0.10.0/24, 192.168.2.0/24
PersistentKeepalive = 25
```

---

## 4. Ключі та підготовка

Згенерувати **окремі** пари ключів для:

- Amper master **wg2**, Amper master **wg3**,
- Amper worker **wg2**, Amper worker **wg3**,
- **macmini7**, **beelinkeqr5**.

На кожному пристрої: `wg genkey | tee privatekey | wg pubkey > publickey`. Публічні ключі розподілити згідно з конфігами вище (macmini7 підключається до wg2 на обох Amper, beelinkeqr5 — до wg3).

---

## 5. Firewall на Amper (UDP-порти)

На master і worker відкрити **UDP** для wg2 і wg3:

| Хост | Порт | Інтерфейс |
|------|------|-----------|
| Amper master | **51824** | wg2 (macmini7) |
| Amper master | **51826** | wg3 (beelinkeqr5) |
| Amper worker | **51825** | wg2 (macmini7) |
| Amper worker | **51827** | wg3 (beelinkeqr5) |

Перевірка: з macmini7 `nc -vzu 141.144.254.42 51824`, з beelinkeqr5 `nc -vzu 141.144.254.42 51826`, аналогічно для worker.

---

## 6. iptables на Amper (wg2, wg3) — INPUT і FORWARD

**IP forwarding** має бути увімкнено: `sysctl -w net.ipv4.ip_forward=1` (або в `/etc/sysctl.conf`).

Правила **iptables** дозволяють приймати трафік на wg2/wg3 і **форвардити** його між wg2, wg3 та основним інтерфейсом (eth0 / enp0s6), а також **між wg2 і wg3** (трафік macmini7 ↔ beelinkeqr5 через Amper). **NAT для wg2/wg3 не робити.**

Нижче — імена інтерфейсів: **IN_FACE** — основний інтерфейс Amper (eth0 або enp0s6), **wg2**, **wg3**. Підставити фактичні назви.

### 6.1 Правила (однаково для Amper master і worker)

```bash
# Змінні — підставити фактичний основний інтерфейс (наприклад enp0s6)
IN_FACE="enp0s6"

# INPUT — дозволити вхід на wg2 і wg3
iptables -I INPUT 1 -i wg2 -j ACCEPT
iptables -I INPUT 1 -i wg3 -j ACCEPT

# FORWARD — дозволити forward між wg2/wg3 і основним інтерфейсом (10.0.10.0/24)
iptables -I FORWARD 1 -i wg2 -o $IN_FACE -j ACCEPT
iptables -I FORWARD 1 -i $IN_FACE -o wg2 -j ACCEPT
iptables -I FORWARD 1 -i wg3 -o $IN_FACE -j ACCEPT
iptables -I FORWARD 1 -i $IN_FACE -o wg3 -j ACCEPT

# FORWARD — дозволити forward між wg2 і wg3 (трафік macmini7 ↔ beelinkeqr5 через Amper)
iptables -I FORWARD 1 -i wg2 -o wg3 -j ACCEPT
iptables -I FORWARD 1 -i wg3 -o wg2 -j ACCEPT
```

### 6.2 PostUp / PostDown у конфігах WireGuard (опційно)

Щоб правила застосовувались при піднятті інтерфейсу і прибирались при опусканні, можна додати в **обидва** файли wg2.conf і wg3.conf на Amper:

```ini
# У [Interface] для wg2.conf (приклад для master)
PostUp = iptables -I INPUT 1 -i wg2 -j ACCEPT; iptables -I FORWARD 1 -i wg2 -o enp0s6 -j ACCEPT; iptables -I FORWARD 1 -i enp0s6 -o wg2 -j ACCEPT; iptables -I FORWARD 1 -i wg2 -o wg3 -j ACCEPT; iptables -I FORWARD 1 -i wg3 -o wg2 -j ACCEPT
PostDown = iptables -D INPUT -i wg2 -j ACCEPT; iptables -D FORWARD -i wg2 -o enp0s6 -j ACCEPT; iptables -D FORWARD -i enp0s6 -o wg2 -j ACCEPT; iptables -D FORWARD -i wg2 -o wg3 -j ACCEPT; iptables -D FORWARD -i wg3 -o wg2 -j ACCEPT
```

Для wg3.conf — аналогічно, замінити wg2 на wg3 у правилах для wg3 (INPUT -i wg3, FORWARD з wg3). **Важливо:** PostUp для wg2 додає forward wg2↔wg3; PostUp для wg3 теж може додавати wg3↔wg2 — тоді достатньо один раз додати forward між wg2 і wg3 (наприклад тільки в PostUp wg2). Щоб уникнути дублювання, краще винести всі правила в окремий скрипт і викликати його після підняття обох wg2 і wg3.

**Простіший варіант:** один раз вручну або з systemd/скрипта застосувати правила з п. 6.1 після старту wg2 і wg3; PostUp/PostDown не обов’язкові.

### 6.3 Маршрутизація на Amper

- 192.168.2.0/24 — через **wg2** (з AllowedIPs peer macmini7).
- 192.168.1.0/24 — через **wg3** (з AllowedIPs peer beelinkeqr5).

Додаткових статичних маршрутів не потрібно — WireGuard додає їх з AllowedIPs.

---

## 7. k3s та tls-san

Після введення прямих тунелів трафік між нодами йде з source IP **192.168.2.19** та **192.168.1.19** (і 10.0.10.10, 10.0.10.20). Тунельні адреси роутерів (192.168.100.x) в цьому трафіку **не з’являються**.

У **`/etc/rancher/k3s/config.yaml`** на усіх control-plane нодах достатньо:

- **tls-san:** лише **10.0.10.10**, **192.168.2.19**, **192.168.1.19** (тунельні 192.168.100.x не потрібні).
- **Peer URL etcd:** як і раніше https://10.0.10.10:2380, https://192.168.2.19:2380, https://192.168.1.19:2380.

Node IP (InternalIP) залишаються 10.0.10.10, 10.0.10.20, 192.168.2.19, 192.168.1.19.

---

## 8. Порядок впровадження

1. **Ключі:** згенерувати шість пар ключів (Amper master wg2, wg3; Amper worker wg2, wg3; macmini7; beelinkeqr5) і розподілити публічні ключі згідно з конфігами.
2. **Amper master:** створити `/etc/wireguard/wg2.conf` і `/etc/wireguard/wg3.conf`, відкрити UDP 51824 і 51826, увімкнути `net.ipv4.ip_forward=1`, застосувати **iptables** (п. 6.1), запустити `wg-quick up wg2`, `wg-quick up wg3`.
3. **Amper worker:** аналогічно wg2.conf і wg3.conf, порти 51825 і 51827, iptables, `wg-quick up wg2`, `wg-quick up wg3`.
4. **macmini7:** встановити WireGuard, додати конфіг з двома peer (Amper master :51824, worker :51825 — обидва wg2), підняти інтерфейс.
5. **beelinkeqr5:** конфіг з двома peer (Amper master :51826, worker :51827 — обидва wg3), підняти інтерфейс.
6. **Перевірка зв’язності:** з macmini7 `ping 10.0.10.10`, `ping 192.168.1.19`; з beelinkeqr5 `ping 10.0.10.10`, `ping 192.168.2.19`; з Amper master `ping 192.168.2.19`, `ping 192.168.1.19`. Усі мають відповідати.
7. **k3s:** оновити config.yaml на усіх control-plane — прибрати tls-san з 192.168.100.x, залишити лише 10.0.10.10, 192.168.2.19, 192.168.1.19. Перезапустити k3s.
8. **Роутери:** існуючі WG-клієнти на VRN625/Syhiv17 можна залишити або вимкнути.

---

## 9. Відкат

- На macmini7 і beelinkeqr5 вимкнути WG-інтерфейс.
- На Amper master і worker: `wg-quick down wg2`, `wg-quick down wg3`; прибрати правила iptables для wg2/wg3 (якщо додавались вручну — видалити їх у зворотному порядку).
- Повернути доступ через роутери (WG на VRN625/Syhiv17) і в config.yaml k3s повернути **tls-san** з тунельними IP згідно з [PLAN_NETWORK_AND_REBUILD_CONTROL_PLANE.md](PLAN_NETWORK_AND_REBUILD_CONTROL_PLANE.md).

---

## 10. Підсумок

| Елемент | Дія |
|--------|-----|
| **macmini7** | WG-клієнт, 2 peer (Amper master **wg2** :51824, worker **wg2** :51825), AllowedIPs 10.0.10.0/24, 192.168.1.0/24 |
| **beelinkeqr5** | WG-клієнт, 2 peer (Amper master **wg3** :51826, worker **wg3** :51827), AllowedIPs 10.0.10.0/24, 192.168.2.0/24 |
| **Amper master** | **wg2** (ListenPort 51824) — тільки macmini7, 192.168.2.0/24. **wg3** (ListenPort 51826) — тільки beelinkeqr5, 192.168.1.0/24. iptables: INPUT + FORWARD для wg2, wg3 (wg2↔eth0, wg3↔eth0, wg2↔wg3). Без NAT. |
| **Amper worker** | **wg2** (51825) — macmini7. **wg3** (51827) — beelinkeqr5. Ті самі iptables. |
| **Маршрутизація на Amper** | 192.168.2.0/24 → wg2, 192.168.1.0/24 → wg3 (однозначно по інтерфейсах). |
| **k3s tls-san** | Тільки 10.0.10.10, 192.168.2.19, 192.168.1.19 |
| **Роутери VRN625/Syhiv17** | Не задіяні в трафіку кластера; WG на них опційно залишити або вимкнути |

Посилання: [PLAN_NETWORK_AND_REBUILD_CONTROL_PLANE.md](PLAN_NETWORK_AND_REBUILD_CONTROL_PLANE.md), [WIREGUARD_ANALYSIS.md](WIREGUARD_ANALYSIS.md).
