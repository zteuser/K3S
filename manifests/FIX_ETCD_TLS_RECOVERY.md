# Відновлення etcd: "no leader" та "rejected connection" (TLS SAN)

**Симптоми:**

- **beelinkeqr5:** `watch chan error: etcdserver: no leader`
- **macmini7 / master-node:** k3s не стартує або etcd не формує кворум; в логах — `rejected connection on peer endpoint`, `tls: "192.168.100.x" does not match any of DNSNames [...]`

**Причина:** Трафік між control-plane нодами йде через шлюзи/NAT, тому **source IP** з’єднання до etcd — не власна IP ноди, а адреса шлюзу (192.168.100.2, 192.168.100.5, 192.168.100.6). Etcd перевіряє клієнтський сертифікат піра: якщо цього source IP немає в SAN, з’єднання відхиляється → кворум не формується → "no leader".

**Рішення:** Додати в **tls-san** лише **ті IP, з яких ця нода сама підключається** (source IP її трафіку). Файл на кожній ноді: **`/etc/rancher/k3s/config.yaml`**.

**Важливо:** Кожна нода має мати в tls-san **тільки свої** source IP, а не всі IP кластера. Якщо на одній ноді додати tls-san для всіх (192.168.100.1, .2, .5, .6), це не вирішить "rejected connection": інші ноди підключаються до неї з **своїми** source IP, і їхні сертифікати мають містити ці IP на **тих** нодах.

---

## Яку адресу додати на яку ноду (залежить від маршрутизації)

**Увага:** Конкретні source IP залежать від того, через який роутер/інтерфейс йде трафік. Орієнтуйтеся на **remote-addr** у логах "rejected connection" на тій ноді, де etcd відхиляє з'єднання — цей IP потрібно додати в **tls-san на ноді, яка підключається** (на якій випущений сертифікат з цим DNSNames). **Поточні кроки під ваші логи (master 192.168.100.1, macmini7 192.168.200.6)** — у **ETCD_RECOVERY_TLS_SAN_CURRENT.md**.

| Нода | Приклад tls-san (перевіряйте по логах) | Чому |
| ------------- | ---------------------------- | ------ |
| **beelinkeqr5** | **192.168.100.2** | Коли beelinkeqr5 підключається через Syhiv17, source IP 192.168.100.2 |
| **master-node** | **192.168.100.1** (і/або 192.168.100.5) | Якщо трафік до beelinkeqr5 йде через Syhiv17 (wg0) — beelinkeqr5 бачить 192.168.100.1; через VRN625 (wg1) — 192.168.100.5 |
| **macmini7**    | **192.168.200.6** (і/або 192.168.100.10, 192.168.100.1) | Якщо трафік до beelinkeqr5 йде через VRN625 — beelinkeqr5 бачить 192.168.200.6 |

Усі зміни — лише в **config.yaml** на кожній ноді; перезапуск k3s потрібен після змін.

---

## Крок 1. Додати tls-san на всіх трьох нодах (без перезапуску)

Виконати на **кожній** ноді окремо (SSH або консоль).

### 1.1 beelinkeqr5

**На beelinkeqr5 має бути тільки `tls-san: 192.168.100.2`.** Якщо ви раніше додали всі IP (192.168.100.1, .5, .6) — видаліть їх і залиште лише .2.

```bash
sudo mkdir -p /etc/rancher/k3s
# Видалити всі рядки tls-san і залишити лише один
sudo sed -i '/^tls-san:/d' /etc/rancher/k3s/config.yaml
echo 'tls-san: 192.168.100.2' | sudo tee -a /etc/rancher/k3s/config.yaml
```

Перевірка: `cat /etc/rancher/k3s/config.yaml` — має бути один рядок `tls-san: 192.168.100.2`.

### 1.2 master-node

```bash
sudo mkdir -p /etc/rancher/k3s
if ! grep -q 'tls-san: 192.168.100.5' /etc/rancher/k3s/config.yaml 2>/dev/null; then
  echo 'tls-san: 192.168.100.5' | sudo tee -a /etc/rancher/k3s/config.yaml
fi
```

### 1.3 macmini7

Macmini7 підключається до master-node з source 192.168.100.6 і до beelinkeqr5 з source 192.168.100.1 — потрібні **обидва** tls-san.

```bash
sudo mkdir -p /etc/rancher/k3s
# Видалити старі tls-san для цих IP (щоб не дублювати)
sudo sed -i '/^tls-san: 192.168.100.6$/d' /etc/rancher/k3s/config.yaml
sudo sed -i '/^tls-san: 192.168.100.1$/d' /etc/rancher/k3s/config.yaml
# Додати обидва
grep -q 'tls-san: 192.168.100.6' /etc/rancher/k3s/config.yaml 2>/dev/null || echo 'tls-san: 192.168.100.6' | sudo tee -a /etc/rancher/k3s/config.yaml
grep -q 'tls-san: 192.168.100.1' /etc/rancher/k3s/config.yaml 2>/dev/null || echo 'tls-san: 192.168.100.1' | sudo tee -a /etc/rancher/k3s/config.yaml
```

