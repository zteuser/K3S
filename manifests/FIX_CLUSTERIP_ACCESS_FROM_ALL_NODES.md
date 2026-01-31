# Доступ до Kubernetes API (ClusterIP) з усіх нод

Якщо поди на worker-нодах отримують `dial tcp 10.43.0.1:443: connect: no route to host` при зверненні до Kubernetes API (сервіс `kubernetes.default`, ClusterIP 10.43.0.1), це зазвичай **firewall або маршрутизація** на нодах. Нижче — перевірки та кроки для виправлення.

## Що потрібно для доступу

- **Pod CIDR:** 10.42.0.0/16 (за замовчуванням у k3s)
- **Service CIDR:** 10.43.0.0/16 (тут лежить API 10.43.0.1)
- **API server:** master-нода, порт **6443** (k3s)

Трафік под → 10.43.0.1:443 обробляє **kube-proxy** (DNAT на master:6443). Щоб пакет дійшов до master, потрібно:
1. На **кожній ноді** не блокувати трафік з/до 10.42.0.0/16 і 10.43.0.0/16.
2. На **master** дозволити вхід на порт 6443 з pod-мережі або з IP worker-нод.

**Якщо API по IP (10.43.0.1) з work-node працює, а DNS (nslookup до 10.43.0.10) — таймаут:** правила INPUT/FORWARD для 10.42/10.43 потрібно додати на **усі** ноди кластера, включно з **control-plane** (macmini7, beelinkeqr5, master-node). CoreDNS працює на одній із нод; запит від пода на work-node проходить, але **відповідь** від пода CoreDNS йде з тієї ноди, де він запущений — якщо там у кінці FORWARD стоїть REJECT без дозволу 10.42/10.43, відповідь відкидається і DNS «висить».

**Схема тунелів (WireGuard):**
- **macmini7 (192.168.2.19) ↔ work-node (10.0.10.20)** — тунель **192.168.200.x**: work-node має **192.168.200.5**, macmini7 — **192.168.200.6**. Досяжність macmini7 → work-node відбувається через 192.168.200.5.
- Сегмент **192.168.100.x** — інший тунель (наприклад beelinkeqr5 або інший peer). Якщо k3s на work-node підключається до API за 192.168.100.5, потрібен маршрут/allowed_ips для 192.168.100.5 на wg1.

**Якщо work-node досягає control-plane через WireGuard (wg1):** усі IP API server (192.168.2.155, 192.168.2.19, а за потреби 192.168.100.5, **192.168.200.6** тощо) мають бути в **allowed-ips** для відповідного peer у wg1. Інакше k3s буде таймаутити при підключенні до цих серверів.

### Помилка: `dial tcp 192.168.100.5:6443: connect: connection timed out` на work-node

**Причина:** k3s-agent на work-node намагається підключитися до API за адресою **192.168.100.5** (інший сегмент WG). Якщо трафік до 192.168.100.5 не йде через wg1 або peer не має цього IP в `allowed_ips`, з’єднання таймаутить. Примітка: зв’язок **macmini7 ↔ work-node** йде через **192.168.200.x** (work-node = 192.168.200.5, macmini7 = 192.168.200.6).

**Діагностика на work-node:** `ip route get 192.168.100.5` (має бути `dev wg1`), `sudo wg show wg1` (allowed_ips для peer), `nc -zv 192.168.100.5 6443`. Виправлення: додати 192.168.100.5/32 (або 192.168.100.4/30) у AllowedIPs для відповідного peer у wg1, потім `systemctl restart wg-quick@wg1`.

### Помилка: DNS/OTV не працює — на work-node з’являється `ICMP host 10.0.10.20 unreachable - admin prohibited`

**Симптоми (tcpdump на wg1):** запити OTV (DNS тощо) йдуть з 10.0.10.20 до 192.168.2.19; відповідь з 192.168.200.**6** (macmini7) приходить на 10.0.10.20, але **work-node відповідає ICMP "admin prohibited"** на 192.168.200.6. У результаті відповіді (DNS, flannel) не доходять до подів.

