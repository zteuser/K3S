# Чи достатньо поточної конфігурації WireGuard для коректної роботи FRR OSPF

Аналіз сумісності поточних конфігурацій WireGuard з протоколом OSPF (FRR) та перелік необхідних змін.

---

## 1. Проблема з 224.0.0.5/32 і 224.0.0.6/32 у AllowedIPs

OSPF використовує **multicast** 224.0.0.5 (AllSPFRouters) і 224.0.0.6 (AllDRouters) для Hello та LSU. Якщо додати ці адреси до **AllowedIPs** кожного peer на одному й тому ж хості (наприклад, на master-node у wg0, wg1, wg2, wg3), WireGuard додасть **однаковий маршрут** для кожної пари (destination 224.0.0.5/32 via wg0, via wg1, via wg2, via wg3). У таблиці маршрутизації з’являється **конфлікт**: ядро не може мати кілька однакових prefix з різними nexthop без policy routing. В результаті використовується лише один маршрут (наприклад, перший доданий), і OSPF Hello/LSU йдуть лише в один тунель — сусідство на інших лінках не встановлюється.

**Висновок:** додавати 224.0.0.5/32 і 224.0.0.6/32 у AllowedIPs на **всіх** інтерфейсах wg* на Ubuntu **не можна** — це спричиняє конфлікт маршрутів.

---

## 2. Рішення: OSPF unicast (статичні сусіди) — без multicast у AllowedIPs

Замість multicast можна використовувати **unicast**: FRR відправляє OSPF Hello **на IP сусіда**, а не на 224.0.0.5. Цей IP **вже є** у AllowedIPs (підмережа /30), тому додаткових маршрутів не потрібно.

