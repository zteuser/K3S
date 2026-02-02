# План «Повна заміна»: WireGuard → site-to-site IPsec

---

## ⚠️ Обмеження: роутери за CGNAT

**Роутери VRN625 та Syhiv17 не мають виділеної публічної інтернет-адреси і знаходяться за CGNAT (Carrier-Grade NAT).**

У такій ситуації **класичний site-to-site IPsec не підходить**: для нього потрібно, щоб хоча б одна сторона (а краще обидві) мала сталу публічну IP, до якої можна ініціювати з’єднання. За CGNAT роутери можуть лише **виходити** у інтернет; зовнішній сервер (Amper) не може до них з’єднатися за сталим адресом, а в ряді випадків обидва роутери виглядають з інтернету як одна й та сама CGNAT-адреса — тоді розрізнити два тунелі на стороні Amper неможливо.

**Рекомендація:** залишити **WireGuard** і використовувати план мережі та перебудови control plane з **tls-san** для тунельних IP: [PLAN_NETWORK_AND_REBUILD_CONTROL_PLANE.md](PLAN_NETWORK_AND_REBUILD_CONTROL_PLANE.md). План «Повна заміна» на IPsec нижче збережено лише для випадків, коли у майбутньому з’явиться виділена публічна IP для роутерів (наприклад, окремий інтернет-канал або статична IP у провайдера).

---

Покроковий план повної заміни VPN з WireGuard на site-to-site IPsec (застосовується лише якщо роутери мають публічні IP). Під час міграції кластер k3s буде недоступний до завершення налаштування IPsec та перезапуску з новим config.yaml.

**Топологія після заміни:** один IPsec-шлюз — **Amper master** (10.0.10.10, публічна IP 141.144.254.42). VRN625 та Syhiv17 підключаються до нього двома окремими site-to-site тунелями. Маршрути: 192.168.2.0/24 ↔ 10.0.10.0/24, 192.168.1.0/24 ↔ 10.0.10.0/24 (і між собою через Amper, якщо потрібно — через маршрутизацію на master).

**Публічні IP (приклад, якщо вони є):** Amper master 141.144.254.42, VRN625 178.136.42.156, Syhiv17 45.12.26.162. За CGNAT ці адреси для роутерів не виділені і можуть бути спільними для багатьох абонентів.

---

## Фаза 0. Підготовка (до дня міграції)

### 0.1 Бекапи та знімки

- [ ] **Unifi Controller:** експорт налаштувань (Settings → Backup).
- [ ] **VRN625, Syhiv17:** скріншоти/експорт WireGuard та мережевих налаштувань.
- [ ] **Amper master, Amper worker:** копія `/etc/wireguard/`, `wg show` та вивід `ip route` збережені в репо (вже є в wireguard-configs/).
- [ ] **k3s:** бекап etcd (якщо є процедура) або принаймні збережені маніфести та список `kubectl get all -A`.
- [ ] **OCI:** знімок дисків Amper master (або VM) перед змінами.

### 0.2 Параметри IPsec (узгодити один раз)

Записати і використовувати однаково на Unifi та strongswan:

| Параметр | Значення (приклад) |
|----------|---------------------|
| IKE version | IKEv2 |
| Encryption (IKE) | AES-256 |
| Hashing (IKE) | SHA256 |
| DH group | 14 (2048-bit) або 5 |
| Encryption (ESP) | AES-256 |
| Hashing (ESP) | SHA256 |
| PFS | так, DH 14 |
| IKE lifetime | 28800 s |
| ESP lifetime | 3600 s |
| Authentication | Pre-Shared Key (PSK) |

**PSK:** згенерувати безпечний ключ (наприклад `openssl rand -base64 32`) і зберегти в надійному місці. Один PSK для обох conn (VRN625 і Syhiv17) — або окремі PSK на conn.

### 0.3 Вікно та доступ

- [ ] Призначити час міграції (рекомендовано 1–2 години буферу).
- [ ] Переконатися, що є **фізичний або out-of-band доступ** до VRN625 та Syhiv17 (щоб у разі втрати доступу через VPN відновити конфіг).
- [ ] Доступ по SSH до Amper master з інтернету (публічна IP) або через консоль OCI.

