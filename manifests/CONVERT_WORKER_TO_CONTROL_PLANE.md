# Переведення worker-ноди (agent) у control-plane + etcd (server)

Можна надати роль **control-plane + etcd** ноді, яка зараз є **worker** (запускала k3s-agent). Для цього на цій ноді потрібно **зняти k3s-agent** і **встановити k3s у режимі server** (з тим самим токеном та адресою існуючого server). Приклад: нода **master-node**.

Після переведення у вас буде **три** server-ноди — etcd отримає кворум 2 з 3, і кластер залишатиметься працездатним при відмові однієї control-plane ноди.

---

## Передумови

1. **Кластер доступний** — хоча б одна control-plane нода працює, `kubectl` виконується (наприклад з macmini7 або beelinkeqr5).
2. **Token** — є доступ до `/var/lib/rancher/k3s/server/node-token` на будь-якій server-ноді.
3. **IP існуючого server** — для `--server https://<IP>:6443` (наприклад 192.168.2.19 або 192.168.2.155).
4. Нода, яку переводите (наприклад **master-node**), має мережевий доступ до існуючих server на порти **6443**, **2379**, **2380**.

---

## Порядок дій

### 1. Drain і cordon ноди (з робочої control-plane)

З ноди, де працює `kubectl` (наприклад macmini7):

```bash
# Замініть master-node на hostname вашої worker-ноди
kubectl drain master-node --ignore-daemonsets --delete-emptydir
kubectl cordon master-node
```

Поди з master-node переїдуть на інші ноди. Якщо drain не потрібен (нода майже порожня), можна лише cordon або пропустити і виконати далі на самій ноді.

### 2. На ноді master-node: зупинити і зняти k3s-agent

Підключіться до **master-node** (SSH або консоль):

```bash
sudo systemctl stop k3s-agent
sudo /usr/local/bin/k3s-agent-uninstall.sh
# або, якщо скрипта немає:
# sudo systemctl disable k3s-agent
# sudo rm -f /etc/systemd/system/k3s-agent.service
# sudo systemctl daemon-reload
```

Якщо пакет встановлювався через `get.k3s.io`, зазвичай є скрипт:

```bash
ls /usr/local/bin/k3s-agent-uninstall.sh
sudo /usr/local/bin/k3s-agent-uninstall.sh
```

Після цього k3s на цій ноді більше не працює.

### 3. На master-node: встановити k3s у режимі server

На тій самій ноді (master-node) виконайте (підставте **реальний токен** та **IP існуючого server** — macmini7 або beelinkeqr5):

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --token <K3S_TOKEN> \
  --server https://<IP_ІСНУЮЧОГО_SERVER>:6443
```

Приклад:

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --token K1068efbaeb8a868a219592420062f2c7378e47e70ace1f546d56ed3b8dedb7a706::server:f7eda228ae9a7c9ec861ad3f8261a418 \
  --server https://192.168.2.19:6443
```

Токен взяти на будь-якій server-ноді: `sudo cat /var/lib/rancher/k3s/server/node-token`.

Після встановлення запуститься сервіс **k3s** (server), не k3s-agent.

### 4. Uncordon і перевірка

З ноди з kubectl:

```bash
kubectl uncordon master-node
kubectl get nodes -o wide
```

Нода **master-node** має з’явитися з ролями **control-plane,etcd,master** (або control-plane,etcd). Якщо роль `master` не з’явилася:

```bash
kubectl label node master-node node-role.kubernetes.io/master=
```

### 5. Firewall на master-node

На ноді, яку перевели в server, відкрийте порти для etcd і API (якщо використовується firewall):

```bash
sudo ufw allow 6443/tcp
sudo ufw allow 2379/tcp
sudo ufw allow 2380/tcp
sudo ufw reload
```

Аналогічно на інших server-нодах має бути дозволений вхід з IP master-node на 6443, 2379, 2380.

---

## Підсумок

