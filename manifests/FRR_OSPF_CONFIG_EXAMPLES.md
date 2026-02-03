# FRR OSPF — приклади конфігурації для mesh WireGuard + кластер k3s

Документ базується на діаграмі **Syhiv VPN-3 OSPF.pdf**: OSPF Area 0 (backbone), FRR на всіх пристроях — ноди кластера (Amper master/worker, macmini7, beelinkeqr5) та роутери (VRN625, Syhiv17). Мережі тунелів WireGuard та LAN оголошуються в OSPF для динамічної маршрутизації.

---

## 1. Топологія з діаграми (коротко)

| Пристрій | Роль | LAN / OCI | WG0 (192.168.100.x/30) | WG1 (192.168.200.x/30) | WG2 (192.168.100.x/30) | WG3 (192.168.200.x/30) |
|----------|------|-----------|-------------------------|-------------------------|-------------------------|-------------------------|
| **Amper master** | k3s master | 10.0.10.10/24 (eth0) | wg0: .5/30 (peer .6) | wg1: .5/30 (peer .6) | wg2: .10/30 (peer macmini7 .9) | wg3: .10/30 (peer macmini7 .9) |
| **Amper worker** | k3s worker | 10.0.10.20/24 (eth0) | wg0: .6/30 (peer .5) | wg1: .6/30 (peer .5) | wg2: .14/30 (peer beelink .13) | wg3: .14/30 (peer beelink .13) |
| **VRN625** | роутер | 192.168.2.1/24 | wg0: .1/30 (peer .2) | wg1: .1/30 (peer .2) | — | — |
| **Syhiv17** | роутер | 192.168.1.1/24 | wg0: .2/30 (peer .1) | wg1: .2/30 (peer .1) | — | — |
| **macmini7** | k3s master | 192.168.2.19/24 | — | — | wg2: .9/30 (peer Amper .10) | wg3: .9/30 (peer Amper .10) |
| **beelinkeqr5** | k3s master | 192.168.1.19/24 | — | — | wg2: .13/30 (peer Amper .14) | wg3: .13/30 (peer Amper .14) |

**Мережі для OSPF (Area 0):**

- 10.0.10.0/24 — OCI VLAN (Amper)
- 192.168.1.0/24 — LAN Syhiv17 / beelinkeqr5
- 192.168.2.0/24 — LAN VRN625 / macmini7
- 192.168.100.0/24 — збір /30 тунелів WG0/WG2 (оголошувати підмережі або один network statement залежно від підходу)
- 192.168.200.0/24 — збір /30 тунелів WG1/WG3

Нижче використовується **оголошення кожного інтерфейсу в OSPF** (network ... area 0), щоб у FRR були точні мережі. Router ID — унікальний на пристрій (наприклад 0.0.0.1 … 0.0.0.6).

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

### 3.1 Amper master (k3s master, OCI 10.0.10.10)

**Router ID:** 0.0.0.1. Інтерфейси: OCI VLAN, wg0, wg1, wg2, wg3 (якщо використовуються з адресами з діаграми).

```bash
sudo vtysh
```

```vtysh
configure terminal
hostname amper-master
ip forwarding
router ospf
 router-id 0.0.0.1
 network 10.0.10.0/24 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
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

Еквівалент у вигляді фрагмента **/etc/frr/frr.conf** (після існуючих `service integrated-vtysh-config` та `hostname`):

```conf
router ospf
 router-id 0.0.0.1
 network 10.0.10.0/24 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
 network 192.168.200.0/24 area 0.0.0.0
 passive-interface default
 no passive-interface eth0
 no passive-interface wg0
 no passive-interface wg1
 no passive-interface wg2
 no passive-interface wg3
```

Якщо основний інтерфейс OCI називається `enp0s6`, замініть `eth0` на `enp0s6`. Якщо частини WG-інтерфейсів немає (наприклад, тільки wg0/wg1), приберіть відповідні рядки `no passive-interface wg2`/`wg3`.

---

### 3.2 Amper worker (k3s worker, OCI 10.0.10.20)

**Router ID:** 0.0.0.2.

```vtysh
configure terminal
hostname amper-worker
ip forwarding
router ospf
 router-id 0.0.0.2
 network 10.0.10.0/24 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
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

### 3.3 macmini7 (k3s master, LAN 192.168.2.19)

**Router ID:** 0.0.0.5. OSPF на LAN-інтерфейсі та на wg2, wg3 (тунелі до Amper).