**Причина:** на **work-node** firewall (iptables) **відкидає вхідний трафік** з джерела 192.168.200.6 (або 192.168.200.0/30) на призначення 10.0.10.20 (локальний інтерфейс work-node). Тобто зворотний OTV/overlay-трафік з control-plane на work-node блокується.

**Виправлення на work-node:** дозволити INPUT (і за потреби FORWARD) з тунельної підмережі, щоб пакети від macmini7 (192.168.200.6) до 10.0.10.20 приймалися:

```bash
# Дозволити вхід з тунелю 192.168.200.x (macmini7 = .6) на work-node (10.0.10.20)
sudo iptables -I INPUT 1 -s 192.168.200.0/30 -d 10.0.10.20 -j ACCEPT
# Якщо потрібно також для pod/service CIDR (зворотний трафік у overlay):
sudo iptables -I INPUT 1 -s 192.168.200.0/30 -j ACCEPT
```

Після перевірки — зберегти правила (див. розділ 3.4). Перевірка: з work-node под `nslookup kubernetes.default.svc.cluster.local` має відповідати без таймауту; на wg1 не має з’являтися нових `ICMP ... admin prohibited` у відповідь на пакети з 192.168.200.6.

---

## 1. Перевірки перед змінами

**Де виконувати `kubectl`:** на worker-нодах часто немає kubeconfig (помилка `connection to server localhost:8080 refused`). Усі команди `kubectl` нижче виконуйте з **control-plane** ноди (macmini7, beelinkeqr5 або master-node), де є доступ до кластера (наприклад `/etc/rancher/k3s/k3s.yaml`).

Перевірки в цьому розділі: пункти 1.1 — з control-plane; 1.2, 1.3, 1.4 — безпосередньо на відповідній ноді (SSH на worker/master).

### 1.1 kube-proxy

Виконати **з control-plane** (macmini7 або beelinkeqr5):

```bash
kubectl get pods -n kube-system -o wide | grep -E 'kube-proxy|NAME'
# або напряму DaemonSet (у k3s він називається kube-proxy):
kubectl get daemonset -n kube-system
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide
```

Має бути один под kube-proxy на кожну ноду (включно з work-node), статус Running. Якщо на worker немає пода або він у CrashLoopBackOff — спочатку вирішіть це.

### 1.2 Маршрути та інтерфейси

На worker-ноді:

```bash
ip route | grep -E '10\.42|10\.43|flannel|cni'
```

Має бути маршрут до 10.42.0.0/16 (pod network). Якщо його немає — проблема в CNI (flannel тощо).

### 1.3 Доступ з хоста worker до API на master

На worker-ноді (замініть `<MASTER_IP>` на IP master):

```bash
curl -k https://<MASTER_IP>:6443/healthz
```

Якщо з хоста є "connection refused" або "no route to host" — firewall на master або мережа між нодами.

### 1.4 Що використовується: firewalld чи iptables/nftables

```bash
sudo systemctl status firewalld 2>/dev/null || true
sudo iptables -L -n 2>/dev/null | head -30
```

Далі налаштовуємо те, що у вас увімкнено.

---

## 2. Firewalld (RHEL/CentOS/Fedora, частина дистрибутивів)

Виконуйте на **усіх нодах** (master і workers).

### 2.1 Дозволити pod- і service-мережі (trusted)

```bash
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
sudo firewall-cmd --reload
```

### 2.2 На **master** дозволити вхід на порт API

```bash
sudo firewall-cmd --permanent --add-port=6443/tcp
# Якщо хочете обмежити лише pod/worker-мережею:
# sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=10.42.0.0/16 port port=6443 protocol=tcp accept'
sudo firewall-cmd --reload
```

### 2.3 Перезапуск k3s після змін firewalld (якщо щось зламалося)

На деяких системах після `firewall-cmd --reload` k3s перестає бачити свої правила. Якщо після кроків вище доступ не з’явився:

