# FRR OSPF — приклади конфігурації для mesh WireGuard + кластер k3s

**Поточний стан:** у OSPF беруть участь **чотири вузли** — Amper master, Amper worker, Syhiv17, VRN625. Ноди **macmini7** та **beelinkeqr5** мають WireGuard-тунелі до Amper (wg2/wg3), але **не запускають OSPF** — вони підключені до роутерів Syhiv17 та VRN625, які забезпечують маршрутизацію до них (див. **Syhiv OSPF.pdf**). Нижче — приклади для Area 0 (backbone); розділи 3.3 та 3.4 (macmini7, beelinkeqr5) — на випадок, якщо вони колись увійдуть в OSPF.

---

## 1. Топологія (з реальних конфігурацій WG)

**Ключове:** на **master-node** усі тунелі в діапазоні **192.168.100.x/30** (wg0–wg3). На **work-node** усі тунелі в **192.168.200.x/30** (wg0–wg3). Між master і worker **немає прямого WG-тунелю** — це два окремі OCI VMs; OSPF-зв'язність між ними відбувається **транзитно** через Syhiv17 та VRN625 (зараз лише ці чотири вузли в OSPF). Це **не є проблемою** для повного mesh — див. **OSPF_MASTER_WORKER_NO_DIRECT_LINK.md**. Роутери: Syhiv17 (45.12.26.162) — master wg0, worker wg0; VRN625 (178.136.42.156) — master wg1, worker wg1. Ноди macmini7 (192.168.**2**.19, за VRN625) та beelinkeqr5 (192.168.**1**.19, за Syhiv17) мають WG-тунелі до Amper (wg2/wg3), але **не в OSPF** — маршрутизація до них забезпечується роутерами.

| Пристрій | Роль | LAN / OCI | 192.168.100.x/30 | 192.168.200.x/30 |
| ---------- | ------ | ----------- | ------------------- | ------------------- |
| **master-node** | k3s master | 10.0.10.10 (141.144.254.42) | wg0 .1/30 Syhiv17, wg1 .5/30 VRN625, wg2 .9/30 macmini7, wg3 .13/30 beelinkeqr5 | — |
| **work-node** | k3s worker | 10.0.10.20 (141.147.58.119) | — | wg0 .1/30 Syhiv17, wg1 .5/30 VRN625, wg2 .9/30 macmini7, wg3 .13/30 beelinkeqr5 |
| **VRN625** (Vernadskogo25) | роутер | 192.168.2.1/24 | wgclt1 → master:51821 | wgclt2 → worker:51823 |
| **Syhiv17** (Syhiv17-25) | роутер | 192.168.1.1/24 | wgclt1 → master:51820 | wgclt2 → worker:51822 |
| **macmini7** | k3s master | **192.168.2.19**/24 (VRN625) | wg0 .10/30 → master:51824 (wg2) | wg1 .10/30 → worker:51825 (wg2) |
| **beelinkeqr5** | k3s master | **192.168.1.19**/24 (Syhiv17) | wg0 .14/30 → master:51826 (wg3) | wg1 .14/30 → worker:51827 (wg3) |

**Порти master-node:** wg0 51820, wg1 51821, wg2 51824, wg3 51826.  
**Порти work-node:** wg0 51822, wg1 51823, wg2 51825, wg3 51827.

**Підмережі /30:**

- **192.168.100.0/30** — master wg0 .1 ↔ Syhiv17 (wgclt1)
- **192.168.100.4/30** — master wg1 .5 ↔ VRN625 (wgclt1)
- **192.168.100.8/30** — master wg2 .9 ↔ macmini7 wg0 .10 (master:51824)
- **192.168.100.12/30** — master wg3 .13 ↔ beelinkeqr5 wg0 .14 (master:51826)
- **192.168.200.0/30** — work wg0 .1 ↔ Syhiv17 (wgclt2)
- **192.168.200.4/30** — work wg1 .5 ↔ VRN625 (wgclt2)
- **192.168.200.8/30** — work wg2 .9 ↔ macmini7 wg1 .10 (worker:51825)
- **192.168.200.12/30** — work wg3 .13 ↔ beelinkeqr5 wg1 .14 (worker:51827)  