У [FRR OSPFv2](https://docs.frrouting.org/en/latest/ospfd.html) команда **neighbor** існує **лише під router ospf** (для NBMA та point-to-multipoint non-broadcast); **ip ospf neighbor** під інтерфейсом у FRR немає. Щоб FRR використовував unicast до цих сусідів:

- Тип мережі на WG-інтерфейсах: **point-to-multipoint non-broadcast** (тоді OSPF не шле на 224.0.0.5 і очікує явно заданих сусідів).
- Під **router ospf**: **neighbor &lt;IP_сусіда_на_/30&gt;** (опційно **poll-interval 30**).

Після цього OSPF використовує **unicast** до цього сусіда; маршрут до сусідського IP уже є (через AllowedIPs підмережі /30). **224.0.0.5/32 і 224.0.0.6/32 у WireGuard AllowedIPs не додаємо.**

---

## 3. Таблиця сусідів OSPF по інтерфейсах (IP другого кінця /30)

На кожному інтерфейсі вказується **один** сусід — протилежний кінець лінка /30.

### 3.1 master-node (192.168.100.x лише)

| Інтерфейс | Підмережа | Локальний IP | IP сусіда (neighbor) |
| ----------- | ----------- | -------------- | ------------------------ |
| wg0 | 192.168.100.0/30 | .1 | **192.168.100.2** (Syhiv17) |
| wg1 | 192.168.100.4/30 | .5 | **192.168.100.6** (VRN625) |
| wg2 | 192.168.100.8/30 | .9 | **192.168.100.10** (macmini7) |
| wg3 | 192.168.100.12/30 | .13 | **192.168.100.14** (beelinkeqr5) |

### 3.2 work-node (192.168.200.x лише)

| Інтерфейс | Підмережа | Локальний IP | IP сусіда (neighbor) |
| ----------- | ----------- | -------------- | ------------------------ |
| wg0 | 192.168.200.0/30 | .1 | **192.168.200.2** (Syhiv17) |
| wg1 | 192.168.200.4/30 | .5 | **192.168.200.6** (VRN625) |
| wg2 | 192.168.200.8/30 | .9 | **192.168.200.10** (macmini7) |
| wg3 | 192.168.200.12/30 | .13 | **192.168.200.14** (beelinkeqr5) |

### 3.3 macmini7

| Інтерфейс | Підмережа | Локальний IP | IP сусіда (neighbor) |
| ----------- | ----------- | -------------- | ------------------------ |
| wg0 | 192.168.100.8/30 | .10 | **192.168.100.9** (master wg2) |
| wg1 | 192.168.200.8/30 | .10 | **192.168.200.9** (worker wg2) |

### 3.4 beelinkeqr5

| Інтерфейс | Підмережа | Локальний IP | IP сусіда (neighbor) |
| ----------- | ----------- | -------------- | ------------------------ |
| wg0 | 192.168.100.12/30 | .14 | **192.168.100.13** (master wg3) |
| wg1 | 192.168.200.12/30 | .14 | **192.168.200.13** (worker wg3) |

### 3.5 Роутери (VRN625, Syhiv17)

Якщо на роутерах OSPF налаштовується через FRR/vtysh:

- **Syhiv17** wgclt1 (192.168.100.0/30, .2): neighbor **192.168.100.1** (master wg0).  
  Syhiv17 wgclt2 (192.168.200.0/30, .2): neighbor **192.168.200.1** (worker wg0).
- **VRN625** wgclt1 (192.168.100.4/30, .6): neighbor **192.168.100.5** (master wg1).  
  VRN625 wgclt2 (192.168.200.4/30, .6): neighbor **192.168.200.5** (worker wg1).

На UniFi (UI) — перевірити, чи є опція «OSPF neighbor» або «static neighbor» для інтерфейсу; якщо ні — залишити multicast і мати 224.0.0.5 лише на **одному** тунелі (на роутері зазвичай один peer на інтерфейс, тож конфлікту може не бути).

---

## 4. Що змінити в WireGuard

**Нічого.** 224.0.0.5/32 і 224.0.0.6/32 у AllowedIPs **не додавати**. Поточних AllowedIPs (підмережі /30 та потрібні LAN/хости) достатньо: unicast до сусідського IP вже маршрутизується через відповідний wg-інтерфейс.

Якщо на master-node (або work-node) у wg0/wg1 **вже** були додані 224.0.0.5/32, 224.0.0.6/32 для роутерів — їх можна **залишити** лише на **одному** з інтерфейсів (наприклад, тільки wg0), щоб не створювати конфлікт з wg1. Або прибрати з усіх і повністю перейти на unicast через **point-to-multipoint non-broadcast** і **neighbor** під router ospf (рекомендовано).

---

## 5. Що змінити у FRR (обов’язково)

У [FRR OSPFv2](https://docs.frrouting.org/en/latest/ospfd.html) команда **neighbor** існує **лише під router ospf**; **ip ospf neighbor** під інтерфейсом немає. На кожному пристрої з FRR:

1. На WG-інтерфейсах: **ip ospf network point-to-multipoint non-broadcast** (щоб FRR не слало Hello на 224.0.0.5 і використовувало список neighbor).
2. Під **router ospf**: **neighbor &lt;IP_сусіда&gt;** — значення з таблиці (розділ 3); опційно **poll-interval 30**.

Приклад для **master-node** (vtysh):

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

Для work-node, macmini7, beelinkeqr5 — аналогічно (тип мережі ptmp-nb на WG, neighbor під router ospf). Повні приклади — у **FRR_OSPF_CONFIG_EXAMPLES.md** (розділ 5.1).

---

## 6. iptables (Amper master і work-node)

Без правил **FORWARD між wg0/wg1 та wg2/wg3** трафік OSPF (і будь-який інший) між роутерами і нодами через Amper може не проходити. Це не пов’язано з multicast/unicast — див. **WIREGUARD_IPTABLES_HELPER_ANALYSIS.md**. Потрібно додати FORWARD для пар wg0↔wg2, wg0↔wg3, wg1↔wg2, wg1↔wg3 і симетрично видаляти їх у remove-скриптах.

---

## 7. Підсумок

| Питання | Відповідь |
| --------- | ----------- |
| Чи додавати 224.0.0.5/32, 224.0.0.6/32 у AllowedIPs на всіх wg*? | **Ні** — виникає конфлікт маршрутів на Ubuntu. |
| Як тоді працюватиме OSPF по тунелях? | Через **unicast**: у FRR тип мережі **point-to-multipoint non-broadcast** на WG-інтерфейсах і **neighbor &lt;IP&gt;** під **router ospf** (таблиця в розділі 3). У FRR **ip ospf neighbor** під інтерфейсом немає. |
| Чи потрібно щось міняти в WireGuard? | Ні (або прибрати 224.0.0.5/6 з AllowedIPs, якщо вони були додані на кількох інтерфейсах). |
| Що обов’язково змінити у FRR? | На WG-інтерфейсах: **ip ospf network point-to-multipoint non-broadcast**. Під **router ospf**: **neighbor &lt;IP&gt;** (розділ 3 і 5). У FRR **ip ospf neighbor** під інтерфейсом немає — тільки neighbor під router ospf. |
| Що ще потрібно для повного mesh? | iptables FORWARD між wg0/wg1 та wg2/wg3 на Amper (WIREGUARD_IPTABLES_HELPER_ANALYSIS.md). |
| Маршрути має формувати WireGuard чи OSPF? | За бажанням: **Table = off** у WG — маршрути тільки з FRR/OSPF; **AllowedIPs** лишаються (який трафік шифрувати). Див. **FRR_OSPF_CONFIG_EXAMPLES.md** (розд. 1.1) та **WIREGUARD_CLIENT_CONFIG_MACMINI_BEELINK.md** (розд. 5). |

Після налаштування статичних сусідів OSPF (unicast) поточна конфігурація WireGuard **достатня** для коректної роботи FRR OSPF без додавання 224.0.0.5/32 і 224.0.0.6/32 у AllowedIPs на всіх інтерфейсах.
