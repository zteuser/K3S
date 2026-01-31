# Додавання другої control-plane ноди (secondary master + etcd) у k3s

Інструкція для додавання ноди **192.168.2.155** (Ubuntu 24) у роль **control-plane** (secondary master) з **etcd**. Після цього кластер матиме два сервери з API, scheduler, controller-manager та спільним etcd-кластером.

## Передумови

1. **Перший master** уже працює з k3s у режимі server (з embedded etcd).
2. Для HA з кількома control-plane перший сервер має бути запущений з прапорцем **`--cluster-init`**. Якщо встановлювали без нього — перевірте на першому сервері:
   ```bash
   # На першому master
   cat /etc/rancher/k3s/config.yaml
   # або
   systemctl cat k3s
   ```
   Якщо там немає `--cluster-init` і кластер був один-нодний, додавання другого server може вимагати переінсталяції першого з `--cluster-init` (збережіть дані etcd/backup).
3. Нова нода **192.168.2.155** має мережевий доступ до першого master на порт **6443** (TCP).
4. На новій ноді: Ubuntu 24, права sudo.

---

## Крок 1. Отримати token на існуючому master

На **першому** server-вузлі (де вже працює k3s):

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

Збережіть виведений рядок — це **K3S_TOKEN** для join.

Також знайте **IP першого master** — далі він позначається як **&lt;FIRST_SERVER_IP&gt;** (наприклад, якщо master у локальній мережі — це може бути 192.168.2.x або зовнішній IP).

---

## Крок 2. Підготовка нової ноди (192.168.2.155)

Підключіться до нової ноди:

```bash
ssh ubuntu@192.168.2.155
# або ваш користувач
```

Виконайте підготовку (як для будь-якої ноди k3s):

```bash
# Вимкнути swap (рекомендовано для Kubernetes)
sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab

# Модулі ядра для мережі
sudo modprobe overlay
sudo modprobe br_netfilter
echo -e "overlay\nbr_netfilter" | sudo tee /etc/modules-load.d/k3s.conf

# Sysctl
sudo tee /etc/sysctl.d/99-k3s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

Переконайтеся, що з нової ноди є доступ до першого master на 6443:

```bash
curl -k https://<FIRST_SERVER_IP>:6443/healthz
# Очікується: "ok" або JSON з "status": "Failure", "code": 401 (Unauthorized)
# 401 означає, що з’єднання є, API відповідає, але запит без токена — це нормально для перевірки зв’язку.
```

---

## Крок 3. Встановлення k3s у режимі server (control-plane + etcd)

На ноді **192.168.2.155** виконайте (підставте реальні **&lt;FIRST_SERVER_IP&gt;** та **&lt;K3S_TOKEN&gt;**):

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --token <K3S_TOKEN> \
  --server https://<FIRST_SERVER_IP>:6443
```

Ця команда:

- встановить k3s;
- запустить **server** (API server, scheduler, controller-manager, **etcd**);
- приєднає ноду до існуючого кластера через `--server` та `--token`.

Після встановлення k3s запуститься як сервіс `k3s` (не `k3s-agent`).

---

## Крок 4. Перевірка

З будь-якої ноди з налаштованим `kubectl` (наприклад, з першого master):

```bash
kubectl get nodes -o wide
```

Обидва server-ноди мають бути в статусі **Ready** і з ролями **control-plane,etcd,master** (або подібними).

Якщо нова нода показує лише `control-plane,etcd` без `master`, додайте мітку вручну:

```bash
kubectl label node <NEW_NODE_NAME> node-role.kubernetes.io/master=
# Приклад: kubectl label node beelinkeqr5 node-role.kubernetes.io/master=
```

Перевірка etcd-членів (на першому або другому server):

```bash
sudo k3s etcd-snapshot ls
# або перегляд подів
kubectl get pods -n kube-system -l component=etcd
```

Перевірка компонентів control-plane на новій ноді:

```bash
ssh 192.168.2.155 'sudo systemctl status k3s'
```

---

## Крок 5. Firewall (якщо використовується)

На **новій** ноді (192.168.2.155) мають бути відкриті ті самі порти, що й на інших server-нодах, зокрема:

- **6443** — Kubernetes API;
- **2379–2380** — etcd (клієнт та peer);
- потрібні порти для flannel/cni (за замовчуванням k3s сам керує iptables).

Якщо на ноді працює **firewalld**:

```bash
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=2379-2380/tcp
sudo firewall-cmd --reload
```

Якщо **ufw**:

```bash
sudo ufw allow 6443/tcp
sudo ufw allow 2379:2380/tcp
sudo ufw reload
```

На **першому** master має бути дозволено вхід з 192.168.2.155 на 6443 та 2379–2380.

---

## Конфігурація через config-файл (альтернатива)

Замість передачі параметрів у командному рядку можна використати конфіг k3s на новій ноді:

```bash
# Після curl -sfL https://get.k3s.io | sh -s - server
# відредагувати /etc/rancher/k3s/config.yaml
sudo tee /etc/rancher/k3s/config.yaml <<EOF
token: <K3S_TOKEN>
server: https://<FIRST_SERVER_IP>:6443
EOF
sudo systemctl restart k3s
```

Параметри (CIDR, flannel тощо) мають **збігатися** з першим сервером, інакше join може не вдатися.

---

## Troubleshooting