```bash
sudo systemctl restart k3s
# або на worker:
# sudo systemctl restart k3s-agent
```

---

## 3. iptables (Debian/Ubuntu та ін., коли firewalld немає)

На **кожній ноді** переконайтеся, що не блокується трафік для pod/service CIDR.

### 3.1 Переглянути правила

```bash
sudo iptables -L -n -v | head -60
sudo iptables -L FORWARD -n -v
```

Шукайте правила, що DROP або REJECT трафік з 10.42.x.x або до 10.43.x.x. Якщо в кінці INPUT або FORWARD є `REJECT all`, а дозволу лише для 10.0.10.0/24 — трафік з подів (10.42.x) і до сервісів (10.43.x) буде відкидатися. Потрібно додати ACCEPT для 10.42.0.0/16 і 10.43.0.0/16 **перед** цим REJECT.

### 3.2 Дозволити pod/service CIDR в INPUT і FORWARD (на **усіх** нодах)

Якщо на ноді є фінальне правило `REJECT all` в INPUT (або FORWARD), а 10.42/16 і 10.43/16 не дозволені — поди не зможуть досягти API/CoreDNS. Додайте правила **на початок** ланцюга (щоб вони спрацювали раніше REJECT).

**Важливо:** правила потрібно додати на **усі** ноди кластера — і на work-node, і на **control-plane** (macmini7, beelinkeqr5, master-node). Інакше DNS може не працювати: запит з work-node доходить до CoreDNS, а відповідь від пода CoreDNS (нода, де він запущений) відкидається там фінальним REJECT у FORWARD.

**На кожній ноді (work-node, macmini7, beelinkeqr5, master-node):**

```bash
# INPUT: дозволити трафік з/до pod і service мереж (щоб поди могли ходити до ClusterIP)
sudo iptables -I INPUT 1 -s 10.43.0.0/16 -j ACCEPT
sudo iptables -I INPUT 1 -d 10.43.0.0/16 -j ACCEPT
sudo iptables -I INPUT 1 -s 10.42.0.0/16 -j ACCEPT
sudo iptables -I INPUT 1 -d 10.42.0.0/16 -j ACCEPT

# FORWARD: те саме для forwarded трафіку подів
sudo iptables -I FORWARD 1 -s 10.42.0.0/16 -j ACCEPT
sudo iptables -I FORWARD 1 -d 10.42.0.0/16 -j ACCEPT
sudo iptables -I FORWARD 1 -s 10.43.0.0/16 -j ACCEPT
sudo iptables -I FORWARD 1 -d 10.43.0.0/16 -j ACCEPT
```

Після перевірки (под з work-node досягає API) — збережіть правила (див. 3.4).

**Порядок правил у FORWARD:** правила ACCEPT для 10.42/10.43 мають бути **першими** у ланцюгу FORWARD (перевірка: `iptables -L FORWARD -n -v | head -15`). Якщо першим йде `KUBE-ROUTER-FORWARD` (kube-router), весь трафік спочатку потрапляє туди і може бути відкинутий — тоді DNS з work-node не працюватиме. На такій ноді ще раз виконайте тільки 4 команди для FORWARD (див. вище); вони вставляють правила в позицію 1 і зсувають KUBE-ROUTER-FORWARD нижче.

**Якщо kube-router знову ставить своє правило першим:** kube-router (або k3s) періодично оновлює iptables і вставляє `KUBE-ROUTER-FORWARD` на початок FORWARD, тому ручні ACCEPT зсуваються вниз і перестають спрацьовувати. Рішення — скрипт, що періодично (cron) видаляє наші правила за коментарем і знову вставляє їх на позицію 1. На **кожній** ноді (work-node, macmini7, beelinkeqr5, master-node), де потрібен доступ подів до ClusterIP/DNS:

