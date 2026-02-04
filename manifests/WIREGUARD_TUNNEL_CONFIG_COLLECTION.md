# Чому в трафіку кластера з’являються тунельні адреси та збір конфігурації WireGuard

Два питання: (1) чому etcd бачить source IP 192.168.100.x замість LAN‑адрес хостів; (2) як зібрати конфігурацію тунелів з усіх пристроїв для перевірки.

---

## 1. Чому в трафіку між хостами кластера з’являються тунельні адреси?

Трафік між **macmini7** (192.168.2.19) і **beelinkeqr5** (192.168.1.19) або між ними і **Amper** (10.0.10.x) йде не напряму, а **через маршрутизатори** VRN625 та Syhiv17 і далі по **тунелях WG0/WG1**.

- **Маршрутизація:** пакет з macmini7 до 192.168.1.19 йде на шлюз 192.168.2.1 (VRN625). Роутер пересилає його в тунель WG0. На виході з тунелю (на Syhiv17 або Amper) **source IP пакета** залежить від того, чи робить VRN625 **NAT (masquerade)**.
- **Якщо є NAT:** вихідний інтерфейс роутера — wg0 (наприклад 192.168.100.1/30). При masquerade source замінюється на адресу цього інтерфейсу — **192.168.100.1**. Тому приймач (beelinkeqr5 або etcd на іншій ноді) бачить source **192.168.100.1**, а не 192.168.2.19.
- **Якщо NAT немає (чистий routing):** source IP могла б залишатися 192.168.2.19, і тоді тунельні адреси в etcd не з’являлися б.

**Висновок:** поява тунельних адрес (192.168.100.1, 192.168.100.2, …) як source IP означає, що трафік йде через тунелі і на якомусь етапі застосовується **NAT** (або пакет виходить у тунель з адреси інтерфейсу тунелю). Щоб перевірити, чи це очікувана поведінка і чи коректно налаштовані тунелі, потрібно зібрати конфігурацію WG та маршрутизації на всіх чотирьох пристроях.

---

## 2. Пристрої, з яких збирати конфігурацію

| Пристрій | Роль | Де знаходиться | Як збирати конфіг |
| ---------- | ------ | ---------------- | ------------------- |
| **Amper master** | k3s master-node, WG‑сервер | OCI 10.0.10.10 | Linux: `wg`, `/etc/wireguard/` |
| **Amper worker** | k3s work-node, WG‑сервер | OCI 10.0.10.20 | Linux: `wg`, `/etc/wireguard/` |
| **VRN625** | маршрутизатор, WG‑клієнт/сервер | 192.168.2.1 (шлюз macmini7) | Ubiquiti UCG Ultra (Unifi OS): Controller або SSH |
| **Syhiv17** | маршрутизатор, WG‑клієнт/сервер | 192.168.1.1 (шлюз beelinkeqr5) | Ubiquiti UCG Ultra (Unifi OS): Controller або SSH |

Мережі тунелів (з діаграми Syhiv VPN-2.pdf): **192.168.100.0/30**, **192.168.100.4/30** (WG0), **192.168.200.0/30**, **192.168.200.4/30** (WG1). Адреси на тунелях — на роутерах VRN625, Syhiv17 та на хостах Amper (wg0/wg1).

---

## 3. Збір конфігурації WireGuard

### 3.1 Amper master (10.0.10.10)

Це Linux‑хост (Oracle/Amper), на ньому WireGuard зазвичай у вигляді інтерфейсів wg0, wg1.

**SSH на Amper master**, потім:

```bash
# Стан інтерфейсів WireGuard
sudo wg show

# Список конфігів (якщо є)
ls -la /etc/wireguard/

# Вміст конфігів (без приватних ключів у лог — можна замаскувати)
sudo cat /etc/wireguard/wg0.conf 2>/dev/null || true
sudo cat /etc/wireguard/wg1.conf 2>/dev/null || true

# Маршрути (щоб зрозуміти, що йде в тунель)
ip route show
ip addr show wg0 2>/dev/null
ip addr show wg1 2>/dev/null
```

Зберегти вивід у файл, наприклад: `amper-master-wg-$(date +%Y%m%d).txt`.

### 3.2 Amper worker (10.0.10.20)

Аналогічно до Amper master:

```bash
sudo wg show
ls -la /etc/wireguard/
sudo cat /etc/wireguard/wg0.conf 2>/dev/null || true
sudo cat /etc/wireguard/wg1.conf 2>/dev/null || true
ip route show
ip addr show wg0 2>/dev/null
ip addr show wg1 2>/dev/null
```

Зберегти у файл: `amper-worker-wg-$(date +%Y%m%d).txt`.

### 3.3 VRN625 (Ubiquiti UCG Ultra — Unifi OS)

