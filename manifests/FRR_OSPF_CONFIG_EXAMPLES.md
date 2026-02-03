# FRR OSPF — приклади конфігурації для mesh WireGuard + кластер k3s

OSPF Area 0 (backbone), FRR на нодах кластера (master-node, work-node, macmini7, beelinkeqr5) та роутерах (VRN625 / Vernadskogo25, Syhiv17 / Syhiv17-25). Топологія та адресація взяті з **фактичних конфігурацій WireGuard** на пристроях.

---

## 1. Топологія (з реальних конфігурацій WG)

**Ключове:** на **master-node** усі тунелі в діапазоні **192.168.100.x/30** (wg0–wg3). На **work-node** усі тунелі в **192.168.200.x/30** (wg0–wg3). Роутери: Syhiv17 (45.12.26.162) — master wg0, worker wg0; VRN625 (178.136.42.156) — master wg1, worker wg1. Ноди macmini7 (192.168.**1**.19) та beelinkeqr5 (192.168.**2**.19) підключені до Amper через wg2/wg3 (прямі тунелі або через NAT роутерів).

| Пристрій | Роль | LAN / OCI | 192.168.100.x/30 | 192.168.200.x/30 |
|----------|------|-----------|-------------------|-------------------|
| **master-node** | k3s master | 10.0.10.10 (141.144.254.42) | wg0 .1/30 Syhiv17, wg1 .5/30 VRN625, wg2 .9/30 beelinkeqr5, wg3 .13/30 macmini7 | — |
| **work-node** | k3s worker | 10.0.10.20 (141.147.58.119) | — | wg0 .1/30 Syhiv17, wg1 .5/30 VRN625, wg2 .9/30 beelinkeqr5, wg3 .13/30 macmini7 |
| **VRN625** (Vernadskogo25) | роутер | 192.168.2.1/24 | wgclt1 → master:51821 | wgclt2 → worker:51823 |
| **Syhiv17** (Syhiv17-25) | роутер | 192.168.1.1/24 | wgclt1 → master:51820 | wgclt2 → worker:51822 |
| **macmini7** | k3s master | **192.168.1.19**/24 | wg0 .10/30 → master:51824 (wg2) | wg1 .10/30 → worker:51825 (wg2) |
| **beelinkeqr5** | k3s master | **192.168.2.19**/24 | wg0 .14/30 → master:51826 (wg3) | wg1 .14/30 → worker:51827 (wg3) |

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

**Мережі для OSPF Area 0:** 10.0.10.0/24, 192.168.1.0/24, 192.168.2.0/24, 192.168.100.0/24, 192.168.200.0/24. На кожному пристрої в OSPF оголошуються лише ті з них, які реально є на інтерфейсах (див. розділи по пристроях).

---

## 2. Встановлення FRR (Ubuntu / ноди кластера)

На **Amper master, Amper worker, macmini7, beelinkeqr5** (Ubuntu):

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

### 3.3 macmini7 (k3s master, LAN 192.168.1.19)

**Router ID:** 0.0.0.5. OSPF на LAN-інтерфейсі та на wg0, wg1 (тунелі до Amper: master:51824, worker:51825).

```vtysh
configure terminal
hostname macmini7
ip forwarding
router ospf
 router-id 0.0.0.5
 network 192.168.1.0/24 area 0.0.0.0
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

Ім’я LAN-інтерфейсу замініть на фактичне (наприклад `en0` на macOS — на Ubuntu зазвичай `eth0` або подібне).

---

### 3.4 beelinkeqr5 (k3s master, LAN 192.168.2.19)

**Router ID:** 0.0.0.6. Тунелі до Amper: master:51826 (wg0), worker:51827 (wg1).

```vtysh
configure terminal
hostname beelinkeqr5
ip forwarding
router ospf
 router-id 0.0.0.6
 network 192.168.2.0/24 area 0.0.0.0
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

---

### 3.5 VRN625 (роутер, LAN 192.168.2.1, wgclt1/wgclt2)