1. Створити скрипт `/usr/local/bin/k3s-forward-pod-cidr.sh`:
   ```bash
   #!/bin/bash
   COMMENT="k3s-pod-cidr-accept"
   for _ in 1 2 3 4 5 6 7 8; do
     iptables -D FORWARD -s 10.42.0.0/16 -j ACCEPT -m comment --comment "$COMMENT" 2>/dev/null || true
     iptables -D FORWARD -d 10.42.0.0/16 -j ACCEPT -m comment --comment "$COMMENT" 2>/dev/null || true
     iptables -D FORWARD -s 10.43.0.0/16 -j ACCEPT -m comment --comment "$COMMENT" 2>/dev/null || true
     iptables -D FORWARD -d 10.43.0.0/16 -j ACCEPT -m comment --comment "$COMMENT" 2>/dev/null || true
   done
   iptables -I FORWARD 1 -d 10.43.0.0/16 -j ACCEPT -m comment --comment "$COMMENT"
   iptables -I FORWARD 1 -s 10.43.0.0/16 -j ACCEPT -m comment --comment "$COMMENT"
   iptables -I FORWARD 1 -d 10.42.0.0/16 -j ACCEPT -m comment --comment "$COMMENT"
   iptables -I FORWARD 1 -s 10.42.0.0/16 -j ACCEPT -m comment --comment "$COMMENT"
   ```

2. `chmod +x /usr/local/bin/k3s-forward-pod-cidr.sh`

3. Cron кожні 1–2 хвилини (root): `crontab -e`, додати:
   ```
   */2 * * * * /usr/local/bin/k3s-forward-pod-cidr.sh
   ```

Після цього перевірити: `iptables -L FORWARD -n -v | head -10` — спочатку мають бути 4× ACCEPT з коментарем `k3s-pod-cidr-accept`, потім KUBE-ROUTER-FORWARD.

### 3.3 Дозволити лише forward (якщо INPUT вже не реджектить pod-трафік)

Якщо є політика DROP лише для FORWARD:

```bash
sudo iptables -I FORWARD 1 -s 10.42.0.0/16 -j ACCEPT
sudo iptables -I FORWARD 1 -d 10.42.0.0/16 -j ACCEPT
sudo iptables -I FORWARD 1 -s 10.43.0.0/16 -j ACCEPT
sudo iptables -I FORWARD 1 -d 10.43.0.0/16 -j ACCEPT
```

### 3.4 Збереження правил (persistent)