Перевірка (на кожній ноді):

```bash
# beelinkeqr5 — тільки один рядок
cat /etc/rancher/k3s/config.yaml   # tls-san: 192.168.100.2

# master-node — тільки один рядок
cat /etc/rancher/k3s/config.yaml   # tls-san: 192.168.100.5

# macmini7 — два рядки
cat /etc/rancher/k3s/config.yaml   # tls-san: 192.168.100.6 та tls-san: 192.168.100.1
```

Якщо в config вже є інші опції (node-ip, тощо), просто **додайте** один рядок `tls-san: <IP>` для цієї ноди, не видаляючи інше.

---

## Крок 2. Перегенерація etcd-сертифікатів і перезапуск k3s

K3s при старті генерує etcd peer-сертифікати з урахуванням **tls-san** з config. Щоб нові SAN потрапили в сертифікати, потрібно їх перегенерувати.

**Варіант A (рекомендовано):** перегенерація через `k3s certificate rotate --service etcd` на кожній ноді, потім перезапуск. Якщо **k3s зараз не запускається** на жодній ноді, спочатку виконайте **Варіант B**.

**Варіант B:** перезапустити k3s на всіх нодах після додавання tls-san. У багатьох версіях k3s сертифікати etcd оновлюються при перезапуску з новим config. Якщо після перезапуску всіх трьох помилки "rejected connection" лишаються — перейдіть до Варіанту A.

**Якщо k3s не стартує на master-node і macmini7:** спочатку виконайте Крок 1 (додати tls-san на усіх трьох), потім Крок 2.1 (перезапуск). Після додавання tls-san k3s при наступному старті може перегенерувати etcd-сертифікати з новими SAN — тоді кворум має з’явитися. Команду `k3s certificate rotate` можна виконати лише коли k3s уже запущений.

### 2.1 Варіант B: перезапуск усіх трьох (спочатку спробувати це)

Порядок перезапуску (щоб дві ноди могли швидше сформувати кворум):

1. **master-node**

   ```bash
   sudo systemctl restart k3s
   sudo systemctl status k3s
   ```

   Дочекатися, поки k3s стане active (навіть якщо etcd ще скаржиться в логах).

2. **macmini7**

   ```bash
   sudo systemctl restart k3s
   sudo systemctl status k3s
   ```

3. **beelinkeqr5**

   ```bash
   sudo systemctl restart k3s
   sudo systemctl status k3s
   ```

Через 1–2 хвилини перевірити:

```bash
# На будь-якій ноді з kubectl
kubectl get nodes
kubectl get cs  # компоненти (scheduler, controller-manager, etcd) мають бути Healthy
```

Якщо в логах (macmini7, master-node) все ще багато "rejected connection" і кворум не з’являється — виконати **Варіант A**.

### 2.2 Варіант A: rotate etcd-сертифікатів (якщо після Варіанту B помилки лишилися)

На **кожній** ноді по черзі (k3s має бути запущений, навіть якщо etcd "no leader"):

**На beelinkeqr5:**

```bash
sudo k3s certificate rotate --service etcd
sudo systemctl restart k3s
```

**На master-node:**

```bash
sudo k3s certificate rotate --service etcd
sudo systemctl restart k3s
```

**На macmini7:**

```bash
sudo k3s certificate rotate --service etcd
sudo systemctl restart k3s
```

Після перезапуску всіх трьох знову перевірити `kubectl get nodes` та логи: повідомлення "192.168.100.x does not match" мають зникнути, etcd — отримати лідера.

---

## Крок 3. Перевірка

- На будь-якій control-plane ноді:

  ```bash
  sudo k3s etcdctl member list
  ```

  Усі три члени мають бути в списку; якщо є `k3s etcdctl` — можна перевірити стан кворуму.

- Логи без "rejected connection":

  ```bash
  sudo journalctl -u k3s -f --no-pager | head -100
  ```

- З beelinkeqr5 (або з іншої ноди з kubectl):

  ```bash
  kubectl get nodes
  kubectl get pods -A
  ```

---

## Якщо beelinkeqr5 лишається NotReady (rejected 192.168.100.1 / 192.168.100.6)

