# Помилка: peer-server-client.crt: no such file or directory

**Повідомлення в логах k3s (master-node, macmini7):**
```
rejected connection on peer endpoint ... "error":"open /var/lib/rancher/k3s/server/tls/etcd/peer-server-client.crt: no such file or directory"
```

Це **не** помилка TLS SAN (не "does not match DNSNames"). Etcd на цій ноді не може відкрити файл сертифіката для перевірки peer-з'єднань — файл відсутній або не створений після `certificate rotate --service etcd`.

---

## 1. Діагностика

На ноді, де з’являється помилка (master-node або macmini7):

```bash
sudo ls -la /var/lib/rancher/k3s/server/tls/etcd/
```

Перевірте, чи є там:
- `server-ca.crt`
- `server-client.crt`, `server-client.key`
- **`peer-server-client.crt`**, **`peer-server-client.key`** — саме їх не вистачає.

У частині версій k3s після `k3s certificate rotate --service etcd` etcd очікує саме `peer-server-client.crt`; іноді генеруються тільки `server-client.crt`. Тоді допомагає симлінк або повторний rotate.

### Якщо в каталозі тільки CA (peer-ca, server-ca) — немає server-client і peer-server-client

Симлінк (Варіант A) **не підходить**. Потрібно або згенерувати сертифікати через **rotate** (Варіант B), або тимчасово взяти їх з робочої ноди (Варіант C), потім обов’язково виконати `k3s certificate rotate --service etcd` на цій ноді.

---

## 2. Варіант A: Симлінк server-client → peer-server-client (швидкий обхід)

Якщо в каталозі є **server-client.crt** і **server-client.key**, але немає **peer-server-client.crt** / **peer-server-client.key**, можна тимчасово зробити симлінки (перевірено для частини збірок k3s):

```bash
# На ноді, де помилка (master-node або macmini7)
cd /var/lib/rancher/k3s/server/tls/etcd/

# Якщо peer-server-client.crt відсутній, а server-client.crt є:
sudo ln -sf server-client.crt peer-server-client.crt
sudo ln -sf server-client.key peer-server-client.key

# Перезапуск k3s
sudo systemctl restart k3s
```

Після перезапуску перевірте логи: `journalctl -u k3s -f` — помилка "no such file or directory" має зникнути. Якщо з’являться інші (наприклад, TLS SAN), їх треба вирішувати окремо (див. **ETCD_RECOVERY_TLS_SAN_CURRENT.md**).

---

## 3. Варіант B: Rotate etcd (згенерувати клієнтські сертифікати)

Якщо є **тільки CA** (немає server-client / peer-server-client), спочатку спробуйте згенерувати сертифікати:

```bash
# 1) tls-san у config (див. ETCD_RECOVERY_TLS_SAN_CURRENT.md)
cat /etc/rancher/k3s/config.yaml

# 2) Зупинити k3s
sudo systemctl stop k3s

# 3) Спробувати згенерувати etcd-сертифікати (частина версій k3s робить це офлайн по CA)
sudo k3s certificate rotate --service etcd

# 4) Перевірити
ls -la /var/lib/rancher/k3s/server/tls/etcd/
# Якщо з’явилися server-client.crt і peer-server-client.crt (або лише server-client) — запустити k3s
sudo systemctl start k3s
# Якщо є тільки server-client — після старту зробити симлінки (Варіант A) і restart.
```

Якщо після `rotate` при зупиненому k3s файли **не створилися**, перейдіть до Варіанту C: скопіювати etcd TLS з ноди, де вони є (наприклад beelinkeqr5), запустити k3s, одразу виконати на цій ноді `k3s certificate rotate --service etcd`.

---

## 4. Варіант C: Копіювання etcd TLS з іншої ноди (коли rotate не створив файли)

Спочатку на ноді, де k3s і etcd працюють (наприклад **beelinkeqr5**), перевірте наявність клієнтських сертифікатів:

```bash
ls -la /var/lib/rancher/k3s/server/tls/etcd/
# Потрібні: server-client.crt, server-client.key, peer-server-client.crt, peer-server-client.key (або хоча б server-client.*)
```

Якщо там повний набір, **тимчасово** скопіюйте весь каталог `/var/lib/rancher/k3s/server/tls/etcd/` з beelinkeqr5 на master-node та macmini7 (наприклад через scp), потім на кожній пошкодженій ноді запустіть k3s і одразу виконайте `certificate rotate` на цій ноді. У такому випадку сертифікати будуть від іншої ноди (неправильні SAN для цієї ноди), тому після першого успішного старту **обов’язково** виконайте на цій ноді:

```bash
sudo k3s certificate rotate --service etcd
```

щоб перевипустити сертифікати вже з правильними SAN для поточної ноди.

---

## Підсумок

| Ситуація | Дія |
|----------|-----|
| Є `server-client.crt`, немає `peer-server-client.crt` | Варіант A (симлінк), потім перезапуск k3s. |
| Нічого не допомагає, потрібно швидко підняти ноду | Варіант C (копія з іншої ноди), одразу після старту — `certificate rotate --service etcd` на цій ноді. |
| Після rotate з’явилися файли | Варіант B достатній; перезапуск k3s після rotate. |

Після усунення "no such file or directory" якщо з’являться помилки типу "does not match DNSNames" — орієнтуйтеся на **ETCD_RECOVERY_TLS_SAN_CURRENT.md** (tls-san на всіх control-plane нодах).
