# Зміна IP control-plane ноди (beelinkeqr5): оновлення peer URL в etcd

Якщо на ноді **beelinkeqr5** змінилася IP з **192.168.2.155** на **192.168.2.95** (наприклад після переходу з Wi‑Fi на Ethernet), k3s на beelinkeqr5 не зможе приєднатися до etcd: в кластері цей член зареєстрований як `beelinkeqr5-f65cf434=https://192.168.2.155:2380`, а локально k3s очікує `https://192.168.2.95:2380`.

**Помилка в логах (beelinkeqr5):**
```
Failed to test etcd connection: this server is a not a member of the etcd cluster.
Found [..., beelinkeqr5-f65cf434=https://192.168.2.155:2380], expect: beelinkeqr5-f65cf434=https://192.168.2.95:2380
```

**Рішення:** оновити peer URL члена etcd **з іншої** control-plane ноди (macmini7 або master-node), потім перезапустити k3s на beelinkeqr5.

---

## 1. На macmini7 або master-node (де k3s і etcd працюють)

### 1.1 Список членів etcd

```bash
sudo k3s etcdctl member list
```

Приклад виводу:
```
..., started, beelinkeqr5-f65cf434, https://192.168.2.155:2380, https://192.168.2.155:2380
```

Перше поле (hex, наприклад `a1b2c3d4e5f67890`) — **member ID**. Знайдіть рядок з `192.168.2.155:2380` і збережіть цей ID.

Якщо `k3s etcdctl` недоступний, використовуйте etcdctl з сертифікатами k3s (див. розділ 2).

### 1.2 Оновити peer URL для beelinkeqr5

Підставте **MEMBER_ID** (hex з кроку 1.1) та нову IP **192.168.2.95**. Peer URL передається через прапорець **`--peer-urls`** (не другим аргументом):

```bash
sudo k3s etcdctl member update MEMBER_ID --peer-urls="https://192.168.2.95:2380"
```

Приклад (MEMBER_ID для beelinkeqr5 з вашого виводу — **86093c4df29ebc77**):
```bash
etcdctl member update 86093c4df29ebc77 --peer-urls="https://192.168.2.95:2380"
```
Якщо використовуєте `k3s etcdctl`: `sudo k3s etcdctl member update 86093c4df29ebc77 --peer-urls="https://192.168.2.95:2380"`.

Після успіху виводу може не бути або з’явиться оновлений список.

### 1.3 Перевірити

```bash
sudo k3s etcdctl member list
```

У рядку beelinkeqr5 має бути `https://192.168.2.95:2380`.

---

## 2. Якщо `k3s etcdctl` не працює: etcdctl з сертифікатами

На macmini7 або master-node встановіть etcdctl (відповідна версія etcd, наприклад 3.5.x) і виконайте:

```bash
export ETCDCTL_API=3
export ETCDCTL_ENDPOINTS='https://127.0.0.1:2379'
export ETCDCTL_CACERT='/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt'
export ETCDCTL_CERT='/var/lib/rancher/k3s/server/tls/etcd/server-client.crt'
export ETCDCTL_KEY='/var/lib/rancher/k3s/server/tls/etcd/server-client.key'

# Список (знайти MEMBER_ID для 192.168.2.155)
etcdctl member list

# Оновити (підставити справжній MEMBER_ID; обовʼязково --peer-urls=)
etcdctl member update MEMBER_ID --peer-urls="https://192.168.2.95:2380"
```

У новіших k3s etcd може слухати клієнтські з’єднання на порту **2382** замість 2379 — тоді використовуйте `ETCDCTL_ENDPOINTS='https://127.0.0.1:2382'`.

---

## 3. На beelinkeqr5: перезапустити k3s

Після оновлення peer URL на іншій ноді:

```bash
sudo systemctl restart k3s
sudo systemctl status k3s
```

У логах не повинно з’являтися «this server is a not a member of the etcd cluster». Через 1–2 хвилини перевірте з іншої ноди:

```bash
kubectl get nodes -o wide
```

beelinkeqr5 має бути Ready з INTERNAL-IP **192.168.2.95**.

---

## 4. Підсумок

| Крок | Де | Дія |
|------|-----|-----|
| 1 | macmini7 або master-node | `sudo k3s etcdctl member list` → знайти MEMBER_ID для 192.168.2.155 |
| 2 | macmini7 або master-node | `sudo k3s etcdctl member update MEMBER_ID --peer-urls="https://192.168.2.95:2380"` |
| 3 | beelinkeqr5 | `sudo systemctl restart k3s` |
| 4 | будь-де з kubectl | `kubectl get nodes` — beelinkeqr5 Ready, 192.168.2.95 |

Після цього node-exporter та інші поди на beelinkeqr5 будуть показувати нову IP 192.168.2.95.