| Проблема | Що перевірити |
|----------|----------------|
| Join не вдається, "connection refused" | Доступ з 192.168.2.155 до &lt;FIRST_SERVER_IP&gt;:6443, firewall на обох нодах. |
| "Managed etcd cluster not yet initialized" | Перший server має бути запущений з `--cluster-init`; перезапустіть k3s на першому і повторіть join. |
| Нода в NotReady | `journalctl -u k3s -f` на 192.168.2.155; перевірка CNI (flannel), маршрутів 10.42.0.0/16. |
| Різні cluster-cidr/service-cidr | На обох server мають бути однакові значення (за замовчуванням 10.42.0.0/16 та 10.43.0.0/16). |

---

## Чи працює кластер при зникненні однієї control-plane ноди?

**Так, але залежить від кількості server-нод.**

| Кількість control-plane (server) | Одна нода зникає | Що відбувається |
|----------------------------------|-------------------|------------------|
| **2 ноди** (як у вас зараз) | API-сервер | Друга нода продовжує приймати запити на 6443 — клієнти (kubectl, поди) можуть звертатися до неї. |
| | **etcd** | При 2 вузлах кворум etcd = 2. Якщо одна нода зникла, друга не має кворуму (потрібно 2 з 2) — etcd перестає приймати **записи**. Кластер може стати read-only: читання працює, створення/оновлення об’єктів (поди, Deployment тощо) — ні, поки нода не повернеться. |
| **3 або більше нод** | API + etcd | Кворум etcd зберігається (наприклад 2 з 3). Кластер залишається **повністю працездатним**: і читання, і запис. |

**Висновок:** при двох control-plane нодах зникнення однієї дає **часткову** працездатність (API доступний з другої ноди, але зміни в кластері можуть не застосовуватися через etcd). Для повноцінного HA при відмові однієї ноди потрібно **3** server-ноди (кворум 2, одна може бути недоступна). Додати третю ноду можна за тими самими кроками, що й другу.

### Що робити, коли одна нода NotReady і API повертає ServiceUnavailable

Якщо одна control-plane нода (наприклад beelinkeqr5) стала **NotReady**, а з другої (macmini7) `kubectl get nodes` дає `ServiceUnavailable` або `connection refused` — це через відсутність кворуму etcd (2 з 2, одна нода недоступна).

**Відновлення:** потрібно знову зробити доступною ноду, що в NotReady.

1. **Доступ до ноди, що в NotReady** (наприклад beelinkeqr5): по SSH або консоль. Перевірити мережу (`ip addr`, `ping` до інших нод), що k3s запущений:
   ```bash
   sudo systemctl status k3s
   sudo journalctl -u k3s -n 50 --no-pager
   ```
2. Якщо k3s не працює — запустити: `sudo systemctl start k3s`.
3. Якщо була зміна мережі (наприклад netplan для двох Ethernet) — переконатися, що нода має маршрут до інших нод і що порти 6443, 2379–2380 не блокуються.
4. Коли нода знову стане **Ready** (`kubectl get nodes` з іншої ноди), etcd отримає кворум і API знову буде обслуговувати запити.

Поки beelinkeqr5 не повернеться в кластер, `kubectl` з macmini7 може не працювати — це очікувана поведінка при двох server-нодах.

### "etcdserver: no leader" та "prober detected unhealthy … remote-peer-id … EOF"

Якщо на beelinkeqr5 в логах: `Failed to test etcd connection: etcdserver: no leader` і `prober detected unhealthy status … remote-peer-id 48c9a1862f44c505 … error EOF` — це означає, що **beelinkeqr5 не може з’єднатися з etcd на другій server-ноді** (macmini7). Без двох живих peer etcd не обирає лідера, API повертає ServiceUnavailable.

**Що перевірити:**

1. **Зв’язок між нодами по портах etcd (2379, 2380)**  
   На beelinkeqr5 (підставте IP macmini7, наприклад 192.168.2.19):
   ```bash
   nc -zv 192.168.2.19 2379
   nc -zv 192.168.2.19 2380
   ```
   Якщо «Connection refused» або таймаут — мережа або firewall блокує.

2. **Firewall на macmini7**  
   Дозволити вхід з IP beelinkeqr5 (наприклад 192.168.2.155) на 2379, 2380:
   ```bash
   sudo ufw allow from 192.168.2.155 to any port 2379 proto tcp
   sudo ufw allow from 192.168.2.155 to any port 2380 proto tcp
   sudo ufw reload
   ```
   (Аналогічно для firewalld: `firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.2.155 port port=2379 protocol=tcp accept'` та для 2380.)

3. **Firewall на beelinkeqr5**  
   Дозволити вихід або не блокувати з’єднання до 2379/2380 на macmini7 (за потреби перевірити правила виходу).

4. **k3s на macmini7**  
   На другій server-ноді переконатися, що k3s працює і слухає 2379/2380:
   ```bash
   sudo systemctl status k3s
   ss -tlnp | grep -E '2379|2380'
   ```

5. **Мережа після змін netplan**  
   Якщо на beelinkeqr5 змінювали мережу (наприклад два Ethernet, DHCP), перевірити, що поточний IP beelinkeqr5 дійсно досяжний з macmini7 (`ping`, `nc` з macmini7 на 2379/2380 до IP beelinkeqr5). Якщо beelinkeqr5 отримала новий IP, інші ноди мають мати до неї маршрут і не блокувати порти.

---

## Підсумок

| Параметр | Значення |
|----------|----------|
| Нова нода | 192.168.2.155 |
| ОС | Ubuntu 24 |
| Роль | control-plane (secondary master), etcd |
| Сервіс | `k3s` (server), не k3s-agent |
| Команда join | `sh -s - server --token <TOKEN> --server https://<FIRST_SERVER_IP>:6443` |

Після успішного join кластер матиме два control-plane + etcd вузли; для etcd рекомендується непарна кількість (1, 3, 5) для кворуму — при потребі можна додати третій server за тими самими кроками.
