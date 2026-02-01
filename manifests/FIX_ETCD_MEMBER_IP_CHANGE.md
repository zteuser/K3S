# Зміна IP control-plane ноди (beelinkeqr5): оновлення peer URL в etcd

Якщо на ноді **beelinkeqr5** змінилася IP (наприклад після **переїзду на локацію Syhiv17** — з 192.168.2.x на **192.168.1.19**), k3s на beelinkeqr5 не зможе приєднатися до etcd: в кластері цей член зареєстрований зі старим peer URL (наприклад `https://192.168.2.95:2380` або `https://192.168.2.155:2380`), а локально k3s очікує `https://192.168.1.19:2380`.

**Помилка в логах (beelinkeqr5):**
```
Failed to test etcd connection: this server is a not a member of the etcd cluster.
Found [..., beelinkeqr5-...=https://СТАРИЙ_IP:2380], expect: beelinkeqr5-...=https://192.168.1.19:2380
```

**Рішення:** оновити peer URL члена etcd **з іншої** control-plane ноди (macmini7 або master-node), потім перезапустити k3s на beelinkeqr5.

---

## 1. На macmini7 або master-node (де k3s і etcd працюють)

### 1.1 Список членів etcd

```bash
sudo k3s etcdctl member list
```

Приклад виводу (старий IP — будь-який з 192.168.2.x, наприклад 192.168.2.95 або 192.168.2.155):
```
..., started, beelinkeqr5-..., https://192.168.2.95:2380, https://192.168.2.95:2380
```

Перше поле (hex, наприклад `a1b2c3d4e5f67890`) — **member ID**. Знайдіть рядок з **beelinkeqr5** і старим IP (192.168.2.x) у peer URL — збережіть цей ID.

Якщо `k3s etcdctl` недоступний, використовуйте etcdctl з сертифікатами k3s (див. розділ 2).

### 1.2 Оновити peer URL для beelinkeqr5

Підставте **MEMBER_ID** (hex з кроку 1.1) та **нову IP beelinkeqr5** — **192.168.1.19** (локація Syhiv17). Peer URL передається через прапорець **`--peer-urls`** (не другим аргументом):

```bash
sudo k3s etcdctl member update MEMBER_ID --peer-urls="https://192.168.1.19:2380"
```

Приклад (MEMBER_ID для beelinkeqr5 з вашого виводу — **86093c4df29ebc77**):
```bash
sudo k3s etcdctl member update 86093c4df29ebc77 --peer-urls="https://192.168.1.19:2380"
```

Після успіху виводу може не бути або з’явиться оновлений список.

### 1.3 Перевірити

```bash
sudo k3s etcdctl member list
```

У рядку beelinkeqr5 має бути `https://192.168.1.19:2380`.

---

## 2. Якщо `k3s etcdctl` не працює: etcdctl з сертифікатами k3s

У багатьох збірках k3s **немає** підкоманди `k3s etcdctl` (помилка "No help topic for 'etcdctl'"). Використовуйте звичайний **etcdctl** з сертифікатами k3s. Сертифікати лежать у `/var/lib/rancher/k3s/server/tls/etcd/`, тому команди потрібно виконувати через **sudo**.

**Спочатку перевірте, на якому порту слухає etcd (на macmini7):**
```bash
sudo ss -tlnp | grep -E '2379|2380|2382'
```
Якщо бачите тільки 2380 — клієнтський порт може бути **2382** (k3s часто використовує 2382 для etcd client). Спробуйте спочатку 2379, якщо не працює — 2382.

**Список членів та оновлення (підставте порт 2379 або 2382):**
```bash
sudo env ETCDCTL_API=3 \
  ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl member list
```

Якщо отримаєте **"connection closed"** або **"context deadline exceeded"**, спробуйте порт **2382**:
```bash
sudo env ETCDCTL_API=3 \
  ETCDCTL_ENDPOINTS='https://127.0.0.1:2382' \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl member list
```

Після того як отримаєте список — знайдіть MEMBER_ID для beelinkeqr5 (рядок зі старим IP 192.168.2.x) і оновіть peer URL. **Обовʼязково** передайте ті самі змінні середовища (endpoint і сертифікати), інакше `member update` підключиться без TLS і отримає "connection closed" / "context deadline exceeded":
```bash
sudo env ETCDCTL_API=3 \
  ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl member update MEMBER_ID --peer-urls="https://192.168.1.19:2380"
```
Приклад для beelinkeqr5 (MEMBER_ID 86093c4df29ebc77):
```bash
sudo env ETCDCTL_API=3 \
  ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl member update 86093c4df29ebc77 --peer-urls="https://192.168.1.19:2380"
```

**Примітка:** якщо etcd не відповідає ні на 2379, ні на 2382 (connection closed / deadline exceeded), ймовірно **немає кворуму** (при двох нодах обидві мають бути доступні). Див. розділ 5 нижче.

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

beelinkeqr5 має бути Ready з INTERNAL-IP **192.168.1.19**.

---

## 4. Підсумок

| Крок | Де | Дія |
|------|-----|-----|
| 1 | macmini7 або master-node | `sudo k3s etcdctl member list` → знайти MEMBER_ID для beelinkeqr5 (старий IP 192.168.2.x) |
| 2 | macmini7 або master-node | `sudo k3s etcdctl member update MEMBER_ID --peer-urls="https://192.168.1.19:2380"` |
| 3 | beelinkeqr5 | `sudo systemctl restart k3s` |
| 4 | будь-де з kubectl | `kubectl get nodes` — beelinkeqr5 Ready, 192.168.1.19 |

Після цього node-exporter та інші поди на beelinkeqr5 будуть показувати нову IP 192.168.1.19 (локація Syhiv17). Оновіть також Prometheus configmap: замініть 192.168.2.95 на 192.168.1.19 у job kubernetes-nodes та node-exporter.

---

## 5. Якщо etcd не відповідає (connection closed / context deadline exceeded)

Якщо на macmini7 `etcdctl member list` з сертифікатами k3s (розділ 2) повертає **"connection closed"** або **"context deadline exceeded"** і на портах 2379 та 2382 нічого не змінюється — ймовірно **немає кворуму**: при двох server-нодах etcd потребує обидві ноди; beelinkeqr5 за старим IP недоступна, тому etcd на macmini7 не обирає лідера і може не приймати клієнтські запити.

**Що зробити:**

1. **Перевірити, чи etcd взагалі слухає:**  
   `sudo ss -tlnp | grep -E '2379|2380|2382'` — якщо порти є, але etcdctl все одно не підключається, це підтверджує відсутність кворуму.

2. **Єдиний надійний варіант без кворуму:** відновити кластер з **однієї** ноди (macmini7) з останнього etcd-снепшоту, потім **заново приєднати** beelinkeqr5 з новою IP 192.168.1.19.
   - На macmini7: зробити backup, виконати `k3s server --cluster-reset --cluster-reset-restore-path=...` з останнім снепшотом (див. офіційну документацію k3s «Restoring from backup»).
   - Після перезапуску k3s на macmini7 кластер буде з однієї ноди.
   - На beelinkeqr5 (192.168.1.19): перевстановити k3s у режимі server з `--server https://192.168.2.19:6443` (join до macmini7). Etcd автоматично зареєструє beelinkeqr5 з новою адресою 192.168.1.19.
   - Детальні кроки cluster-reset та re-join — у документації k3s та в матеріалах по backup/restore.