---

## Фаза 1. Зупинка кластера та WireGuard

### 1.1 Зупинити k3s на усіх control-plane нодах

Це усуває помилки etcd під час обриву мережі.

- [ ] **Amper master:** `sudo systemctl stop k3s`
- [ ] **macmini7:** `sudo systemctl stop k3s`
- [ ] **beelinkeqr5:** `sudo systemctl stop k3s`
- [ ] **Amper worker (work-node):** `sudo systemctl stop k3s` (опційно, можна пізніше)

### 1.2 Вимкнути WireGuard на роутерах

- [ ] **Unifi Controller** → Gateways → VRN625 → VPN (або Settings → VPN): **вимкнути / видалити** WireGuard Client (wgclt1, wgclt2).
- [ ] **Unifi Controller** → Syhiv17: аналогічно вимкнути WireGuard Client.
- [ ] Перевірити, що маршрути до 10.0.10.0/24 та до іншого LAN (192.168.1.0/24 з боку VRN625, 192.168.2.0/24 з боку Syhiv17) зникли або більше не ведуть у WG (після наступного кроку вони будуть через IPsec).

### 1.3 Вимкнути WireGuard на Amper

- [ ] **Amper master:** `sudo wg-quick down wg0`, `sudo wg-quick down wg1` (або `systemctl stop wg-quick@wg0` тощо).
- [ ] **Amper worker:** аналогічно вимкнути wg0, wg1.
- [ ] Перевірити: `ip addr` — інтерфейсів wg0/wg1 немає (або down).

Після фази 1 між локаціями (VRN625 ↔ Amper, Syhiv17 ↔ Amper) **немає зв’язку** — це очікувано до підняття IPsec.

---

## Фаза 2. Налаштування IPsec на Amper master

### 2.1 Встановити strongswan

На **Amper master** (10.0.10.10):

```bash
sudo apt update
sudo apt install -y strongswan strongswan-pki
```

### 2.2 Конфіг ipsec.conf

Файл: `/etc/ipsec.conf`. Два conn: один для VRN625, один для Syhiv17.

```ini
config setup
    charondebug="ike 2, knl 2, cfg 2"

conn vrn625-to-amper
    left=141.144.254.42
    leftid=141.144.254.42
    leftsubnet=10.0.10.0/24
    leftfirewall=yes
    right=178.136.42.156
    rightsubnet=192.168.2.0/24
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256!
    ikelifetime=28800s
    lifetime=3600s
    keyexchange=ikev2
    authby=secret
    auto=start
    type=tunnel

conn syhiv17-to-amper
    left=141.144.254.42
    leftid=141.144.254.42
    leftsubnet=10.0.10.0/24
    leftfirewall=yes
    right=45.12.26.162
    rightsubnet=192.168.1.0/24
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256!
    ikelifetime=28800s
    lifetime=3600s
    keyexchange=ikev2
    authby=secret
    auto=start
    type=tunnel
```

**Примітка:** якщо Unifi використовує інші алгоритми (наприклад AES-128, SHA1, DH group 5), їх треба узгодити тут і в Unifi.

### 2.3 Секрети ipsec.secrets

Файл: `/etc/ipsec.secrets`. Права `chmod 600`.

```
141.144.254.42 178.136.42.156 : PSK "ваш_PSK_для_VRN625"
141.144.254.42 45.12.26.162   : PSK "ваш_PSK_для_Syhiv17"
```

Або один спільний PSK для обох:

```
141.144.254.42 178.136.42.156 : PSK "спільний_PSK"
141.144.254.42 45.12.26.162   : PSK "спільний_PSK"
```

### 2.4 Firewall на Amper master

Дозволити IKE та ESP з публічної мережі:

```bash
# Приклад для ufw
sudo ufw allow 500/udp comment 'IKE'
sudo ufw allow 4500/udp comment 'IKE NAT-T'
sudo ufw allow proto esp from any
sudo ufw status
```

