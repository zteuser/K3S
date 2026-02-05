# Відновлення кластера: beelinkeqr5 не стартує (TLS SAN за поточними логами)

**Стан:** etcd member list коректний (10.0.10.10, 192.168.2.19, 192.168.1.19). На **beelinkeqr5** k3s не виходить у стабільний стан; в логах — `rejected connection on peer endpoint` і `tls: "IP" does not match any of DNSNames`.

**Причина:** З’єднання до etcd йдуть через роутери (Syhiv17, VRN625), тому **source IP**, який бачить beelinkeqr5, — це адреса роутера (WG), а не ноди. Сертифікати master-node та macmini7 не містять цих IP у SAN → beelinkeqr5 відхиляє з’єднання.

З ваших логів на **beelinkeqr5**:
- **remote-addr 192.168.100.1** → сертифікат з DNSNames `master-node` → це **master-node** підключається з source **192.168.100.1** (Syhiv17 wg0).
- **remote-addr 192.168.200.6** → сертифікат з DNSNames `macmini7` → це **macmini7** підключається з source **192.168.200.6** (VRN625 wgclt2 на 192.168.200.4/30).

Тобто потрібно додати в **tls-san** на **master-node** і **macmini7** саме ті IP, з яких beelinkeqr5 бачить їхні з’єднання.

---

## Таблиця: що додати в tls-san (за поточними логами)

**Критично:** etcd перевіряє **source IP** вхідного з’єднання. Якщо нода A підключається до ноди B з IP X, то в сертифікаті **ноди B** має бути SAN = X.

| Нода         | Додати tls-san (IP, з яких інші підключаються до цієї ноди) | Чому (з логів) |
|--------------|-------------------------------------------------------------|----------------|
| **master-node** | **192.168.100.1**, **192.168.100.5** | macmini7 підключається до master-node з **192.168.100.5** → `"192.168.100.5" does not match` на master-node. 192.168.100.1 — для beelinkeqr5. |
| **macmini7**    | **192.168.200.6**, **192.168.100.6**  | master-node підключається до macmini7 з **192.168.100.6** → `"192.168.100.6" does not match` на macmini7. 192.168.200.6 — для beelinkeqr5. |
| **beelinkeqr5** | **192.168.100.2**                    | Його source IP при з’єднанні до master/macmini7 — 192.168.100.2. |

---

## Крок 1. Додати tls-san на master-node та macmini7 (обов’язково)

Виконувати на **master-node** і **macmini7** (де k3s зараз працює). Після змін — перезапуск k3s і перегенерація etcd-сертифікатів.

### 1.1 master-node

Потрібні **192.168.100.5** (macmini7 підключається з цим IP) та **192.168.100.1** (beelinkeqr5):

```bash
# Додати tls-san, якщо ще немає (кожен IP — окремий рядок tls-san:)
grep -q 'tls-san: 192.168.100.1' /etc/rancher/k3s/config.yaml 2>/dev/null || echo 'tls-san: 192.168.100.1' | sudo tee -a /etc/rancher/k3s/config.yaml
grep -q 'tls-san: 192.168.100.5' /etc/rancher/k3s/config.yaml 2>/dev/null || echo 'tls-san: 192.168.100.5' | sudo tee -a /etc/rancher/k3s/config.yaml
cat /etc/rancher/k3s/config.yaml
```

### 1.2 macmini7

Потрібні **192.168.100.6** (master-node підключається з цим IP) та **192.168.200.6** (beelinkeqr5):

```bash
grep -q 'tls-san: 192.168.100.6' /etc/rancher/k3s/config.yaml 2>/dev/null || echo 'tls-san: 192.168.100.6' | sudo tee -a /etc/rancher/k3s/config.yaml
grep -q 'tls-san: 192.168.200.6' /etc/rancher/k3s/config.yaml 2>/dev/null || echo 'tls-san: 192.168.200.6' | sudo tee -a /etc/rancher/k3s/config.yaml
cat /etc/rancher/k3s/config.yaml
```

### 1.3 beelinkeqr5 (перед перезапуском)

Щоб після відновлення кворуму master/macmini7 не відхиляли beelinkeqr5, додайте tls-san і на beelinkeqr5:

```bash
# Можна виконати зараз (k3s на beelinkeqr5 можна зупинити)
sudo systemctl stop k3s
grep -q 'tls-san: 192.168.100.2' /etc/rancher/k3s/config.yaml 2>/dev/null || echo 'tls-san: 192.168.100.2' | sudo tee -a /etc/rancher/k3s/config.yaml
cat /etc/rancher/k3s/config.yaml
```

---

## Крок 2. Перегенерація etcd-сертифікатів і перезапуск

Нові SAN потраплять в etcd-сертифікати після **rotate** або (залежно від версії k3s) після перезапуску з оновленим config. Рекомендовано: перезапуск → rotate etcd.

### 2.1 master-node

```bash
sudo systemctl restart k3s
# Дочекатися active
sudo systemctl status k3s
# Перегенерувати etcd-сертифікати з новими SAN
sudo k3s certificate rotate --service etcd
```

### 2.2 macmini7

```bash
sudo systemctl restart k3s
sudo systemctl status k3s
sudo k3s certificate rotate --service etcd
```

### 2.3 beelinkeqr5

Після того як master-node і macmini7 прийняли нові сертифікати, перезапустіть k3s на beelinkeqr5. Якщо там уже додано tls-san 192.168.100.2, спочатку просто старт; якщо з’являться reject для beelinkeqr5 (connection from 192.168.100.2), тоді на beelinkeqr5 потрібен rotate etcd (можна спробувати одразу після старту):

```bash
sudo systemctl start k3s
sudo systemctl status k3s
# Якщо k3s став active — перегенерувати etcd cert на beelinkeqr5
sudo k3s certificate rotate --service etcd
```

Якщо k3s на beelinkeqr5 знову падає з "rejected" для 192.168.100.2, перезапустіть його ще раз після rotate (або перезапуск після додавання tls-san іноді достатній для перегенерації при старті).

---

## Крок 3. Перевірка

На macmini7 (або master-node):

```bash
kubectl get nodes
# Всі 4 ноди мають бути Ready (beelinkeqr5 може спочатку NotReady, потім Ready після кількох секунд).
```

```bash
# etcd члени
sudo k3s etcdctl member list
# або з etcdctl та сертифікатами k3s (див. FIX_ETCD_MEMBER_IP_CHANGE.md)
```

---

## Якщо спочатку "peer-server-client.crt: no such file or directory"

Ця помилка **спочатку** має бути усунена, інакше etcd не запуститься. Дії: **ETCD_PEER_SERVER_CLIENT_CRT_MISSING.md** (симлінк або повторний rotate). Після цього продовжуйте з tls-san і rotate нижче.

---

## Якщо помилки лишаються (TLS SAN / "does not match DNSNames")

- **master-node:** у config.yaml мають бути **tls-san: 192.168.100.1** і **tls-san: 192.168.100.5** (IP, з якого macmini7 підключається до master-node).
- **macmini7:** у config.yaml мають бути **tls-san: 192.168.100.6** і **tls-san: 192.168.200.6** (IP, з якого master-node/beelinkeqr5 підключаються до macmini7).
- **beelinkeqr5:** **tls-san: 192.168.100.2**.
- Після зміни config обов’язково: `k3s certificate rotate --service etcd` на кожній ноді, потім `systemctl restart k3s`.
- Детальніше — **FIX_ETCD_TLS_RECOVERY.md**.
