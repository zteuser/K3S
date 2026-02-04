# OSPF на роутерах VRN625 і Syhiv17: оголошувати лише /32 хостів

**Проблема:** роутери VRN625 і Syhiv17 зараз оголошують у OSPF цілі мережі **192.168.1.0/24** та **192.168.2.0/24**. Потрібно оголошувати лише конкретні хости з маскою /32:

- **Syhiv17:** 192.168.1.1/32  
- **VRN625:** 192.168.2.1/32, 192.168.2.198/32, 192.168.2.31/32  

---

## 1. Ідея рішення

1. **Прибрати** з OSPF оголошення мереж `network 192.168.1.0/24 area 0` та `network 192.168.2.0/24 area 0` на цих роутерах — тоді цілі /24 перестануть потрапляти в LSDB.
2. **Додати** в OSPF лише потрібні /32 через **redistribute** з **route-map** і **prefix-list**, щоб у LSDB потрапляли лише ці префікси.

Інтерфейси WireGuard (wgclt1, wgclt2) лишаються в OSPF (`network 192.168.100.0/24`, `network 192.168.200.0/24`) для сусідства з Amper. Змінюється лише спосіб оголошення LAN-адрес.

---

## 2. Syhiv17 (FRR): лише 192.168.1.1/32

- **Не** вказувати `network 192.168.1.0/24 area 0`.
- Оголошувати 192.168.1.1/32 через **redistribute connected** з route-map, який дозволяє лише цей префікс.

**Приклад у vtysh:**

```vtysh
configure terminal
ip prefix-list SYHIV-HOSTS seq 10 permit 192.168.1.1/32
route-map SYHIV-HOSTS-ONLY permit 10
 match ip address prefix-list SYHIV-HOSTS
route-map SYHIV-HOSTS-ONLY deny 20
exit
router ospf
 router-id 0.0.0.4
 no network 192.168.1.0/24 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
 network 192.168.200.0/24 area 0.0.0.0
 redistribute connected route-map SYHIV-HOSTS-ONLY
 passive-interface default
 no passive-interface <lan_interface>
 no passive-interface wgclt1
 no passive-interface wgclt2
exit
write memory
exit
```

Якщо зараз у конфігу немає `network 192.168.1.0/24 area 0`, достатньо додати лише **redistribute connected route-map SYHIV-HOSTS-ONLY** та створити prefix-list і route-map як вище.

---

## 3. VRN625 (FRR): 192.168.2.1/32, 192.168.2.198/32, 192.168.2.31/32

- **Не** вказувати `network 192.168.2.0/24 area 0`.
- 192.168.2.1/32 — **connected** (адреса роутера): вводимо через **redistribute connected** з route-map.
- 192.168.2.198/32 та 192.168.2.31/32 — якщо це хости в LAN, на роутері потрібні **статичні маршрути** (наприклад через LAN-інтерфейс), потім їх оголошуємо в OSPF через **redistribute static** з тим самим route-map.

**Статичні маршрути** (замість `<lan_interface>` підставте інтерфейс у мережі 192.168.2.0/24, наприклад `br0`, `eth0`):

```vtysh
configure terminal
ip route 192.168.2.198/32 <lan_interface>
ip route 192.168.2.31/32 <lan_interface>
exit
```

**Prefix-list і route-map:**

```vtysh
configure terminal
ip prefix-list VRN-HOSTS seq 10 permit 192.168.2.1/32
ip prefix-list VRN-HOSTS seq 20 permit 192.168.2.198/32
ip prefix-list VRN-HOSTS seq 30 permit 192.168.2.31/32
route-map VRN-HOSTS-ONLY permit 10
 match ip address prefix-list VRN-HOSTS
route-map VRN-HOSTS-ONLY deny 20
exit
```

**OSPF:** прибрати `network 192.168.2.0/24 area 0`, додати redistribute connected і redistribute static з цим route-map:

```vtysh
router ospf
 router-id 0.0.0.3
 no network 192.168.2.0/24 area 0.0.0.0
 network 192.168.100.0/24 area 0.0.0.0
 network 192.168.200.0/24 area 0.0.0.0
 redistribute connected route-map VRN-HOSTS-ONLY
 redistribute static route-map VRN-HOSTS-ONLY
 passive-interface default
 no passive-interface <lan_interface>
 no passive-interface wgclt1
 no passive-interface wgclt2
exit
write memory
exit
```

Підсумок для VRN625:

| Префікс        | Джерело    | Як потрапляє в OSPF                    |
|----------------|------------|----------------------------------------|
| 192.168.2.1/32 | connected  | redistribute connected route-map       |
| 192.168.2.198/32, 192.168.2.31/32 | static | redistribute static route-map         |

---

## 4. UniFi (UCG) — обмеження

Якщо VRN625 або Syhiv17 — це UniFi (UCG Ultra тощо), в UI зазвичай **немає** налаштування prefix-list / route-map для OSPF. Тоді:

- або використовувати **FRR** на роутері (якщо є доступ до vtysh, наприклад через SSH),
- або перевірити, чи в новіших версіях UniFi OS є опції типу «OSPF redistribute filter» / «prefix list» для OSPF.

Якщо в UI можна вимкнути оголошення мережі 192.168.x.0/24 і вручну додати лише «connected» — це дасть усі connected-префікси (включно з /32 на інтерфейсі), але не дозволить обмежитися лише одним /32 без FRR.

---

## 5. Перевірка

Після застосування змін на іншій ноді (наприклад master-node):

```bash
sudo vtysh -c "show ip route ospf"
```

У виводі мають з’явитися лише маршрути типу:

- 192.168.1.1/32
- 192.168.2.1/32, 192.168.2.198/32, 192.168.2.31/32  

і **не** має бути 192.168.1.0/24 та 192.168.2.0/24 від цих роутерів.

На самих роутерах:

```bash
show ip ospf route
show running-config
```

---

## 6. Підсумок

| Роутер  | Прибрати з OSPF      | Додати в OSPF (redistribute)                    |
|---------|----------------------|--------------------------------------------------|
| Syhiv17 | network 192.168.1.0/24 area 0 | redistribute connected route-map → лише 192.168.1.1/32 |
| VRN625  | network 192.168.2.0/24 area 0 | redistribute connected + static route-map → 192.168.2.1/32, 192.168.2.198/32, 192.168.2.31/32 |

Мережі 192.168.100.0/24 та 192.168.200.0/24 на WG-інтерфейсах лишаються в OSPF без змін.
