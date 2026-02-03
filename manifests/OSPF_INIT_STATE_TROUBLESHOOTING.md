# OSPF застряг у стані Init між master-node та роутерами (Syhiv17, VRN625)

## 1. Що видно з виводу

- **master-node** `show ip ospf neighbor`: сусіди 192.168.1.1 (Syhiv17) і 192.168.2.1 (VRN625) у стані **Init/-** на wg0 і wg1.
- **Init** означає: ми отримали Hello від сусіда, але сусід **ще не отримав наш Hello**. Тобто наші Hello не доходять до роутерів або йдуть не туди.
- **tcpdump**: і master, і VRN625 шлють OSPF у **224.0.0.5** (multicast). На VRN625 wgclt1 видно лише **192.168.100.6 → 224.0.0.5**; пакетів **192.168.100.5 → …** (від master) там немає.

**Висновок:** Hello від master-node **не доходять** до Syhiv17/VRN625 по wg0/wg1. Причина: FRR на master відправляє Hello на **224.0.0.5**; без 224.0.0.5 у AllowedIPs на кожному wg ядро не маршрутизує цей multicast саме через wg0/wg1, тому роутери не бачать Hello від master.

---

## 2. Рішення: unicast Hello через point-to-multipoint non-broadcast + neighbor під router ospf

У [FRR OSPFv2](https://docs.frrouting.org/en/latest/ospfd.html) команда **neighbor A.B.C.D** існує **лише під router ospf** (для NBMA та point-to-multipoint non-broadcast). Команди **ip ospf neighbor** під інтерфейсом у FRR **немає**.

Щоб FRR слало Hello **unicast** на IP сусіда (а не на 224.0.0.5), потрібно:

1. На WG-інтерфейсах задати тип мережі **ip ospf network point-to-multipoint non-broadcast**. Тоді OSPF не використовує multicast і очікує явно заданих сусідів.
2. Під **router ospf** задати **neighbor &lt;IP_сусіда_на_/30&gt;** (опційно **poll-interval 30**). FRR шле Hello unicast на ці IP; маршрут до них уже є (AllowedIPs /30).

---

## 3. Що змінити на master-node

1. Тип мережі на wg0–wg3: **point-to-multipoint non-broadcast** (замість point-to-point):

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
write memory
exit
```

2. Сусіди лише під **router ospf** (у вас вже є; можна додати poll-interval):

```vtysh
router ospf
 neighbor 192.168.100.2 poll-interval 30
 neighbor 192.168.100.6 poll-interval 30
 neighbor 192.168.100.10 poll-interval 30
 neighbor 192.168.100.14 poll-interval 30
exit
write memory
exit
```

Після цього перевірте `show ip ospf neighbor` і tcpdump — мають з’явитися пакети **192.168.100.5 → 192.168.100.6** (unicast).

---

## 4. Роутери (VRN625, Syhiv17)

У вас на VRN625 вже є:

```
router ospf
 neighbor 192.168.100.5 poll-interval 30
 neighbor 192.168.200.5 poll-interval 30
```

Це **правильний** варіант для FRR. На WG-інтерфейсах (wgclt1, wgclt2) потрібно задати **ip ospf network point-to-multipoint non-broadcast**, щоб FRR використовував ці neighbor для unicast Hello. Якщо зараз на wgclt1/wgclt2 стоїть **point-to-point**, замініть на:

```vtysh
interface wgclt1
 ip ospf network point-to-multipoint non-broadcast
interface wgclt2
 ip ospf network point-to-multipoint non-broadcast
exit
write memory
exit
```

Syhiv17 аналогічно: **neighbor 192.168.100.1**, **neighbor 192.168.200.1** під router ospf і **point-to-multipoint non-broadcast** на wgclt1/wgclt2.

---

## 5. Коротко

| Питання | Відповідь |
|---------|-----------|
| Чи є в FRR **ip ospf neighbor** під інтерфейсом? | **Ні.** У [FRR OSPFv2](https://docs.frrouting.org/en/latest/ospfd.html) neighbor задається лише під **router ospf**. |
| Як отримати unicast Hello? | Тип мережі на WG: **point-to-multipoint non-broadcast**; сусіди під **router ospf**: **neighbor A.B.C.D [poll-interval 30]**. |
| master-node | На wg0–wg3: **ip ospf network point-to-multipoint non-broadcast**. Під router ospf: neighbor 192.168.100.2, .6, .10, .14 (poll-interval 30). |
| VRN625 / Syhiv17 | Залишити **neighbor** під router ospf; на wgclt1/wgclt2 — **ip ospf network point-to-multipoint non-broadcast**. |