Коли macmini7 і master-node вже **Ready**, etcd **Healthy**, а beelinkeqr5 — **NotReady** і в логах beelinkeqr5 лише "rejected … remote-addr: 192.168.100.1" та "192.168.100.6", це означає, що **beelinkeqr5** як сервер відхиляє вхідні з’єднання від macmini7. Можливі причини: (1) peer URL beelinkeqr5 в etcd member list не збігається з адресою, з якої інші ноди до нього підключаються; (2) сертифікат macmini7 після rotate не містить 192.168.100.1 / 192.168.100.6.

### Крок A. Перевірити сертифікат macmini7 (на macmini7)

Переконатися, що etcd peer-сертифікат macmini7 містить 192.168.100.1 і 192.168.100.6:

```bash
sudo openssl x509 -in /var/lib/rancher/k3s/server/tls/etcd/peer-server-client.crt -noout -text | grep -A1 "Subject Alternative Name"
```

У виводі мають бути IP: 192.168.100.1 та 192.168.100.6 (або в рядку DNS Name / IP Address). Якщо їх немає — на macmini7 знову виконати `sudo k3s certificate rotate --service etcd` і `sudo systemctl restart k3s`.

### Крок B. Оновити peer URL beelinkeqr5 (і за потреби macmini7) в etcd

Виконувати **на macmini7** (де etcd працює і є кворум):

```bash
# 1. Список членів — знайти MEMBER_ID для beelinkeqr5 та macmini7
sudo env ETCDCTL_API=3 \
  ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl member list
```

У виводі буде щось на кшталт:

- `... beelinkeqr5-... https://192.168.1.19:2380` або `https://192.168.2.x:2380`
- `... macmini7-... https://192.168.2.19:2380`