```vtysh
configure terminal
hostname macmini7
ip forwarding
router ospf
 router-id 0.0.0.5
 network 192.168.2.0/24 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
 network 192.168.200.0/24 area 0.0.0.0
 passive-interface default
 no passive-interface eth0
 no passive-interface wg2
 no passive-interface wg3
exit
exit
write memory
exit
```

Ім’я LAN-інтерфейсу замініть на фактичне (наприклад `en0` на macOS — на Ubuntu зазвичай `eth0` або подібне).

---

### 3.4 beelinkeqr5 (k3s master, LAN 192.168.1.19)

**Router ID:** 0.0.0.6.

```vtysh
configure terminal
hostname beelinkeqr5
ip forwarding
router ospf
 router-id 0.0.0.6
 network 192.168.1.0/24 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
 network 192.168.200.0/24 area 0.0.0.0
 passive-interface default
 no passive-interface eth0
 no passive-interface wg2
 no passive-interface wg3
exit
exit
write memory
exit
```

---

### 3.5 VRN625 (роутер, LAN 192.168.2.1, WG0/WG1)

**Router ID:** 0.0.0.3. На UCG Ultra OSPF налаштовується через **UniFi Network Application** (Settings → Routing & Firewall → OSPF). Нижче — еквівалент для FRR (якщо на роутері доступний vtysh або імпорт конфігу).

Потрібно в OSPF Area 0:

- Інтерфейс LAN (192.168.2.0/24)
- Інтерфейси WireGuard: 192.168.100.1/30 (wg0), 192.168.200.1/30 (wg1)

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
 no passive-interface wg0
 no passive-interface wg1
exit
exit
write memory
exit
```

Ім’я LAN-інтерфейсу на UCG підставити згідно з вашою топологією (наприклад br0 або інтерфейс, що має 192.168.2.1).

---

### 3.6 Syhiv17 (роутер, LAN 192.168.1.1, WG0/WG1)

**Router ID:** 0.0.0.4. Аналогічно VRN625 — через UniFi UI або FRR.

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
 no passive-interface wg0
 no passive-interface wg1
exit
exit
write memory
exit
```

---

## 4. Альтернатива: оголошення точних підмереж /30

Якщо замість `network 192.168.100.0/24` потрібно оголошувати лише ті підмережі, що реально є на пристрої, можна використати окремі `network` для кожного /30. Приклад для **Amper master** (має .5/30 на wg0, .5/30 на wg1, .10/30 на wg2, .10/30 на wg3):

```vtysh
router ospf
 router-id 0.0.0.1
 network 10.0.10.0/24 area 0.0.0.0
 network 192.168.100.4/30 area 0.0.0.0
 network 192.168.100.8/30 area 0.0.0.0
 network 192.168.100.12/30 area 0.0.0.0
 network 192.168.200.4/30 area 0.0.0.0
 network 192.168.200.8/30 area 0.0.0.0
 network 192.168.200.12/30 area 0.0.0.0
 passive-interface default
 no passive-interface eth0
 no passive-interface wg0
 no passive-interface wg1
 no passive-interface wg2
 no passive-interface wg3
```

На інших пристроях аналогічно: оголошувати лише ті 192.168.100.x/30 та 192.168.200.x/30, які реально знаходяться на локальних інтерфейсах. Це обмежує LSA та таблиці маршрутів лише потрібними підмережами.

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
| Amper master | 0.0.0.1   | 10.0.10.0/24, 192.168.100.0/24, 192.168.200.0/24 |
| Amper worker | 0.0.0.2   | 10.0.10.0/24, 192.168.100.0/24, 192.168.200.0/24 |
| VRN625       | 0.0.0.3   | 192.168.2.0/24, 192.168.100.0/24, 192.168.200.0/24 |
| Syhiv17      | 0.0.0.4   | 192.168.1.0/24, 192.168.100.0/24, 192.168.200.0/24 |
| macmini7     | 0.0.0.5   | 192.168.2.0/24, 192.168.100.0/24, 192.168.200.0/24 |
| beelinkeqr5  | 0.0.0.6   | 192.168.1.0/24, 192.168.100.0/24, 192.168.200.0/24 |

Після встановлення сусідства (Full) між усіма парами на спільних мережах у кожного роутера з’явиться повна картина маршрутів до 10.0.10.0/24, 192.168.1.0/24, 192.168.2.0/24 та тунельних підмереж, що відповідає mesh WireGuard + OSPF з діаграми Syhiv VPN-3 OSPF.