| Крок | Де виконувати | Дія |
|------|----------------|-----|
| 1 | control-plane (macmini7/beelinkeqr5) | `kubectl drain master-node --ignore-daemonsets --delete-emptydir` та `cordon` |
| 2 | master-node | `systemctl stop k3s-agent`, `k3s-agent-uninstall.sh` |
| 3 | master-node | `curl -sfL https://get.k3s.io \| sh -s - server --token <TOKEN> --server https://<SERVER_IP>:6443` |
| 4 | control-plane | `kubectl uncordon master-node`, `kubectl get nodes` |
| 5 | master-node (та інші server) | Firewall: 6443, 2379, 2380 |

Після цього кластер матиме **три** control-plane + etcd ноди; при падінні однієї кворум etcd зберігається (2 з 3), API залишається доступним.

---

## Помилка при join: "rejected connection", "Failed to test etcd connection"

Якщо після встановлення k3s server на колишній worker-ноді сервіс падає, а в логах з’являються **"rejected connection"** (etcd) та **"Failed to test etcd connection: rpc error"** — etcd на існуючих server-нодах (macmini7, beelinkeqr5) **відхиляє** з’єднання з нової ноди. Найчастіше це **firewall** або недоступність портів **2379, 2380** з нової ноди до існуючих server.

**Що зробити:**

1. **Доступ з master-node до server-нод по 2379 і 2380**  
   На master-node (підставте IP macmini7 та beelinkeqr5):
   ```bash
   nc -zv 192.168.2.19 2379
   nc -zv 192.168.2.19 2380
   nc -zv 192.168.2.155 2379
   nc -zv 192.168.2.155 2380
   ```
   Якщо «Connection refused» або таймаут — відкрити порти на server-нодах для IP master-node.

2. **Firewall на macmini7 і beelinkeqr5**  
   Дозволити вхід з IP master-node на порти etcd (замініть `<MASTER_NODE_IP>` на реальний IP):
   ```bash
   sudo ufw allow from <MASTER_NODE_IP> to any port 2379 proto tcp
   sudo ufw allow from <MASTER_NODE_IP> to any port 2380 proto tcp
   sudo ufw reload
   ```
   Виконати на **обох** server-нодах (macmini7 і beelinkeqr5).

3. **Перезапуск k3s на master-node після відкриття портів**
   ```bash
   sudo systemctl restart k3s
   journalctl -u k3s -f
   ```
   Після встановлення зв’язку з etcd сервіс має стабільно піднятися.

4. **Якщо нода раніше була в кластері як agent**  
   Якщо з робочої control-plane видно старий вузол `master-node` (наприклад NotReady), перед повторним join можна видалити його:  
   `kubectl delete node master-node`  
   Після успішного join нода з’явиться знову вже як server.

### TLS: "192.168.100.6 does not match" — два варіанти

**Варіант A: З’єднання від master-node йдуть з 192.168.100.6 (неправильний node-ip)**  
Якщо порти 2379/2380 відкриті, а в логах **на master-node** з’являється **rejected connection** при спробах master-node підключитися до macmini7/beelinkeqr5 — причина в тому, що master-node приєднується з неправильною адресою. k3s взяв для master-node адресу **10.0.10.10**, а реальні з’єднання до інших server-нод йдуть **з 192.168.100.6**. etcd перевіряє TLS по source IP; сертифікат виписаний на 10.0.10.10, тому з’єднання з 192.168.100.6 відхиляються.

**Варіант B: З’єднання до master-node приходять з 192.168.100.6 (NAT)**  
Якщо в логах **на master-node** з’являється **rejected connection on peer endpoint**, **remote-addr: 192.168.100.6**, **tls: "192.168.100.6" does not match any of DNSNames [macmini7, beelinkeqr5, ...]** — це означає, що **macmini7 або beelinkeqr5** підключаються **до** etcd на master-node (192.168.100.5), але їхній трафік проходить через **NAT**, тому source IP виглядає як **192.168.100.6**. Etcd на master-node перевіряє клієнтський сертифікат; у ньому вказано macmini7/beelinkeqr5 (або 192.168.2.x), а не 192.168.100.6 — тому з’єднання відхиляються. Рішення — додати 192.168.100.6 до SAN etcd peer-сертифікатів на **macmini7** і **beelinkeqr5** (див. нижче підрозділ «NAT: додати tls-san 192.168.100.6 на macmini7/beelinkeqr5»).