**Мережі для OSPF Area 0:** 10.0.10.0/24, 192.168.100.0/24, 192.168.200.0/24 та **хости /32** (192.168.1.1, 192.168.2.1, 192.168.2.31, 192.168.2.198 тощо — оголошують роутери; див. **OSPF_ROUTERS_HOST_ROUTES_32.md**). Мереж 192.168.1.0/24 та 192.168.2.0/24 **не** оголошують — лише /32. Розділи 3.3 та 3.4 — для варіанту, коли macmini7/beelinkeqr5 теж увійдуть в OSPF.

**WireGuard і OSPF:** додавати **224.0.0.5/32, 224.0.0.6/32** у AllowedIPs на **всіх** wg* на одному хості **не можна** — виникає конфлікт маршрутів. Замість multicast використовуйте **unicast**: у FRR задайте тип мережі **point-to-multipoint non-broadcast** на WG-інтерфейсах і сусідів **під router ospf** командою **neighbor A.B.C.D** (див. розділ 5.1 і [FRR OSPFv2](https://docs.frrouting.org/en/latest/ospfd.html)). На Amper також потрібні правила iptables FORWARD між wg0/wg1 та wg2/wg3 — див. **WIREGUARD_IPTABLES_HELPER_ANALYSIS.md**.

### 1.1 WireGuard Table = off: маршрути тільки з FRR/OSPF

За замовчуванням **wg-quick** за **AllowedIPs** додає маршрути в основну таблицю маршрутизації. У нашій топології **джерелом маршрутів** має бути **FRR/OSPF**, а не WireGuard.

- **Table = off** (у секції `[Interface]` у конфігу WG): **wg-quick не додає** жодних маршрутів у таблицю. Таблицю заповнює лише FRR (zebra) з OSPF.
- **AllowedIPs** у кожному `[Peer]` **залишаються обов'язковими**: вони задають, **який трафік** модуль WireGuard шифрує і відправляє якому peer. Це не маршрути, а критерій «ці префікси йдуть у цей тунель».
- Послідовність: ядро обирає маршрут з таблиці (наприклад, 10.0.10.10/32 via 192.168.100.9 dev wg0) → пакет потрапляє на wg0 → WireGuard перевіряє AllowedIPs для peer з 192.168.100.9 → шифрує і відправляє. Якщо в AllowedIPs цього peer немає 10.0.10.10/32, трафік не буде зашифрований для цього peer.

**Висновок:** на хостах Ubuntu з FRR доцільно вказати **Table = off** у всіх WG-інтерфейсах і в **AllowedIPs** перерахувати **усі підмережі, які доступні в OSPF** (ті самі, що оголошуються в Area 0: 10.0.10.0/24, 192.168.100.0/24, 192.168.200.0/24 та хости /32 — 192.168.1.19/32, 192.168.2.19/32 тощо; мереж 192.168.1.0/24 та 192.168.2.0/24 не оголошують, див. OSPF_ROUTERS_HOST_ROUTES_32.md). Приклади конфігів з **Table = off** і списком AllowedIPs під OSPF — у **WIREGUARD_CLIENT_CONFIG_MACMINI_BEELINK.md** (розділ про Table = off).

---

## 2. Встановлення FRR (Ubuntu / вузли OSPF)

На **Amper master** та **Amper worker** (Ubuntu). Роутери Syhiv17 та VRN625 вже мають OSPF (UniFi/FRR). *Якщо колись підключатимете macmini7/beelinkeqr5 до OSPF — FRR ставити й там.*

```bash
sudo apt update
sudo apt install -y frr
sudo sed -i 's/^bgpd=no/bgpd=no/' /etc/frr/daemons
sudo sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
sudo sed -i 's/^zebra=no/zebra=yes/' /etc/frr/daemons
sudo systemctl enable frr
sudo systemctl restart frr
```

Перевірка:

```bash
sudo vtysh -c "show running-config"
```

Конфігурацію змінюють через `vtysh` або правленням `/etc/frr/frr.conf` і перезапуском/релоадом FRR.

---

## 3. Приклади конфігурації FRR по пристроях

Усі приклади — **Area 0** (backbone). Імена інтерфейсів (eth0, enp0s6, wg0, wg1, wg2, wg3) потрібно підставити під фактичні на кожному хості.

### 3.1 master-node (Amper master, OCI 10.0.10.10)

**Router ID:** 0.0.0.1. На master-node **лише 192.168.100.x** (wg0–wg3); інтерфейсів 192.168.200.x немає.

```bash
sudo vtysh
```

```vtysh
configure terminal
hostname master-node
ip forwarding
router ospf
 router-id 0.0.0.1
 network 10.0.10.0/24 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
 passive-interface default
 no passive-interface eth0
 no passive-interface wg0
 no passive-interface wg1
 no passive-interface wg2
 no passive-interface wg3
exit
exit
write memory
exit
```

Фрагмент **/etc/frr/frr.conf**:

```conf
router ospf
 router-id 0.0.0.1
 network 10.0.10.0/24 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
 passive-interface default
 no passive-interface eth0
 no passive-interface wg0
 no passive-interface wg1
 no passive-interface wg2
 no passive-interface wg3
```

Якщо основний інтерфейс OCI — `enp0s6`, замініть `eth0` на `enp0s6`.

---

### 3.2 Amper worker (k3s worker, OCI 10.0.10.20)

**Router ID:** 0.0.0.2. На work-node лише **192.168.200.x** (wg0–wg3); 192.168.100.x немає.

```vtysh
configure terminal
hostname amper-worker
ip forwarding
router ospf
 router-id 0.0.0.2
 network 10.0.10.0/24 area 0.0.0.0
 network 192.168.200.0/24 area 0.0.0.0
 passive-interface default
 no passive-interface eth0
 no passive-interface wg0
 no passive-interface wg1
 no passive-interface wg2
 no passive-interface wg3
exit
exit
write memory
exit
```

Інтерфейс OCI за потреби замініть на `enp0s6` або інший.

---

### 3.3 macmini7 (k3s master, LAN 192.168.2.19, VRN625) — *опційно, зараз не в OSPF*

**Зараз** macmini7 не бере участі в OSPF; маршрутизація до нього — через VRN625. Якщо колись увійде в OSPF: **Router ID** 0.0.0.5. OSPF на wg0, wg1 (тунелі до Amper: master:51824, worker:51825) та **лише хост 192.168.2.19/32** — мережу 192.168.2.0/24 **не** оголошувати (див. **OSPF_ROUTERS_HOST_ROUTES_32.md** — той самий підхід для хостів).

```vtysh
configure terminal
hostname macmini7
ip forwarding
router ospf
 router-id 0.0.0.5
 network 192.168.2.19/32 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
 network 192.168.200.0/24 area 0.0.0.0
 passive-interface default
 no passive-interface eth0
 no passive-interface wg0
 no passive-interface wg1
exit
exit
write memory
exit
```

Ім’я LAN-інтерфейсу замініть на фактичне (наприклад `en0` на macOS — на Ubuntu зазвичай `eth0` або подібне). Щоб у OSPF потрапив лише 192.168.2.19/32, можна замість `network 192.168.2.19/32` використати loopback з цією адресою або redistribute connected з route-map (лише /32) — як на роутерах у **OSPF_ROUTERS_HOST_ROUTES_32.md**.

---

### 3.4 beelinkeqr5 (k3s master, LAN 192.168.1.19, Syhiv17) — *опційно, зараз не в OSPF*

**Зараз** beelinkeqr5 не бере участі в OSPF; маршрутизація до нього — через Syhiv17. Якщо колись увійде в OSPF: **Router ID** 0.0.0.6. Тунелі до Amper: master:51826 (wg0), worker:51827 (wg1). В OSPF оголошувати **лише хост 192.168.1.19/32** — мережу 192.168.1.0/24 **не** оголошувати.

```vtysh
configure terminal
hostname beelinkeqr5
ip forwarding
router ospf
 router-id 0.0.0.6
 network 192.168.1.19/32 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
 network 192.168.200.0/24 area 0.0.0.0
 passive-interface default
 no passive-interface eth0
 no passive-interface wg0
 no passive-interface wg1
exit
exit
write memory
exit
```

Якщо через `network` не вдається оголосити лише /32 (інтерфейс у підмережі /24), використати loopback з 192.168.1.19/32 та `network 192.168.1.19/32 area 0` або redistribute connected з route-map (лише 192.168.1.19/32) — аналогічно **OSPF_ROUTERS_HOST_ROUTES_32.md**.

---

### 3.5 VRN625 (роутер, LAN 192.168.2.1, wgclt1/wgclt2)

**Router ID:** 0.0.0.3. Endpoint master:51821 (wgclt1), worker:51823 (wgclt2). На UCG Ultra OSPF налаштовується через **UniFi Network Application** (Settings → Routing & Firewall → OSPF). Нижче — еквівалент для FRR (якщо на роутері доступний vtysh або імпорт конфігу).

**Важливо:** в OSPF **не** оголошувати мережу 192.168.2.0/24; оголошувати лише хости /32: **192.168.2.1/32**, **192.168.2.31/32**, **192.168.2.198/32**. Повна схема — у **OSPF_ROUTERS_HOST_ROUTES_32.md**.

Потрібно в OSPF Area 0:

- **Не** включати LAN 192.168.2.0/24; лише /32 (див. OSPF_ROUTERS_HOST_ROUTES_32.md).
- Інтерфейси WireGuard (wgclt1, wgclt2) — 192.168.100.0/24, 192.168.200.0/24

**Через UniFi UI (рекомендовано для UCG):**

1. Settings → OSPF (або Routing → OSPF).
2. Увімкнути OSPF, **Router ID** встановити унікальний, наприклад **0.0.0.3**.
3. Додати **Area** з Area ID **0.0.0.0** (backbone).
4. До Area додати лише **/32** (192.168.2.1, 192.168.2.31, 192.168.2.198), якщо UI дозволяє; інакше див. OSPF_ROUTERS_HOST_ROUTES_32.md (ручна правка FRR).
5. WireGuard-мережі 192.168.100.0/24, 192.168.200.0/24 — як раніше.

**FRR (vtysh) — оголошення лише /32:**

```vtysh
ip prefix-list ROUTERS-HOSTS seq 5 permit 192.168.2.1/32
ip prefix-list ROUTERS-HOSTS seq 10 permit 192.168.2.31/32
ip prefix-list ROUTERS-HOSTS seq 15 permit 192.168.2.198/32
route-map REDIST-ONLY-32 permit 10
 match ip address prefix-list ROUTERS-HOSTS
!
router ospf
 router-id 0.0.0.3
 network 192.168.100.0/24 area 0.0.0.0
 network 192.168.200.0/24 area 0.0.0.0
 redistribute static route-map REDIST-ONLY-32
 redistribute connected route-map REDIST-ONLY-32
 passive-interface default
 no passive-interface wgclt1
 no passive-interface wgclt2
```

Перед цим: статичні маршрути для 192.168.2.31/32 та 192.168.2.198/32 (`ip route 192.168.2.31/32 dev br0` тощо). Детально — **OSPF_ROUTERS_HOST_ROUTES_32.md**.

---

### 3.6 Syhiv17 (роутер, LAN 192.168.1.1, wgclt1/wgclt2)

**Router ID:** 0.0.0.4. Endpoint master:51820 (wgclt1), worker:51822 (wgclt2). Аналогічно VRN625 — через UniFi UI або FRR.

**Важливо:** в OSPF **не** оголошувати мережу 192.168.1.0/24; оголошувати лише хост **192.168.1.1/32**. Детально — **OSPF_ROUTERS_HOST_ROUTES_32.md**.

**UniFi UI:** якщо є опція — вказати лише 192.168.1.1/32 замість 192.168.1.0/24; інакше див. документ вище.

**FRR (vtysh) — оголошення лише 192.168.1.1/32:**

Прибрати `network 192.168.1.0/24`, додати `network 192.168.1.1/32` (адресу 192.168.1.1/32 має мати інтерфейс, наприклад loopback):

```vtysh
router ospf
 router-id 0.0.0.4
 no network 192.168.1.0/24 area 0.0.0.0
 network 192.168.1.1/32 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
 network 192.168.200.0/24 area 0.0.0.0
 passive-interface default
 no passive-interface wgclt1
 no passive-interface wgclt2
```

---

## 4. Альтернатива: оголошення точних підмереж /30

Якщо замість `network 192.168.100.0/24` потрібно оголошувати лише ті підмережі, що реально є на пристрої, можна використати окремі `network` для кожного /30. Приклад для **Amper master** (має лише 192.168.100.x: .1 wg0, .5 wg1, .9 wg2, .13 wg3):

```vtysh
router ospf
 router-id 0.0.0.1
 network 10.0.10.0/24 area 0.0.0.0
 network 192.168.100.0/30 area 0.0.0.0
 network 192.168.100.4/30 area 0.0.0.0
 network 192.168.100.8/30 area 0.0.0.0
 network 192.168.100.12/30 area 0.0.0.0
 passive-interface default
 no passive-interface eth0
 no passive-interface wg0
 no passive-interface wg1
 no passive-interface wg2
 no passive-interface wg3
```

Для **Amper worker** — лише 192.168.200.x/30 (wg0–wg3). На інших пристроях аналогічно: оголошувати лише ті підмережі, які реально є на локальних інтерфейсах.

---

## 5. Перевірка OSPF

На будь-якій ноді з FRR (Ubuntu):

```bash
sudo vtysh -c "show ip ospf neighbor"
sudo vtysh -c "show ip ospf interface"
sudo vtysh -c "show ip route ospf"
```

На UCG — через UniFi: статус OSPF, списки сусідів та маршрутів (якщо інтерфейс це показує).

---

## 5.1 Unicast OSPF по WireGuard: point-to-multipoint non-broadcast + neighbor під router ospf

У [FRR OSPFv2](https://docs.frrouting.org/en/latest/ospfd.html) команда **neighbor A.B.C.D** існує **лише під router ospf** (для NBMA та point-to-multipoint non-broadcast), а не під інтерфейсом. Команди **ip ospf neighbor** під інтерфейсом у FRR немає.

Щоб OSPF слало Hello **unicast** (без 224.0.0.5 у AllowedIPs і без конфлікту маршрутів):

1. На WG-інтерфейсах задати тип мережі **point-to-multipoint non-broadcast** — тоді FRR не використовує multicast і очікує явно заданих сусідів.
2. Під **router ospf** задати **neighbor &lt;IP_сусіда_на_/30&gt;** (опційно **poll-interval**). FRR шле Hello unicast на ці IP; маршрут до них уже є (AllowedIPs /30).

### master-node (192.168.100.x)

```vtysh
configure terminal
interface wg0
 ip ospf network point-to-multipoint non-broadcast
interface wg1
 ip ospf network point-to-multipoint non-broadcast
interface wg2
 ip ospf network point-to-multipoint non-broadcast
interface wg3
 ip ospf network point-to-multipoint non-broadcast
exit
router ospf
 neighbor 192.168.100.2 poll-interval 30
 neighbor 192.168.100.6 poll-interval 30
 neighbor 192.168.100.10 poll-interval 30
 neighbor 192.168.100.14 poll-interval 30
exit
write memory
exit
```

(192.168.100.2 Syhiv17, .6 VRN625, .10 macmini7, .14 beelinkeqr5.)

### work-node (192.168.200.x)

```vtysh
configure terminal
interface wg0
 ip ospf network point-to-multipoint non-broadcast
interface wg1
 ip ospf network point-to-multipoint non-broadcast
interface wg2
 ip ospf network point-to-multipoint non-broadcast
interface wg3
 ip ospf network point-to-multipoint non-broadcast
exit
router ospf
 neighbor 192.168.200.2 poll-interval 30
 neighbor 192.168.200.6 poll-interval 30
 neighbor 192.168.200.10 poll-interval 30
 neighbor 192.168.200.14 poll-interval 30
exit
write memory
exit
```

### macmini7 (wg0 → master, wg1 → worker)

```vtysh
configure terminal
interface wg0
 ip ospf network point-to-multipoint non-broadcast
interface wg1
 ip ospf network point-to-multipoint non-broadcast
exit
router ospf
 neighbor 192.168.100.9 poll-interval 30
 neighbor 192.168.200.9 poll-interval 30
exit
write memory
exit
```

### beelinkeqr5 (wg0 → master, wg1 → worker)

```vtysh
configure terminal
interface wg0
 ip ospf network point-to-multipoint non-broadcast
interface wg1
 ip ospf network point-to-multipoint non-broadcast
exit
router ospf
 neighbor 192.168.100.13 poll-interval 30
 neighbor 192.168.200.13 poll-interval 30
exit
write memory
exit
```

### Роутери (VRN625, Syhiv17)

Як у вашому варіанті: **neighbor** лише під **router ospf**, на інтерфейсах — **ip ospf network point-to-multipoint non-broadcast** (або point-to-point, якщо на UniFi немає ptmp-nb). Приклад VRN625:

```vtysh
router ospf
 neighbor 192.168.100.5 poll-interval 30
 neighbor 192.168.200.5 poll-interval 30
exit
```

Syhiv17: `neighbor 192.168.100.1`, `neighbor 192.168.200.1` (Amper на wg0). На UniFi через UI — якщо є тип мережі «point-to-multipoint non-broadcast» та список neighbor, задати їх; інакше залишити поточний варіант (neighbor під router ospf).

---

## 6. Зведена таблиця Router ID та мереж

| Пристрій     | Router ID | Мережі в OSPF Area 0 |
|--------------|-----------|------------------------ | 
| Amper master | 0.0.0.1   | 10.0.10.0/24, 192.168.100.0/24 |
| Amper worker | 0.0.0.2   | 10.0.10.0/24, 192.168.200.0/24 |
| VRN625       | 0.0.0.3   | 192.168.2.0/24, 192.168.100.0/24, 192.168.200.0/24 |
| Syhiv17      | 0.0.0.4   | 192.168.1.0/24, 192.168.100.0/24, 192.168.200.0/24 |
| macmini7     | 0.0.0.5   | 192.168.2.19/32, 192.168.100.0/24, 192.168.200.0/24 |
| beelinkeqr5  | 0.0.0.6   | 192.168.1.19/32, 192.168.100.0/24, 192.168.200.0/24 |

**Поточний OSPF:** лише **4 вузли** — Amper master, Amper worker, VRN625, Syhiv17. macmini7 та beelinkeqr5 мають WireGuard (wg2/wg3), але **не в OSPF**; маршрутизація до них забезпечується роутерами. У таблиці вони — на випадок подальшого включення в OSPF. Роутери оголошують лише /32 (див. **OSPF_ROUTERS_HOST_ROUTES_32.md**).

Після встановлення сусідства (Full) між усіма парами на спільних мережах у кожного роутера з’явиться повна картина маршрутів до 10.0.10.0/24, хостів /32 (192.168.1.1, 192.168.1.19, 192.168.2.1, 192.168.2.19, 192.168.2.31, 192.168.2.198 тощо) та тунельних підмереж, що відповідає mesh WireGuard + OSPF. Фінальна діаграма OSPF-зв'язності — **Syhiv OSPF.pdf** (у корені репозиторію k3s); детальний аналіз та посилання — **OSPF_DIAGRAM_ANALYSIS_AND_REFERENCES.md**.