Якщо використовується iptables напряму — додати правила для UDP 500, UDP 4500, протокол ESP з WAN (enp0s6 або інтерфейс з публічною IP).

### 2.5 Запуск strongswan

```bash
sudo systemctl enable strongswan-starter
sudo systemctl start strongswan-starter
sudo ipsec status
```

Очікується: conn в стані "CONNECTING" або "INSTALLED" після того, як Unifi ініціює з'єднання. Поки роутери не налаштовані на IPsec, conn будуть чекати.

---

## Фаза 3. Налаштування Site-to-Site IPsec на Unifi

### 3.1 VRN625 (Unifi Controller)

- [ ] **Settings** → **VPN** (або **Gateways** → VRN625 → **VPN**) → **Site-to-Site** → **Create**.
- **Name:** наприклад `Amper-master`.
- **Remote IP/Hostname:** `141.144.254.42`.
- **Local subnet(s):** `192.168.2.0/24`.
- **Remote subnet(s):** `10.0.10.0/24`, `192.168.1.0/24` (щоб через тунель бути доступним і до Amper, і до Syhiv17 LAN).
- **Pre-Shared Key:** той самий PSK, що в ipsec.secrets для VRN625.
- **IKE version:** IKEv2.
- **Encryption / Hash / DH:** узгодити з strongswan (наприклад AES-256, SHA256, DH 14).
- **Enable:** увімкнути.

Зберегти. Перевірити в Unifi, що тунель у стані "Connected" (можна зробити після 3.2 і перевірки з обох сторін).

### 3.2 Syhiv17 (Unifi Controller)

- [ ] Аналогічно створити Site-to-Site IPsec:
- **Remote IP/Hostname:** `141.144.254.42`.
- **Local subnet(s):** `192.168.1.0/24`.
- **Remote subnet(s):** `10.0.10.0/24`, `192.168.2.0/24`.
- **Pre-Shared Key:** той самий PSK, що для Syhiv17 у ipsec.secrets.
- **IKE / ESP:** ті самі алгоритми.
- **Enable:** увімкнути.

### 3.3 Перевірка тунелів

- На **Amper master:** `sudo ipsec status` — обидва conn у стані **INSTALLED**.
- У **Unifi** для VRN625 та Syhiv17 — статус VPN "Connected".
- **Ping:** з Amper master `ping 192.168.2.19`, `ping 192.168.1.19`; з macmini7 `ping 10.0.10.10`; з beelinkeqr5 `ping 10.0.10.10`. Усі мають відповідати.
- **Перевірка порту etcd:** з macmini7 `nc -zv 10.0.10.10 2380`; з beelinkeqr5 `nc -zv 10.0.10.10 2380`; з Amper master `nc -zv 192.168.2.19 2380`, `nc -zv 192.168.1.19 2380` (поки k3s зупинений — Connection refused, але порт відкритий або closed — головне, що маршрут є).

---

## Фаза 4. Оновлення k3s config та запуск кластера

### 4.1 config.yaml без тунельних tls-san

На **кожній** control-plane ноді оновити `/etc/rancher/k3s/config.yaml`: прибрати всі рядки **tls-san** з тунельними IP (192.168.100.x, 192.168.200.x). Залишити лише LAN-адреси та, за потреби, node-ip.

**master-node (Amper):**

```yaml
node-ip: 10.0.10.10
tls-san: 10.0.10.10
tls-san: 192.168.2.19
tls-san: 192.168.1.19
# server + token якщо не перший сервер
```

**macmini7:**

```yaml
tls-san: 10.0.10.10
tls-san: 192.168.2.19
tls-san: 192.168.1.19
# server + token
```

**beelinkeqr5:**

```yaml
tls-san: 10.0.10.10
tls-san: 192.168.2.19
tls-san: 192.168.1.19
# server + token
```

(Якщо node-ip не вказано, k3s візьме 192.168.2.19 / 192.168.1.19 з інтерфейсу.)

### 4.2 Порядок запуску k3s