Оновити **beelinkeqr5** так, щоб його peer URL була адреса, за якою до нього підключаються (у вашому випадку з beelinkeqr5 прийходять з’єднання з source 192.168.100.1/192.168.100.6, тобто підключаються **до** beelinkeqr5; для beelinkeqr5 потрібно вказати URL, за яким інші ноди його досягають — зазвичай **192.168.100.2** або **192.168.1.19**). Якщо інші ноди підключаються до beelinkeqr5 по 192.168.100.2 — встановіть peer URL **[https://192.168.100.2:2380]**:

```bash
# 2. Підставити MEMBER_ID beelinkeqr5 (перше поле з member list)
sudo env ETCDCTL_API=3 \
  ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl member update BEELINKEQR5_MEMBER_ID --peer-urls="https://192.168.100.2:2380"
```

Якщо з’єднання до beelinkeqr5 йдуть по **192.168.1.19**, використовуйте `--peer-urls="https://192.168.1.19:2380"`.

Опціонально: якщо peer URL **macmini7** зараз 192.168.2.19, а фактичні з’єднання до macmini7 мають source 192.168.100.1, оновіть macmini7 на 192.168.100.1 (підставити MEMBER_ID macmini7):

```bash
sudo env ETCDCTL_API=3 \
  ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl member update MACMINI7_MEMBER_ID --peer-urls="https://192.168.100.1:2380"
```

(Якщо один член має кілька адрес досяжності, можна передати кілька URL через кому: `--peer-urls="https://192.168.100.1:2380,https://192.168.2.19:2380"`.)

### Крок C. Перезапустити k3s на beelinkeqr5

Після оновлення peer URL:

```bash
# На beelinkeqr5
sudo systemctl restart k3s
sudo systemctl status k3s
```

Через 1–2 хв перевірити з macmini7: `kubectl get nodes -o wide` — beelinkeqr5 має стати Ready.

---

## Якщо beelinkeqr5: "authentication handshake failed" / "request timed out"

Після оновлення peer URL beelinkeqr5 на 192.168.100.2 у логах beelinkeqr5 можуть з’явитися замість "rejected connection":

- `transport: authentication handshake failed: context deadline exceeded`
- `failed to publish local member to cluster through raft` з `error: etcdserver: request timed out`

Це означає, що **beelinkeqr5 не встигає пройти TLS/raft до інших пірів** або не може до них досягнути (outbound).

**Що зробити:**

### 1. На beelinkeqr5: перегенерувати etcd-сертифікат і перезапустити

Щоб macmini7 і master-node приймали з’єднання **від** beelinkeqr5 (source 192.168.100.2), сертифікат beelinkeqr5 має містити 192.168.100.2 у SAN. Після додавання в config лише `tls-san: 192.168.100.2` потрібно виконати rotate і перезапуск:

```bash
# На beelinkeqr5
sudo k3s certificate rotate --service etcd
sudo systemctl restart k3s
sudo systemctl status k3s
```

### 2. Peer URL має бути адресою, де etcd **слухає** (не source IP)

**Важливо:** Peer URL у member list — це адреса, **на якій цей член etcd приймає з’єднання** (де слухає порт 2380). Це **не** source IP трафіку. Якщо змінити macmini7 peer URL на 192.168.100.1, а etcd на macmini7 слухає лише на 192.168.2.19, то з’єднання до 192.168.100.1:2380 отримають **Connection refused** і кворум розсипається.

Перед зміною peer URL перевірте з іншої ноди: `nc -zv <IP> 2380` — має бути **succeeded**. Якщо **Connection refused** — на цій IP ніхто не слухає 2380, не використовуйте її в peer URL.

**Не змінюйте** macmini7 peer URL на 192.168.100.1, якщо на 192.168.100.1 порт 2380 не слухає (nc — Connection refused).

---

## Якщо після зміни peer URL macmini7 на 192.168.100.1 etcd розсипався

Якщо ви змінили macmini7 peer URL на **[https://192.168.100.1:2380]**, а на 192.168.100.1 ніхто не слухає порт 2380 (nc — Connection refused), то master-node і macmini7 не зможуть підключатися до macmini7 за member list → кворум втрачається, kubectl — ServiceUnavailable / Timeout.

**Відкотити peer URL macmini7 назад на 192.168.2.19** (адреса, де etcd на macmini7 реально слухає). Виконати **на macmini7** (etcd може ще відповідати локально):

```bash
sudo env ETCDCTL_API=3 \
  ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl member update 48c9a1862f44c505 --peer-urls="https://192.168.2.19:2380"
```

Якщо 2379 не відповідає, спробуйте порт **2382**: `ETCDCTL_ENDPOINTS='https://127.0.0.1:2382'`.

**Якщо etcdctl повертає `DeadlineExceeded`** — локальний etcd не має кворуму і не обробляє запити. Відновити member list без кворуму неможливо. **192.168.100.1 не можна використовувати на macmini7** — ця адреса зайнята роутером для тунелю (див. діаграму в `Syhiv VPN-2.pdf`), тому варіант «тимчасово додати 192.168.100.1 на macmini7» неприйнятний. Єдині варіанти — відновлення з etcd snapshot або перебудова control plane (див. нижче).

Після успішного update перезапустити k3s **на всіх трьох** нодах (спочатку macmini7, потім master-node, потім beelinkeqr5):

```bash
# На кожній ноді
sudo systemctl restart k3s
```

Через 1–2 хв перевірити: `kubectl get nodes -o wide`, `kubectl get cs` — кворум має повернутися (macmini7 і master-node Ready; beelinkeqr5 — окремо вирішувати через tls-san/rotate).

### Якщо etcdctl дає DeadlineExceeded і 192.168.100.1 недоступна (роутер/тунель)

Адреса **192.168.100.1** використовується роутером для тунелю (діаграма в `Syhiv VPN-2.pdf`), тому додавати її на macmini7 для тимчасового слухання etcd **не можна** — конфлікт IP.

**Можливі варіанти відновлення:**

1. **Відновлення з etcd snapshot** — якщо є snapshot etcd, зроблений **до** зміни peer URL macmini7 на 192.168.100.1, можна відновити кластер з нього (одна нода з відновленим snapshot, потім приєднання інших). Див. офіційну документацію k3s: [Backup and Restore](https://docs.k3s.io/backup-restore), зокрема restore from snapshot для embedded etcd.

2. **Перебудова control plane** — якщо snapshot немає або він застарілий, доведеться зберегти конфіги/маніфести, зняти control-plane ноди з кластера (або перевстановити k3s), потім розгорнути кластер заново і відновити workload з бекапів/маніфестів.

Перед будь-якими змінами peer URL у майбутньому перевіряйте: `nc -zv <IP> 2380` має дати **succeeded**; якщо **Connection refused** — цю адресу в peer URL не ставити, і не змінювати peer URL на адресу, де ніхто не слухає.

---

## Підсумок

| Крок | Де | Дія |
| ------ | ----- | ----- |
| 1 | beelinkeqr5 | У `/etc/rancher/k3s/config.yaml` **лише** `tls-san: 192.168.100.2` (видалити .1, .5, .6, якщо додавали) |
| 1 | master-node | У config лише `tls-san: 192.168.100.5` |
| 1 | macmini7 | У config `tls-san: 192.168.100.6` **і** `tls-san: 192.168.100.1` |
| 2 | Усі три | Перезапустити k3s (спочатку master-node, потім macmini7, потім beelinkeqr5) |
| 3 | (за потреби) | Якщо "rejected" лишаються — на кожній ноді: `sudo k3s certificate rotate --service etcd`, потім `sudo systemctl restart k3s` |

Файл конфігурації на кожній ноді — **`/etc/rancher/k3s/config.yaml`**. Окремий процес etcd перезапускати не потрібно: він керується k3s, достатньо перезапуску `k3s`.
