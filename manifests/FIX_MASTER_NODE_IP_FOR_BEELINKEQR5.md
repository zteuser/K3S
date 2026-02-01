# master-node: Internal-IP недоступна з beelinkeqr5 — використання 10.0.10.10

**Проблема:** На ноді **beelinkeqr5** (Syhiv17, 192.168.1.19) нода **master-node** має Internal-IP **192.168.100.5**, яка з beelinkeqr5 **недоступна** (ping 192.168.100.5 — 100% packet loss). При цьому з beelinkeqr5 доступні 192.168.100.1, 192.168.100.2 та **10.0.10.10** (OCI VLAN). Це ламає з’єднання до kubelet/подів на master-node, якщо кластер використовує Node IP для доступу.

**Рішення:** На **master-node** задати оголошення Node IP через **10.0.10.10** (досяжний з beelinkeqr5), щоб у Kubernetes нода master-node мала Internal-IP 10.0.10.10 замість 192.168.100.5.

---

## 1. Перевірка поточного стану

З beelinkeqr5 (або з будь-якої ноди):

```bash
kubectl get nodes -o wide
# master-node зараз: INTERNAL-IP 192.168.100.5

ping -c 1 192.168.100.5   # з beelinkeqr5 — не відповідає
ping -c 1 10.0.10.10      # з beelinkeqr5 — має відповідати (якщо це master-node)
```

Переконайтеся, що **10.0.10.10** — це дійсно master-node (хост Amper master на OCI VLAN).

---

## 2. На master-node: задати Node IP 10.0.10.10

K3s визначає Internal-IP ноди з інтерфейсів або з параметра **`--node-ip`** / змінної **`K3S_NODE_IP`** / опції **`node-ip`** у **config.yaml**. Потрібно зафіксувати IP **10.0.10.10**.

**Якщо вже пробували systemd drop-in з `K3S_NODE_IP=10.0.10.10` і Internal-IP лишилася 192.168.100.5:** на багатьох встановленнях k3s читає **config.yaml** і опція **node-ip** там має пріоритет або змінна середовища не застосовується. Використовуйте **Варіант B (config.yaml)** — він найнадійніший.

### Варіант A: systemd override

На **master-node** (SSH або консоль):

```bash
sudo mkdir -p /etc/systemd/system/k3s.service.d
sudo tee /etc/systemd/system/k3s.service.d/node-ip.conf << 'EOF'
[Service]
Environment="K3S_NODE_IP=10.0.10.10"
EOF
sudo systemctl daemon-reload
sudo systemctl restart k3s
sudo systemctl status k3s
```

Якщо після перезапуску `kubectl get nodes -o wide` все ще показує master-node з 192.168.100.5 — перейдіть до **Варіанту B**.

### Варіант B: конфіг k3s (рекомендовано, якщо A не спрацював)

На **master-node** перевірте наявність конфігу і опції **node-ip**:

```bash
cat /etc/rancher/k3s/config.yaml
```

Якщо файлу немає — створіть; якщо є — додайте або **замініть** рядок `node-ip:` на **10.0.10.10** (щоб не залишилося `node-ip: 192.168.100.5`):

```bash
# Якщо config.yaml вже існує — відредагуйте вручну або:
sudo sed -i '/^node-ip:/d' /etc/rancher/k3s/config.yaml   # видалити старий node-ip
echo 'node-ip: 10.0.10.10' | sudo tee -a /etc/rancher/k3s/config.yaml
```

Або вручну відредагуйте `/etc/rancher/k3s/config.yaml` — має бути рядок (лише один):

```yaml
node-ip: 10.0.10.10
```

Потім перезапустіть k3s:

```bash
sudo systemctl restart k3s
```

Через 1–2 хв перевірте: `kubectl get nodes -o wide` — master-node має показувати INTERNAL-IP **10.0.10.10**.

### Варіант C: існуючий ExecStart

Якщо k3s запускається з явним списком аргументів у `ExecStart`, додайте до команди **`--node-ip=10.0.10.10`** (не дублюйте інші `--node-ip`). Після зміни:

```bash
sudo systemctl daemon-reload
sudo systemctl restart k3s
```

---

## 3. Перевірка після перезапуску

Через 1–2 хвилини з будь-якої ноди з kubectl:

```bash
kubectl get nodes -o wide
```

**master-node** має показувати **INTERNAL-IP 10.0.10.10**.

З **beelinkeqr5** перевірте досяжність:

```bash
ping -c 1 10.0.10.10
nc -zv 10.0.10.10 10250   # kubelet
nc -zv 10.0.10.10 6443    # API (якщо слухає на цьому IP)
```

Після цього з’єднання з beelinkeqr5 до master-node (kubelet, поди тощо) будуть йти на 10.0.10.10.

---

## 4. Помилка etcd: "rejected connection" — remote-addr 192.168.100.2

Якщо в логах **на master-node** з’являється:

```text
rejected connection on peer endpoint, remote-addr: 192.168.100.2:...
tls: "192.168.100.2" does not match any of DNSNames [..., beelinkeqr5]
```