**Router ID:** 0.0.0.3. Endpoint master:51821 (wgclt1), worker:51823 (wgclt2). На UCG Ultra OSPF налаштовується через **UniFi Network Application** (Settings → Routing & Firewall → OSPF). Нижче — еквівалент для FRR (якщо на роутері доступний vtysh або імпорт конфігу).

Потрібно в OSPF Area 0:

- Інтерфейс LAN (192.168.2.0/24)
- Інтерфейси WireGuard (wgclt1, wgclt2) — тунелі до master/worker

**Через UniFi UI (рекомендовано для UCG):**

1. Settings → OSPF (або Routing → OSPF).
2. Увімкнути OSPF, **Router ID** встановити унікальний, наприклад **0.0.0.3**.
3. Додати **Area** з Area ID **0.0.0.0** (backbone).
4. До цієї Area додати **interfaces**:
   - мережа LAN (192.168.2.0/24),
   - мережі WireGuard (192.168.100.0/24 та 192.168.200.0/24 або конкретні підмережі, якщо UI дозволяє вибір інтерфейсу).
5. Увімкнути **Redistribute Connected Routes**, щоб локальні підмережі оголошувались в OSPF.
6. Hello/Dead інтервали за замовчуванням (10/40), без passive на інтерфейсах, де очікуються сусіди OSPF.

**Еквівалент у FRR (vtysh), якщо на UCG є доступ до FRR:**

```vtysh
configure terminal
hostname vrn625
ip forwarding
router ospf
 router-id 0.0.0.3
 network 192.168.2.0/24 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
 network 192.168.200.0/24 area 0.0.0.0
 passive-interface default
 no passive-interface <lan_interface>
 no passive-interface wgclt1
 no passive-interface wgclt2
exit
exit
write memory
exit
```

Ім’я LAN-інтерфейсу на UCG підставити згідно з вашою топологією (наприклад br0 або інтерфейс, що має 192.168.2.1).

---

### 3.6 Syhiv17 (роутер, LAN 192.168.1.1, wgclt1/wgclt2)

**Router ID:** 0.0.0.4. Endpoint master:51820 (wgclt1), worker:51822 (wgclt2). Аналогічно VRN625 — через UniFi UI або FRR.

**UniFi UI:** Router ID **0.0.0.4**, Area **0.0.0.0**, інтерфейси: LAN 192.168.1.0/24 та WireGuard (192.168.100.0/24, 192.168.200.0/24), Redistribute Connected.

**FRR (vtysh):**

```vtysh
configure terminal
hostname syhiv17
ip forwarding
router ospf
 router-id 0.0.0.4
 network 192.168.1.0/24 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
 network 192.168.200.0/24 area 0.0.0.0
 passive-interface default
 no passive-interface <lan_interface>
 no passive-interface wgclt1
 no passive-interface wgclt2
exit
exit
write memory
exit
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

## 6. Зведена таблиця Router ID та мереж

| Пристрій     | Router ID | Мережі в OSPF Area 0 |
|--------------|-----------|------------------------|
| Amper master | 0.0.0.1   | 10.0.10.0/24, 192.168.100.0/24 |
| Amper worker | 0.0.0.2   | 10.0.10.0/24, 192.168.200.0/24 |
| VRN625       | 0.0.0.3   | 192.168.2.0/24, 192.168.100.0/24, 192.168.200.0/24 |
| Syhiv17      | 0.0.0.4   | 192.168.1.0/24, 192.168.100.0/24, 192.168.200.0/24 |
| macmini7     | 0.0.0.5   | 192.168.1.0/24, 192.168.100.0/24, 192.168.200.0/24 |
| beelinkeqr5  | 0.0.0.6   | 192.168.2.0/24, 192.168.100.0/24, 192.168.200.0/24 |

Після встановлення сусідства (Full) між усіма парами на спільних мережах у кожного роутера з’явиться повна картина маршрутів до 10.0.10.0/24, 192.168.1.0/24, 192.168.2.0/24 та тунельних підмереж, що відповідає mesh WireGuard + OSPF з діаграми Syhiv VPN-3 OSPF.
