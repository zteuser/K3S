# Помилки "prober detected unhealthy … remote-peer-id: 48c9a1862f44c505 … error: EOF" на beelinkeqr5

**Симптоми в логах (beelinkeqr5):**

```
prober detected unhealthy status, round-tripper-name:ROUND_TRIPPER_RAFT_MESSAGE, remote-peer-id:48c9a1862f44c505, rtt:1.02...s, error:EOF
prober detected unhealthy status, round-tripper-name:ROUND_TRIPPER_SNAPSHOT, remote-peer-id:48c9a1862f44c505, rtt:1.02...s, error:EOF
```

**Що це означає:** Нода **beelinkeqr5** періодично перевіряє (prober) з’єднання з іншим членом etcd по Raft. **remote-peer-id: 48c9a1862f44c505** — це **macmini7** (192.168.2.19). З’єднання обривається з **EOF** (другий бік закриває або мережа обриває), тому prober вважає піра нездоровим. Високий **rtt** (~1 s) вказує на затримку або таймаути.

**Наслідок:** Якщо зв’язок beelinkeqr5 ↔ macmini7 нестабільний, etcd може не мати кворуму, з’являються "no leader", API — ServiceUnavailable.

---

## 1. Перевірка мережі (beelinkeqr5 → macmini7)

На **beelinkeqr5**:

```bash
# Досяжність хоста
ping -c 3 192.168.2.19

# Порти etcd (2380 — peer, 2379 — client)
nc -zv 192.168.2.19 2380
nc -zv 192.168.2.19 2379
```

- Якщо **Connection refused** — на macmini7 не слухає etcd або firewall блокує.
- Якщо **таймаут** — мережа або firewall між Syhiv17 (beelinkeqr5) та VRN625 (macmini7) не пропускає порти 2379/2380.

---

## 2. macmini7: k3s та порти

На **macmini7**:

```bash
sudo systemctl status k3s
ss -tlnp | grep -E '2379|2380|2382'
```

Переконайтеся, що k3s працює і etcd слухає на 2380 (і за потреби 2379/2382).

---

## 3. Firewall

**На macmini7** дозволити вхід з IP beelinkeqr5 (**192.168.1.19**) на порти etcd:

```bash
# ufw
sudo ufw allow from 192.168.1.19 to any port 2379 proto tcp
sudo ufw allow from 192.168.1.19 to any port 2380 proto tcp
sudo ufw reload
```

Якщо трафік йде через тунелі (WireGuard) і source IP не 192.168.1.19, а інша (наприклад 192.168.100.2), дозволити цю підмережу/адресу. Перевірити source IP можна в логах macmini7 при "rejected connection" (remote-addr).

**На beelinkeqr5** переконатися, що вихід на 192.168.2.19:2379,2380 не блокується.

---

## 4. TLS SAN (rejected connection → EOF)

Якщо macmini7 **відхиляє** з’єднання через TLS (SAN не збігається з source IP), клієнт може отримати закриття з’єднання — у логах beelinkeqr5 це виглядає як **EOF**.

На **macmini7** перевірити логи при спробі підключення з beelinkeqr5:

```bash
sudo journalctl -u k3s -n 200 --no-pager | grep -E 'rejected|2380|tls|SAN'
```

Якщо є "rejected connection" або "does not match any of DNSNames" — на ноді, **з якої підключаються** (beelinkeqr5), у etcd peer-сертифікаті має бути **tls-san** для тієї **source IP**, яку бачить macmini7 (у логах — **remote-addr**, напр. 192.168.200.2). Додайте цю IP в `/etc/rancher/k3s/config.yaml` на beelinkeqr5. Детально: **[FIX_ETCD_TLS_RECOVERY.md](./FIX_ETCD_TLS_RECOVERY.md)**. Після змін tls-san на beelinkeqr5 потрібні:

```bash
# На beelinkeqr5
sudo k3s certificate rotate --service etcd
sudo systemctl restart k3s
```

---

## 5. Peer URL у etcd

Якщо peer URL для macmini7 в etcd вказує на адресу, яка не досяжна з beelinkeqr5 (наприклад помилкова або стара), з’єднання може падати з EOF.

На **macmini7** (або master-node, де є кворум):

```bash
sudo k3s etcdctl member list
```

Знайти рядок з **48c9a1862f44c505** (macmini7) і перевірити **peer URL**. Має бути адреса, за якою beelinkeqr5 реально досягає macmini7 (зазвичай **https://192.168.2.19:2380**). Якщо там інший IP — оновити:

```bash
sudo k3s etcdctl member update 48c9a1862f44c505 --peer-urls="https://192.168.2.19:2380"
```

Перед зміною переконайтеся з beelinkeqr5: `nc -zv 192.168.2.19 2380` — succeeded. Деталі по зміні peer URL: **[FIX_ETCD_MEMBER_IP_CHANGE.md](./FIX_ETCD_MEMBER_IP_CHANGE.md)**, **[FIX_ETCD_TLS_RECOVERY.md](./FIX_ETCD_TLS_RECOVERY.md)**.

---

## 6. Маршрути та стабільність каналу

Трафік beelinkeqr5 (Syhiv17) ↔ macmini7 (VRN625) йде через роутери/тунелі. Якщо канал перевантажений або нестабільний, можливі таймаути і обриви (EOF). Варто перевірити:

- Втрати: `ping -c 50 192.168.2.19` з beelinkeqr5.
- Чи не блокує провайдер/роутер порти 2379, 2380.

---

## Підсумок

| Крок | Де | Дія |
|------|-----|-----|
| 1 | beelinkeqr5 | `ping 192.168.2.19`, `nc -zv 192.168.2.19 2380` (і 2379) |
| 2 | macmini7 | `systemctl status k3s`, `ss -tlnp \| grep 2380` |
| 3 | macmini7 | Firewall: дозволити з 192.168.1.19 (або фактичний source IP) на 2379, 2380 |
| 4 | macmini7 / beelinkeqr5 | Якщо в логах macmini7 є "rejected" — виправити tls-san (FIX_ETCD_TLS_RECOVERY), rotate etcd cert на beelinkeqr5 |
| 5 | macmini7 | `k3s etcdctl member list` → перевірити peer URL для 48c9a1862f44c505 (macmini7), при потребі `member update` |

Після виправлення мережі/TLS/peer URL перезапустити k3s на beelinkeqr5 і перевірити логи: попередження "prober detected unhealthy … 48c9a1862f44c505 … EOF" мають зникнути або рідшати.