**Що зробити:** на master-node **зафіксувати node-ip** адресою, яка **реально налаштована на інтерфейсі** цієї ноди і до якої можуть з’єднатися macmini7/beelinkeqr5. Перевірити свої IP: `ip -4 addr` або `hostname -I`. Якщо в логах було "192.168.100.6" — це могла бути адреса шлюзу/NAT; для node-ip потрібен **власний** IP ноди, інакше виникне помилка **bind: cannot assign requested address**.

1. **Зупинити k3s на master-node:**
   ```bash
   sudo systemctl stop k3s
   ```

2. **Додати node-ip у конфіг** (замініть на реальний IP ноди, якщо він інший):
   ```bash
   echo 'node-ip: 192.168.100.6' | sudo tee -a /etc/rancher/k3s/config.yaml
   ```
   Або відредагувати `/etc/rancher/k3s/config.yaml` вручну — мають бути рядки `server:`, `token:` та додати `node-ip: 192.168.100.6`.

3. **Видалити старий etcd-статус** (щоб нода приєдналася з новою адресою):
   ```bash
   sudo rm -rf /var/lib/rancher/k3s/server/db/etcd
   ```

4. **На робочій control-plane (macmini7 або beelinkeqr5)** видалити старий член etcd з адресою 10.0.10.10 (якщо він уже в кластері і join з новою адресою не проходить). У k3s немає команд `etcd-member-list` / `etcd-member-remove` — використовуйте **etcdctl** з сертифікатами k3s:
   ```bash
   # Встановити etcdctl (apt install etcd-client або завантажити з release etcd)
   export ETCDCTL_API=3
   export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
   export ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt
   export ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/client.crt
   export ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/client.key

   sudo -E etcdctl member list
   # Знайти member з name master-node-... або peerURLs https://10.0.10.10:2380, зберегти його ID (перший стовпчик)
   sudo -E etcdctl member remove <MEMBER_ID>
   ```
   Якщо etcdctl недоступний — спочатку запустіть k3s на master-node з node-ip та очищеним etcd; якщо join знову впаде через існуючий член, тоді встановіть etcdctl і виконайте видалення.

5. **Запустити k3s на master-node:**
   ```bash
   sudo systemctl start k3s
   journalctl -u k3s -f
   ```

Після цього etcd на master-node має рекламувати **192.168.100.6:2380**, сертифікат буде для цієї адреси, і з’єднання з macmini7/beelinkeqr5 пройдуть TLS-перевірку.

### Трафік до control-plane йде з іншого IP (WireGuard/VPN): "192.168.100.6 does not match"

Якщо master-node має **node-ip: 10.0.10.10** і etcd слухає на 10.0.10.10, але з’єднання **від** master-node до macmini7/beelinkeqr5 виходять з **іншого** IP (наприклад 192.168.100.6 через WireGuard), то etcd на macmini7/beelinkeqr5 відхиляє їх: сертифікат клієнта для 10.0.10.10, а source IP — 192.168.100.6.

**Рішення:** на **master-node** змусити трафік **до** 192.168.2.x (macmini7, beelinkeqr5) виходити з інтерфейсу **10.0.10.10** (enp0s6), щоб source IP збігався з сертифікатом.

1. **Перевірити поточний маршрут** на master-node:
   ```bash
   ip route get 192.168.2.19
   ip route get 192.168.2.155
   ```
   Якщо в виводі є `src 192.168.100.5` або подібне — трафік йде через WG, потрібен окремий маршрут.