1. [ ] **Amper master:** `sudo systemctl start k3s`, дочекатися `systemctl status k3s` — active.
2. [ ] **macmini7:** `sudo systemctl start k3s`.
3. [ ] **beelinkeqr5:** `sudo systemctl start k3s`.
4. [ ] Перевірити etcd: з master `sudo k3s etcd-snapshot ls` або з будь-якої ноди з KUBECONFIG `kubectl get cs` — etcd Healthy.
5. [ ] **Amper worker:** `sudo systemctl start k3s`.
6. [ ] `kubectl get nodes -o wide` — усі Ready, InternalIP коректні (10.0.10.10, 192.168.2.19, 192.168.1.19, 10.0.10.20).

### 4.3 Перевірка кластера

- [ ] `kubectl get pods -A` — поди в стані Running / Completed.
- [ ] З beelinkeqr5: `nc -zv 192.168.2.19 2380`, `nc -zv 10.0.10.10 2380` — succeeded.
- [ ] В логах k3s на control-plane нодах немає "rejected connection" через TLS.

---

## Фаза 5. Прибирання WireGuard на Amper (опційно)

Після успішної роботи кластера на IPsec можна остаточно прибрати WireGuard з Amper:

- [ ] **Amper master:** вимкнути сервіси wg-quick@wg0, wg-quick@wg1; за бажанням видалити пакет wireguard-tools та конфіги в `/etc/wireguard/`.
- [ ] **Amper worker:** аналогічно. Якщо worker більше не використовується як VPN-сервер, маршрути до 10.0.10.0/24 та між 192.168.2/1.0/24 йдуть лише через master.

---

## Відкат (якщо IPsec не запрацював або потрібно повернутися на WG)

1. Зупинити strongswan на Amper master: `sudo systemctl stop strongswan-starter`.
2. У Unifi вимкнути Site-to-Site IPsec для VRN625 та Syhiv17.
3. На Amper master та worker знову підняти WireGuard: `sudo wg-quick up wg0`, `sudo wg-quick up wg1` (або systemctl start).
4. У Unifi знову увімкнути WireGuard Client (wgclt1, wgclt2) з попередніми конфігами.
5. Відновити в `/etc/rancher/k3s/config.yaml` на всіх control-plane нодах **tls-san** з тунельними IP згідно з PLAN_NETWORK_AND_REBUILD_CONTROL_PLANE.md (розділ 4, 6).
6. Запустити k3s у тому ж порядку: master → macmini7 → beelinkeqr5 → worker.
7. Перевірити кластер.

---

## Чеклист у одному місці

| # | Крок | Виконано |
|---|------|----------|
| 0 | Бекапи, PSK, вікно, доступ | ☐ |
| 1.1 | Зупинити k3s на master, macmini7, beelinkeqr5, work-node | ☐ |
| 1.2 | Вимкнути WG на VRN625 та Syhiv17 (Unifi) | ☐ |
| 1.3 | Вимкнути WG на Amper master та worker | ☐ |
| 2.1–2.5 | strongswan на Amper master: install, ipsec.conf, ipsec.secrets, firewall, start | ☐ |
| 3.1–3.2 | Site-to-Site IPsec на VRN625 та Syhiv17 в Unifi | ☐ |
| 3.3 | Перевірка: ipsec status, ping, nc 2380 | ☐ |
| 4.1 | Оновити config.yaml на всіх control-plane (тільки LAN tls-san) | ☐ |
| 4.2–4.3 | Запустити k3s (master → macmini7 → beelinkeqr5 → worker), перевірити | ☐ |
| 5 | Опційно: прибрати WG з Amper | ☐ |

Посилання: [SITE_TO_SITE_IPSEC_OPTION.md](SITE_TO_SITE_IPSEC_OPTION.md), [PLAN_NETWORK_AND_REBUILD_CONTROL_PLANE.md](PLAN_NETWORK_AND_REBUILD_CONTROL_PLANE.md), [UniFi Site-to-Site IPsec](https://help.ui.com/hc/en-us/articles/7983431932439).