**Звідки береться 192.168.100.2:** це **source IP** вхідного з’єднання **до** etcd на master-node. Один із etcd-пірів (**beelinkeqr5** або macmini7) підключається до master-node (10.0.10.10 або 192.168.100.6), але **маршрут** від beelinkeqr5 до master-node проходить через тунель/шлюз з адресою **192.168.100.2**. Тому на master-node пакет приходить з **source IP 192.168.100.2**, а не 192.168.1.19. Etcd перевіряє клієнтський сертифікат піра: у сертифікаті beelinkeqr5 є лише beelinkeqr5 / 192.168.1.19, а не 192.168.100.2 — тому з’єднання **rejected**.

**Щоб прибрати помилку без зміни маршрутів:** додати **192.168.100.2** до SAN etcd peer-сертифіката на тій ноді, чий трафік з’являється як 192.168.100.2 (найімовірніше **beelinkeqr5**). Див. розділ 4.1 нижче.

**Якщо хочете, щоб 192.168.100.2 не використовувалась:** змінити маршрути так, щоб трафік від beelinkeqr5 до 10.0.10.10 йшов напряму (source 192.168.1.19), а не через шлюз 192.168.100.2.

**Кроки:** оновити в etcd **peer URL master-node** з `https://192.168.100.5:2380` на **`https://10.0.10.10:2380`**. Виконувати на **macmini7** (або будь-якій ноді, де etcd відповідає):

```bash
# 1. Список членів — знайти MEMBER_ID для master-node (рядок з 192.168.100.5:2380)
sudo env ETCDCTL_API=3 \
  ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl member list
```

У виводі знайдіть рядок **master-node** з `https://192.168.100.5:2380` і скопіюйте **перше поле (MEMBER_ID**, hex, наприклад `2a512d942904b402`).

```bash
# 2. Оновити peer URL master-node на 10.0.10.10 (підставте справжній MEMBER_ID)
sudo env ETCDCTL_API=3 \
  ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl member update MEMBER_ID_MASTER_NODE --peer-urls="https://10.0.10.10:2380"
```

Приклад для MEMBER_ID master-node з вашого кластера (**2a512d942904b402**):

```bash
sudo env ETCDCTL_API=3 \
  ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl member update 2a512d942904b402 --peer-urls="https://10.0.10.10:2380"
```

Після оновлення перезапустіть k3s **на master-node**, щоб він використовував новий peer URL:

```bash
# На master-node
sudo systemctl restart k3s
```

Через 1–2 хв перевірте логи на master-node — повідомлення про "192.168.100.2 does not match" мають зникнути; піри будуть підключатися до 10.0.10.10, source IP буде 192.168.1.19 / 192.168.2.19.

### 4.1 Якщо після оновлення peer URL помилка "192.168.100.2 does not match" лишається

Якщо маршрут від **beelinkeqr5** (або macmini7) до master-node **10.0.10.10** все одно проходить через шлюз **192.168.100.2**, то на master-node вхідне з’єднання матиме source IP 192.168.100.2 і etcd відхилятиме його (TLS: сертифікат піра не містить 192.168.100.2).

**Рішення:** додати **192.168.100.2** до SAN etcd peer-сертифіката на **beelinkeqr5** (і на macmini7, якщо його трафік теж приходить з 192.168.100.2).

**На beelinkeqr5 (192.168.1.19):**

```bash
# 1. Додати tls-san у конфіг
echo 'tls-san: 192.168.100.2' | sudo tee -a /etc/rancher/k3s/config.yaml

# 2. Перегенерувати etcd-сертифікати
sudo k3s certificate rotate --service etcd

# 3. Перезапустити k3s
sudo systemctl restart k3s
```

Після цього etcd на master-node прийматиме з’єднання з source 192.168.100.2 (сертифікат beelinkeqr5 міститиме цю адресу в SAN). Якщо macmini7 теж підключається через 192.168.100.2 — повторити аналогічно на macmini7.

---

## 5. Примітка про etcd (загальна)

Після зміни Node IP на 10.0.10.10 варто також оновити **etcd peer URL** master-node на 10.0.10.10:2380 (розділ 4 вище), інакше піри досі з’єднуються з 192.168.100.5, трафік йде через тунель (source 192.168.100.2) і etcd відхиляє з’єднання.

---

## 6. Підсумок

| Крок | Де | Дія |
|------|-----|-----|
| 1 | master-node | Додати `K3S_NODE_IP=10.0.10.10` (override або config.yaml / --node-ip) |
| 2 | master-node | `sudo systemctl restart k3s` |
| 3 | будь-де | `kubectl get nodes -o wide` — master-node має INTERNAL-IP 10.0.10.10 |
| 4 | beelinkeqr5 | `ping 10.0.10.10`, `nc -zv 10.0.10.10 10250` — мають працювати |

Після цього нода master-node буде доступна з beelinkeqr5 за адресою 10.0.10.10.