2. **Додати маршрут через enp0s6 з source 10.0.10.10** (підставте шлюз для 192.168.2.0/24, якщо він є в мережі 10.0.10.x; якщо 192.168.2.x доступний напряму з enp0s6 — використайте `dev enp0s6`):
   ```bash
   # Варіант: мережа 192.168.2.0/24 досяжна через шлюз 10.0.10.1 (приклад)
   sudo ip route add 192.168.2.0/24 via 10.0.10.1 dev enp0s6 src 10.0.10.10
   ```
   Або якщо 192.168.2.x на тому ж L2 що enp0s6:
   ```bash
   sudo ip route add 192.168.2.0/24 dev enp0s6 src 10.0.10.10
   ```
   Щоб маршрут зберігся після перезавантаження — додайте його в netplan або скрипт в `/etc/network/if-up.d/`.

3. **Перевірити**, що тепер трафік до 192.168.2.19 йде з 10.0.10.10:
   ```bash
   ip route get 192.168.2.19
   # Має бути src 10.0.10.10
   ```

4. **Перезапустити k3s** на master-node:
   ```bash
   sudo systemctl restart k3s
   journalctl -u k3s -f
   ```

Після цього etcd-з’єднання з master-node до macmini7/beelinkeqr5 мають йти з 10.0.10.10 і проходити TLS.

### 192.168.2.x досяжний лише через WireGuard (немає маршруту через enp0s6)

Якщо `ip route get 192.168.2.19` показує **dev wg1 src 192.168.100.5** — трафік до macmini7/beelinkeqr5 йде **тільки** через тунель, маршруту через enp0s6 (10.0.10.10) до 192.168.2.x немає. Тоді варто використовувати для k3s **node-ip інтерфейсу WireGuard** (192.168.100.5), щоб etcd біндився і підключався з одного й того ж IP — TLS буде проходити.

1. **Зупинити k3s** на master-node: `sudo systemctl stop k3s`
2. **У конфігу вказати node-ip WireGuard** (на master-node це 192.168.100.5):
   ```bash
   # /etc/rancher/k3s/config.yaml має містити server, token та:
   node-ip: 192.168.100.5
   ```
   (Якщо вже було `node-ip: 10.0.10.10` — замініть на 192.168.100.5.)
3. **Очистити etcd** (щоб приєднатися з новою адресою):  
   `sudo rm -rf /var/lib/rancher/k3s/server/db/etcd`
4. **На macmini7 або beelinkeqr5** видалити старий член etcd з 10.0.10.10 (якщо він є в `etcdctl member list`), щоб у кластері не лишилося запису з 10.0.10.10.
5. **Запустити k3s**: `sudo systemctl start k3s` і перевірити `journalctl -u k3s -f`.

Переконайтеся, що з macmini7/beelinkeqr5 **досяжний** 192.168.100.5 на портах 2379 і 2380 (через той самий WireGuard).

### NAT: з’єднання до master-node приходять з 192.168.100.6 — додати tls-san на macmini7/beelinkeqr5

Якщо в логах **на master-node** з’являється **rejected connection on peer endpoint**, **remote-addr: 192.168.100.6**, і помилка **tls: "192.168.100.6" does not match any of DNSNames [macmini7, beelinkeqr5, ...]** — трафік від macmini7/beelinkeqr5 до master-node (192.168.100.5) проходить через **NAT**, тому source IP виглядає як 192.168.100.6. Etcd на master-node очікує клієнтський сертифікат з SAN, що відповідає джерелу з’єднання; у сертифікатах macmini7/beelinkeqr5 є лише їхні hostname/IP (192.168.2.x), тому з’єднання відхиляються.

**Рішення:** додати **192.168.100.6** до SAN etcd peer-сертифікатів на **обох** існуючих server-нодах (macmini7 і beelinkeqr5), потім перегенерувати etcd-сертифікати.

**На macmini7:**

1. Зупинити k3s: `sudo systemctl stop k3s`
2. Додати SAN у конфіг:
   ```bash
   echo 'tls-san: 192.168.100.6' | sudo tee -a /etc/rancher/k3s/config.yaml
   ```
   (або відредагувати `/etc/rancher/k3s/config.yaml` вручну.)
3. Перегенерувати etcd-сертифікати: `sudo k3s certificate rotate --service etcd`
4. Запустити k3s: `sudo systemctl start k3s`

**На beelinkeqr5:** виконати ті самі кроки (1–4).

