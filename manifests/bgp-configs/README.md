# BGP-конфіги для 4-вузлової full-mesh (WireGuard)

Конфігураційні файли для переходу з OSPF на BGP згідно з діаграмою тунелів (див. **FRR_OSPF_CONFIG_EXAMPLES.md**, **OSPF_VS_BGP_FOUR_ROUTERS_MESH.md**).

---

## Топологія та BGP-сусіди

| Вузол        | Router ID   | Інтерфейси (адреси) | BGP neighbors |
|-------------|-------------|----------------------|---------------|
| **master-node** | 10.0.10.10  | enp0s6 10.0.10.10, wg0 192.168.100.1, wg1 192.168.100.5 | 10.0.10.20, 192.168.100.2 (Syhiv17), 192.168.100.6 (VRN625) |
| **work-node**   | 10.0.10.20  | enp0s6 10.0.10.20, wg0 192.168.200.1, wg1 192.168.200.5 | 10.0.10.10, 192.168.200.2 (Syhiv17), 192.168.200.6 (VRN625) |
| **Syhiv17** (UCG) | 192.168.1.1  | br0 192.168.1.1, wgclt1 192.168.100.2, wgclt2 192.168.200.2 | 192.168.100.1 (master), 192.168.200.1 (worker) |
| **VRN625** (UCG) | 192.168.2.1  | br0 192.168.2.1, wgclt1 192.168.100.6, wgclt2 192.168.200.6 | 192.168.100.5 (master), 192.168.200.5 (worker) |

- **AS:** 65001 (iBGP на всіх).
- **Підмережі /30:** 192.168.100.0/30 (master–Syhiv17), 192.168.100.4/30 (master–VRN625), 192.168.200.0/30 (worker–Syhiv17), 192.168.200.4/30 (worker–VRN625).

---

## Файли

| Файл | Призначення |
|------|-------------|
| **bgp-master-node.conf** | Amper master: повний фрагмент для `/etc/frr/frr.conf` (zebra + bgpd). |
| **bgp-work-node.conf**    | Amper worker: те саме. |
| **bgp-Syhiv17.conf**     | Syhiv17 (UCG): вміст для завантаження в UniFi → Settings → Routing → BGP (тільки BGP + route-map). |
| **bgp-VRN625.conf**      | VRN625 (UCG): те саме. |

---

## Розгортання

### Amper (master / worker)

1. Вимкнути OSPF: у `/etc/frr/daemons` встановити `ospfd=no`, `bgpd=yes`.
2. Зберегти резервну копію `/etc/frr/frr.conf`.
3. Додати або замінити конфіг на вміст **bgp-master-node.conf** / **bgp-work-node.conf** (включно з zebra: hostname, ip forwarding, log, service integrated-vtysh-config). Якщо FRR вже має zebra, можна додати лише блок `router bgp` та вище перелічене за потреби.
4. Перезапустити FRR: `sudo systemctl restart frr`.
5. Перевірка: `sudo vtysh -c "show ip bgp summary"`, `show ip route bgp`.

### UCG (Syhiv17 / VRN625)

1. UniFi → **Settings** → **Routing** → **BGP** (або аналог для вашої версії).
2. Завантажити файл **bgp-Syhiv17.conf** / **bgp-VRN625.conf** як BGP Configuration.
3. Увімкнути BGP; якщо потрібно, увімкнути **bgpd** у `/etc/frr/daemons` через SSH (`bgpd=yes`) і перезапустити FRR.
4. Перевірка по SSH: `vtysh -c "show ip bgp summary"`, `show ip route bgp`.

**Якщо при старті FRR з’являються повідомлення «The route-map 'FROM-MASTER' does not exist»:** у конфігах UCG route-map оголошені **перед** блоком `router bgp`, щоб FRR бачив їх до посилань у neighbor. Якщо після повторного завантаження оновленого файлу помилка лишається, додайте route-maps вручну по SSH (`vtysh` → `conf t` → `route-map FROM-MASTER permit 10` → `set local-preference 200` → `exit` → аналогічно FROM-WORKER з 100) і збережіть конфіг (`write memory`).

---

## Route Reflector (Amper master і worker)

Через **iBGP split-horizon** маршрути, отримані по iBGP, не переказуються іншим iBGP-сусідам. Тому 192.168.1.0/24 (Syhiv17) і 192.168.2.0/24 (VRN625) не з’являлися на протилежному UCG, бо Syhiv17 і VRN625 не піряться між собою — лише через master/worker.

На **master** і **worker** увімкнено **Route Reflector** (`bgp cluster-id 0.0.0.1`, усі сусіди — `route-reflector-client`). Тоді master і worker відображають маршрути між усіма клієнтами: Syhiv17 отримує 192.168.2.0/24, VRN625 — 192.168.1.0/24.

---

## Політики на UCG (симетричний шлях)

На **Syhiv17** і **VRN625** застосовано route-map:

- **FROM-MASTER** (local-preference 200): маршрути від Amper master — переважні.
- **FROM-WORKER** (local-preference 100): маршрути від Amper worker — резерв.

Наслідок: трафік до 10.0.10.10 та 192.168.100.x йде через **wgclt1** (master), до 10.0.10.20 та 192.168.200.x — через **wgclt2** (worker), що уникає асиметричного reply і проблем із conntrack.

---

## Firewall

Як і для OSPF, на обох UCG мають бути дозволені джерела до шлюза (WAN/VPN → Gateway) для мереж: 192.168.100.0/24, 192.168.200.0/24, 192.168.1.0/24, 192.168.2.0/24 (див. **OSPF_192_168_1_2_GATEWAY_UNREACHABLE_FIX.md**). Для BGP потрібен **TCP 179** між сусідами; якщо WG-інтерфейси в зоні WAN/External, правило «дозволити BGP» для цих зон уже може покривати 179.

---

## Примітки

- **WireGuard:** перед увімкненням BGP переконайтеся, що тунелі wg0/wg1 (Amper) та wgclt1/wgclt2 (UCG) підняті і пінг до neighbor-адрес проходить.
- **Таблиця маршрутів:** на Amper при використанні BGP замість OSPF варто лишити **Table = off** у конфігах WireGuard і покладатися на маршрути з FRR (zebra).
- Документація Ubiquiti FRR/BGP на UCG: **UBIQUITI_UCG_FRR_BGP_DOCUMENTATION.md**.
