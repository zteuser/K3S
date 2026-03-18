# Відновлення etcd кворуму після міграції

## Діагноз

**master-node** (10.0.10.10) не може досягти etcd peer на **macmini7** (192.168.2.19) та **beelinkeqr5** (192.168.1.19):

```
dial tcp 192.168.1.19:2380: i/o timeout
dial tcp 192.168.2.19:2380: i/o timeout
```

etcd потребує **2 з 3** нод для кворуму. Зараз master-node один — кворуму немає, API не працює.

---

## Причина

Після зупинки k3s на всіх нодах:
- **macmini7** та **beelinkeqr5** могли не запуститися або недоступні через мережу
- **WireGuard/OSPF** — master-node (OCI) має досягати 192.168.1.19 та 192.168.2.19 через тунелі

---

## Кроки відновлення

### 1. Потрібен доступ до мережі 192.168.x

Ви маєте бути в мережі, де доступні macmini7 та beelinkeqr5 (наприклад, LAN VRN625/Syhiv17 або VPN).

### 2. Перевірити та запустити k3s на macmini7 та beelinkeqr5

```bash
# macmini7 (192.168.2.19)
ssh malex@192.168.2.19 'sudo systemctl status k3s'
ssh malex@192.168.2.19 'sudo systemctl start k3s'   # якщо stopped

# beelinkeqr5 (192.168.1.19)
ssh malex@192.168.1.19 'sudo systemctl status k3s'
ssh malex@192.168.1.19 'sudo systemctl start k3s'   # якщо stopped
```

### 3. Перевірити досяжність з master-node до peer

З **master-node** (або з машини в тій же мережі):

```bash
# З master-node
ssh malex@10.0.10.10
nc -zv 192.168.2.19 2380
nc -zv 192.168.1.19 2380
```

Якщо timeout — перевірити WireGuard, OSPF, маршрути на роутерах.

### 4. Після відновлення кворуму

Коли etcd матиме кворум (2+ ноди), API почне відповідати:

```bash
kubectl get nodes
```

### 5. Далі — Cilium

Після відновлення кластера перевірити Cilium та work-node:

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
ssh malex@10.0.10.20 'sudo systemctl start k3s-agent'   # work-node
```

---

## Якщо ви не в мережі 192.168.x

Потрібен хтось на місці (VRN625/Syhiv17) або підключення через VPN до цієї мережі, щоб:
1. Перевірити, чи працюють macmini7 та beelinkeqr5
2. Запустити k3s на них
3. Перевірити WireGuard/маршрути