Після цього з’єднання від macmini7/beelinkeqr5 до etcd на master-node (з source 192.168.100.6 через NAT) мають проходити TLS-перевірку.

**Додатково на master-node:**

- Переконайтеся, що **node-ip: 192.168.100.5** у `/etc/rancher/k3s/config.yaml` (не 192.168.100.6).
- Якщо в кластері залишився старий Node з InternalIP 192.168.100.6, видаліть його з ноди з kubectl: `kubectl delete node master-node`, щоб master-node повторно зареєструвався з 192.168.100.5.
- Якщо etcd на master-node не стартує (connection refused на 127.0.0.1:2379), очистіть etcd і перезапустіть:  
  `sudo rm -rf /var/lib/rancher/k3s/server/db/etcd` → `sudo systemctl restart k3s`.

### Не використовувати адресу тунелю (192.168.100.5) для etcd

Якщо ви не хочете використовувати IP WireGuard (192.168.100.5) для etcd, а 192.168.2.x з master-node **досяжний лише через тунель** (`ip route get 192.168.2.19` → dev wg1 src 192.168.100.5), то є два варіанти:

1. **Залишити master-node тільки worker (agent)**  
   Не робити з неї control-plane/etcd. Тоді проблеми TLS немає: agent підключається до API по 6443, source IP не перевіряється etcd. Кластер залишається з двома control-plane (macmini7, beelinkeqr5); при падінні однієї кворум etcd не зберігається.

2. **Зробити 192.168.2.x досяжним з мережі 10.0.10.0/24 (без WG для etcd)**  
   Якщо є маршрут: з 10.0.10.10 (enp0s6) до 192.168.2.x через якийсь шлюз у мережі 10.0.10.x (наприклад 10.0.10.1), тоді можна додати на master-node маршрут типу:
   ```bash
   ip route add 192.168.2.0/24 via 10.0.10.1 dev enp0s6 src 10.0.10.10
   ```
   (шлюз 10.0.10.1 — приклад; має бути реальний шлюз, який знає шлях до 192.168.2.x.)  
   Після цього трафік до 192.168.2.19/155 піде з source 10.0.10.10, etcd з node-ip 10.0.10.10 пройде TLS. Якщо такого шляху немає (192.168.2.x лише в AllowedIPs WG), цей варіант неможливий без зміни мережі.

Якщо не використовувати 192.168.100.5 і немає маршруту з 10.0.10.10 до 192.168.2.x — master-node може бути лише **agent**, не server з etcd.

### Спробувати маршрут до 192.168.2.x через шлюз 10.0.10.1 (enp0s6)

Якщо зараз 192.168.2.19/155 мають лише host-маршрути через **wg1**, трафік йде з 192.168.100.5. Щоб він йшов з **10.0.10.10**, потрібен маршрут через **enp0s6** з source 10.0.10.10. Це має сенс лише якщо шлюз **10.0.10.1** сам має доступ до 192.168.2.x (наприклад через свій VPN або мережу).

На master-node виконати (тестовий маршрут, можна видалити пізніше):

```bash
# Додати маршрут до 192.168.2.0/24 через шлюз enp0s6 з source 10.0.10.10
sudo ip route add 192.168.2.0/24 via 10.0.10.1 dev enp0s6 src 10.0.10.10
```

Перевірити, чи тепер трафік до 192.168.2.19 виходить з 10.0.10.10:

```bash
ip route get 192.168.2.19
# Очікується: ... dev enp0s6 src 10.0.10.10
ping -c 1 192.168.2.19
# Якщо пінг проходить — шлюз 10.0.10.1 дійсно доставляє пакети до 192.168.2.x
```

- Якщо **src 10.0.10.10** і пінг успішний — залишити **node-ip: 10.0.10.10** у k3s, очистити etcd, перезапустити k3s; etcd має пройти TLS.
- Якщо маршрут не з’являється або пінг не проходить — 10.0.10.1 не має шляху до 192.168.2.x, тоді варіанти лише: **node-ip 192.168.100.5** (тунель) або **master-node лише як agent**.
