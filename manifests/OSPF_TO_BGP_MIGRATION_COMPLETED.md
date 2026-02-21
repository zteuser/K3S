# Перехід з OSPF на BGP — виконано

**Статус:** маршрутизація між чотирма вузлами (Amper master, Amper worker, Syhiv17, VRN625) виконується протоколом **BGP** замість OSPF. Діаграма та конфіги — у **BGP_ROUTING_DIAGRAM.md** та **manifests/bgp-configs/**.

---

## 1. Чому перейшли на BGP

- **Симетричний шлях:** при OSPF через ECMP reply міг йти іншим тунелем, ніж request → conntrack INVALID, firewall дропав. З BGP вибір next-hop керується політиками (local-preference), один шлях на префікс.
- **Один механізм вибору шляху:** замість різного cost на Syhiv17 і VRN625 (щоб 10.0.10.20 лишався через wgclt2) — route-map FROM-MASTER / FROM-WORKER на UCG.
- **Менше ручних виключень:** не потрібно пам’ятати, де cost підвищувати, а де ні.
- **Той самий failover:** при падінні тунеля BGP withdraw; маршрути від іншого peer залишаються.

Детальне порівняння — **OSPF_VS_BGP_FOUR_ROUTERS_MESH.md**.

---

## 2. Що зроблено

| Етап | Опис |
|------|------|
| Конфіги BGP | Чотири файли: **bgp-master-node.conf**, **bgp-work-node.conf**, **bgp-Syhiv17.conf**, **bgp-VRN625.conf** (каталог **manifests/bgp-configs/**). |
| AS | Один приватний AS **65001** (iBGP) на всіх вузлах. |
| Route Reflector | На **master** і **worker** увімкнено RR (cluster-id 0.0.0.1), усі сусіди — route-reflector-client, щоб 192.168.1.0/24 та 192.168.2.0/24 поширювалися між UCG. |
| Політики на UCG | Route-map FROM-MASTER (local-pref 200), FROM-WORKER (local-pref 100) — оголошені **перед** блоком `router bgp` у завантажуваному файлі. |
| Діаграма | Оновлена схема маршрутизації BGP — **BGP_ROUTING_DIAGRAM.md**. |
| Документація UCG | Посилання на Ubiquiti FRR/BGP — **UBIQUITI_UCG_FRR_BGP_DOCUMENTATION.md**. |

---

## 3. Попередня схема (OSPF)

- Фінальна діаграма OSPF: **Syhiv OSPF.pdf** (у корені репозиторію).
- Опис топології та конфігів OSPF: **FRR_OSPF_CONFIG_EXAMPLES.md**, **OSPF_DIAGRAM_ANALYSIS_AND_REFERENCES.md**.
- Вирішені проблеми (firewall, cost, недоступність .1): **OSPF_192_168_1_2_GATEWAY_UNREACHABLE_FIX.md**, **OSPF_ROUTERS_HOST_ROUTES_32.md**.

Ці документи лишаються для історії та діагностики; поточна робоча схема — BGP (див. діаграму нижче).

---

## 4. Поточна схема (BGP) — короткий огляд

- **Чотири вузли:** master (10.0.10.10), worker (10.0.10.20), Syhiv17 (192.168.1.1), VRN625 (192.168.2.1).
- **Тунелі:** WireGuard full-mesh між Amper і двома UCG (master↔Syhiv17, master↔VRN625, worker↔Syhiv17, worker↔VRN625); master–worker — лише OCI (enp0s6).
- **BGP-сесії:** 5 пар (master–worker, master–Syhiv17, master–VRN625, worker–Syhiv17, worker–VRN625). Syhiv17 і VRN625 між собою не піряться.
- **Оголошені мережі:** 10.0.10.10/32, 10.0.10.20/32, 10.0.10.0/24, 192.168.1.0/24, 192.168.2.0/24, підмережі /30 тунелів.

Повна діаграма та таблиці — у **BGP_ROUTING_DIAGRAM.md**.