Адреса: **192.168.2.1** (шлюз для macmini7). Модель: **Ubiquiti UCG Ultra** (Unifi Cloud Gateway Ultra), ОС Unifi OS.

**Варіант A — через Unifi Controller (веб):**

1. Увійти в Unifi Controller (Self-Hosted або UniFi Cloud).
2. **Settings** → **Networking** (або **VPN** / **WireGuard**, залежно від версії).
3. Відкрити налаштування **WireGuard** для шлюза VRN625.
4. Зробити скріншоти або експорт конфігурації (якщо є кнопка Export / Show config).
5. Перевірити **Firewall / Traffic rules** та **Routing** для мереж 192.168.2.0/24 та 192.168.100.x, 10.0.10.x — чи є NAT (masquerade/source NAT) на інтерфейс WireGuard.

**Варіант B — через SSH:**

1. Увімкнути SSH на UCG Ultra (Controller → Device → VRN625 → Settings → SSH Authentication).
2. Підключитися: `ssh ubnt@192.168.2.1` (або інший користувач/IP згідно з вашими налаштуваннями).
3. На Unifi OS часто є оболонка `unifi-os shell` або контейнер. Якщо встановлено WireGuard (наприклад, через пакет wireguard‑vyatta‑ubnt):

```bash
# Якщо є CLI Unifi (EdgeRouter-подібний)
show interfaces wireguard

# Або перегляд конфігу
cat /etc/wireguard/wg0.conf 2>/dev/null || true

# Маршрути
ip route show
```

4. Якщо WireGuard керується через Unifi UI, повноцінного wg0.conf у файловій системі може не бути — тоді основний збір через Controller (експорт/скріншоти WireGuard та правил firewall/routing).

**Що зберегти:** скріншоти або експорт WireGuard (peers, allowed IPs, endpoint), правила firewall/NAT для трафіку до 192.168.1.0/24 та 10.0.10.0/24.

### 3.4 Syhiv17 (Ubiquiti UCG Ultra — Unifi OS)

Адреса: **192.168.1.1** (шлюз для beelinkeqr5). Так само UCG Ultra, Unifi OS.

Дії ті самі, що для VRN625:

- **Controller:** Settings → Networking / VPN → WireGuard для шлюза Syhiv17; експорт або скріншоти; перевірити firewall/routing і наявність NAT на WG‑інтерфейс.
- **SSH:** `ssh ubnt@192.168.1.1` (або ваш користувач), потім `show interfaces wireguard` / перегляд маршрутів і конфігу WG, якщо доступно.

Зберегти у файл або документ: `syhiv17-wg-$(date +%Y%m%d).txt` (або скріншоти).

---

## 4. Що перевірити після збору конфігурації

1. **Відповідність діаграмі Syhiv VPN-2.pdf:**
   - WG0: 192.168.100.0/30 та 192.168.100.4/30 — які інтерфейси/пристрої мають які адреси (наприклад .1 — VRN625, .2 — Syhiv17, .5/.6 — Amper master/worker).
   - WG1: 192.168.200.0/30 та 192.168.200.4/30 — аналогічно.

2. **AllowedIPs і маршрути:** чи маршрутизовані 192.168.2.0/24, 192.168.1.0/24, 10.0.10.0/24 через потрібні тунелі (allowed-ips на WG та маршрути на роутерах).

3. **NAT (masquerade / source NAT):** чи включено на роутерах VRN625/Syhiv17 NAT на трафік, що йде в WG‑інтерфейс. Якщо так — саме тому приймач бачить source IP 192.168.100.1 (або .2) замість 192.168.2.19 / 192.168.1.19. Якщо потрібно, щоб etcd бачив справжні LAN‑адреси хостів, можна розглянути вимкнення NAT для трафіку між цими мережами (з урахуванням безпеки та політики мережі).

4. **Endpoint і порти:** на Amper master/worker — listen-port 51820 (wg0), 51821 (wg1); на роутерах — відповідні peer endpoint (141.144.254.42, 141.147.58.119 з вашого бекапу). Переконатися, що порти не блокуються firewall.

---

## 5. Де зберігати зібрані конфіги

Рекомендовано зберегти в одній директорії, наприклад:

- `wireguard-configs/amper-master-wg-YYYYMMDD.txt`
- `wireguard-configs/amper-worker-wg-YYYYMMDD.txt`
- `wireguard-configs/vrn625-wg-YYYYMMDD.txt` (або скріншоти/експорт з Controller)
- `wireguard-configs/syhiv17-wg-YYYYMMDD.txt` (аналогічно)

Після збору можна порівняти allowed-ips, endpoint і маршрути з діаграмою та з’ясувати, чому в трафіку кластера з’являються саме тунельні адреси і чи потрібно змінювати NAT/routing на роутерах.
