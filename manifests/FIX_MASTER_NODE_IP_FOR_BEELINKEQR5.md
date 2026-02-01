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

K3s визначає Internal-IP ноди з інтерфейсів або з параметра **`--node-ip`** / змінної **`K3S_NODE_IP`**. Потрібно зафіксувати IP **10.0.10.10**.

### Варіант A: systemd override (рекомендовано)

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

### Варіант B: конфіг k3s

Якщо k3s вже використовує конфіг (наприклад `/etc/rancher/k3s/config.yaml`), додайте туди:

```yaml
node-ip: 10.0.10.10
```

Потім перезапустіть k3s:

```bash
sudo systemctl restart k3s
```

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

## 4. Примітка про etcd

У **etcd** master-node залишається з peer URL **https://192.168.100.5:2380**. Цей документ змінює лише **Kubernetes Node IP** (Internal-IP у `kubectl get nodes`). Якщо потрібно, щоб etcd на master-node був доступний з beelinkeqr5 по 10.0.10.10, це окрема зміна (оновлення peer URL в etcd та конфіг etcd на master-node); для доступу до kubelet і подів на master-node достатньо зміни Node IP на 10.0.10.10.

---

## 5. Підсумок

| Крок | Де | Дія |
|------|-----|-----|
| 1 | master-node | Додати `K3S_NODE_IP=10.0.10.10` (override або config.yaml / --node-ip) |
| 2 | master-node | `sudo systemctl restart k3s` |
| 3 | будь-де | `kubectl get nodes -o wide` — master-node має INTERNAL-IP 10.0.10.10 |
| 4 | beelinkeqr5 | `ping 10.0.10.10`, `nc -zv 10.0.10.10 10250` — мають працювати |

Після цього нода master-node буде доступна з beelinkeqr5 за адресою 10.0.10.10.
