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

1. На worker-ноді запустіть тестовий под і зверніться до API:

   ```bash
   kubectl run test-curl --rm -it --restart=Never --image=curlimages/curl -- \
     curl -k -s -o /dev/null -w "%{http_code}" https://10.43.0.1:443/healthz
   ```

   Очікується HTTP 200 або 403 (головне — не "connection refused" і не "no route to host").

2. Перезапустіть поди, які раніше не могли достукатися до API (наприклад Promtail, CoreDNS на worker):

   ```bash
   kubectl -n monitoring delete pod -l app=promtail
   kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
   ```

3. У логах не повинно бути "no route to host":

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