```bash
# Debian/Ubuntu з iptables-persistent
sudo netfilter-persistent save
# або вручну
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

Якщо правила задаються скриптом при завантаженні — додайте туди ці ж рядки.

### 3.5 На **master**: вхід на 6443

Якщо є INPUT DROP/REJECT за замовчуванням:

```bash
sudo iptables -I INPUT 1 -p tcp --dport 6443 -j ACCEPT
# або лише з pod/worker-мережі:
# sudo iptables -I INPUT 1 -p tcp -s 10.42.0.0/16 --dport 6443 -j ACCEPT
```

І збережіть правила (3.4).

---

## 4. nftables

Якщо використовується nftables замість iptables:

```bash
sudo nft list ruleset
```

Потрібно додати allow для 10.42.0.0/16, 10.43.0.0/16 та для порту 6443 на master (конкретний синтаксис залежить від вашої таблиці/chain).

---

## 5. Перевірка після налаштувань

### 5.1 DNS все ще таймаутить після правил на control-plane

Якщо правила FORWARD на macmini7 (нода з CoreDNS) вже перші, а `nslookup` з пода на work-node до 10.43.0.10 все одно «connection timed out»:

1. **DNS з пода на тій же ноді, що й CoreDNS** (перевірка, чи взагалі CoreDNS відповідає):
   ```bash
   kubectl run dns-local --rm -it --restart=Never --image=busybox:1.36 --overrides='{"spec":{"nodeName":"macmini7"}}' -- nslookup kubernetes.default.svc.cluster.local 10.43.0.10
   ```
   Якщо тут є відповідь, а з work-node — ні, проблема в маршрутизації/форвардингу між нодами (work-node ↔ macmini7).

2. **На work-node** ACCEPT для 10.42/10.43 мають стояти **перед** KUBE-ROUTER-FORWARD. Якщо першим йде KUBE-ROUTER-FORWARD — трафік від подів до CoreDNS відкидається. Вставити правила на початок FORWARD:
   ```bash
   sudo iptables -I FORWARD 1 -d 10.43.0.0/16 -j ACCEPT
   sudo iptables -I FORWARD 1 -s 10.43.0.0/16 -j ACCEPT
   sudo iptables -I FORWARD 1 -d 10.42.0.0/16 -j ACCEPT
   sudo iptables -I FORWARD 1 -s 10.42.0.0/16 -j ACCEPT
   ```
   Перевірка: `sudo iptables -L FORWARD -n -v | head -12` — спочатку мають бути 4× ACCEPT, потім KUBE-ROUTER-FORWARD.

3. **DNS по TCP** (щоб виключити проблему лише з UDP): з пода на work-node спробувати `dig @10.43.0.10 kubernetes.default.svc.cluster.local +tcp` (образ з dig) або перезапустити CoreDNS і повторити nslookup.

4. **Якщо після правил на обох нодах DNS все ще таймаутить** — перевірити маршрутизацію та reverse path filter:
   - **На work-node** маршрут до пода CoreDNS (на macmini7): `ip route get 10.42.0.179` — має бути маршрут через flannel/overlay (не "Network is unreachable").
   - **rp_filter**: якщо ядро відкидає пакети через reverse path (відповідь приходить іншим шляхом, ніж запит), DNS може «висити». На work-node та macmini7 перевірити: `sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter`. Якщо значення `1` (strict), спробувати на інтерфейсі overlay (flannel.1, vxlan тощо) або globally: `sudo sysctl -w net.ipv4.conf.all.rp_filter=2` та `net.ipv4.conf.default.rp_filter=2` (2 = loose). Після перевірки — зберегти в `/etc/sysctl.d/` якщо потрібно постійно.

### 5.2 API по IP з worker-ноди

1. На worker-ноді запустіть тестовий под і зверніться до API:

   ```bash
   kubectl run test-curl --rm -it --restart=Never --image=curlimages/curl -- \
     curl -k -s -o /dev/null -w "%{http_code}" https://10.43.0.1:443/healthz
   ```

   Очікується HTTP 200 або 403 (головне — не "connection refused" і не "no route to host").

2. Перезапустіть поди, які раніше не могли достукатися до API (наприклад Promtail):

   ```bash
   kubectl -n monitoring delete pod -l app=promtail
   kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
   ```

3. У логах не повинно бути "no route to host" або DNS timeout:

   ```bash
   kubectl -n monitoring logs -l app=promtail --tail=20
   ```

---

## 6. Після виправлення доступу до API

- Можна **прибрати nodeSelector** з Promtail DaemonSet, щоб логи збиралися з усіх нод: у `manifests/monitoring/promtail/daemonset.yaml` видаліть блок `nodeSelector: kubernetes.io/hostname: master-node`.
- За потреби поверніть планування CoreDNS на всі ноди (прибрати nodeAffinity з `manifests/coredns`).
- Перевірте інші компоненти (Traefik, Prometheus тощо), які були прив’язані до master-node через цю ж проблему.

---

## Короткий чеклист

| Крок | Де | Дія |
|------|-----|------|
| 1 | Всі ноди | firewalld: `trusted` для 10.42.0.0/16 і 10.43.0.0/16 |
| 2 | Master | firewalld: порт 6443/tcp відкритий |
| 3 | Або iptables | FORWARD/INPUT не блокують 10.42/16, 10.43/16; на master — 6443 |
| 4 | Всі ноди | Після змін: перезапуск k3s/k3s-agent за потреби |
| 5 | Кластер | Тест подом: `curl -k https://10.43.0.1:443/healthz` з пода на worker |

Якщо після цих кроків "no route to host" лишається — варто переглянути маршрути (CNI), MTU та мережеву конфігурацію між нодами (VLAN, VPN, окремі інтерфейси тощо).
