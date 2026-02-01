# Відновлення etcd: "no leader" та "rejected connection" (TLS SAN)

**Симптоми:**
- **beelinkeqr5:** `watch chan error: etcdserver: no leader`
- **macmini7 / master-node:** k3s не стартує або etcd не формує кворум; в логах — `rejected connection on peer endpoint`, `tls: "192.168.100.x" does not match any of DNSNames [...]`

**Причина:** Трафік між control-plane нодами йде через шлюзи/NAT, тому **source IP** з’єднання до etcd — не власна IP ноди, а адреса шлюзу (192.168.100.2, 192.168.100.5, 192.168.100.6). Etcd перевіряє клієнтський сертифікат піра: якщо цього source IP немає в SAN, з’єднання відхиляється → кворум не формується → "no leader".

**Рішення:** Додати в **tls-san** лише **ті IP, з яких ця нода сама підключається** (source IP її трафіку). Файл на кожній ноді: **`/etc/rancher/k3s/config.yaml`**.

**Важливо:** Кожна нода має мати в tls-san **тільки свої** source IP, а не всі IP кластера. Якщо на одній ноді додати tls-san для всіх (192.168.100.1, .2, .5, .6), це не вирішить "rejected connection": інші ноди підключаються до неї з **своїми** source IP, і їхні сертифікати мають містити ці IP на **тих** нодах.

---

## Яку адресу додати на яку ноду (з ваших логів)

| Нода        | Додати tls-san (тільки ці) | Чому |
|-------------|----------------------------|------|
| **beelinkeqr5** | **лише** `192.168.100.2` | Коли beelinkeqr5 підключається до macmini7/master-node, її трафік має source IP 192.168.100.2 |
| **master-node** | **лише** `192.168.100.5` | Коли master-node підключається до інших, трафік має source IP 192.168.100.5 |
| **macmini7**    | `192.168.100.6` **і** `192.168.100.1` | До master-node — source 192.168.100.6; до beelinkeqr5 — source 192.168.100.1 (логи на beelinkeqr5: "rejected … remote-addr: 192.168.100.1") |

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

## Підсумок

| Крок | Де | Дія |
|------|-----|-----|
| 1 | beelinkeqr5 | У `/etc/rancher/k3s/config.yaml` **лише** `tls-san: 192.168.100.2` (видалити .1, .5, .6, якщо додавали) |
| 1 | master-node | У config лише `tls-san: 192.168.100.5` |
| 1 | macmini7 | У config `tls-san: 192.168.100.6` **і** `tls-san: 192.168.100.1` |
| 2 | Усі три | Перезапустити k3s (спочатку master-node, потім macmini7, потім beelinkeqr5) |
| 3 | (за потреби) | Якщо "rejected" лишаються — на кожній ноді: `sudo k3s certificate rotate --service etcd`, потім `sudo systemctl restart k3s` |

Файл конфігурації на кожній ноді — **`/etc/rancher/k3s/config.yaml`**. Окремий процес etcd перезапускати не потрібно: він керується k3s, достатньо перезапуску `k3s`.
