# OCI: «помилкові» FQDN з суфіксом `*.oraclevcn.com` і таймаути CoreDNS

## Що видно в логах

Приклад:

```text
[ERROR] plugin/errors: ... AAAA longhorn-upgrade-responder.rancher.io.vcn09070439.oraclevcn.com. ... read udp ... 1.1.1.1:53: i/o timeout
```

Домену **`longhorn-upgrade-responder.rancher.io.vcn09070439.oraclevcn.com`** не існує: до коректного зовнішнього імені **`longhorn-upgrade-responder.rancher.io`** помилково дописано search-домен VCN **`vcn09070439.oraclevcn.com`** (на нодах OCI він зазвичай приходить з `/etc/resolv.conf`).

### Політика для файлу resolv kubelet / k3s

У **файлі, який ви передаєте kubelet як `resolvConf`** (або k3s `--resolv-conf`), **не додавайте** рядок `search …oraclevcn.com` і взагалі **не дублюйте** VCN search з хоста. Достатньо публічних `nameserver` і за бажанням `options ndots:2`. Кластерні домени (`*.svc.cluster.local`) kubelet додає окремо до resolv подів.

## Чому так відбувається

1. У пода в `resolv.conf` є **`search`**, часто: `default.svc.cluster.local`, `svc.cluster.local`, `cluster.local` **і** домени з ноди (наприклад `vcn09070439.oraclevcn.com`), якщо kubelet підмішує налаштування з ОС.
2. У Kubernetes за замовчуванням для подів часто задається **`options ndots:5`**: якщо в імені **менше ніж 5 крапок**, резолвер **спочатку** додає елементи з `search`, і лише потім може звернутися до «абсолютного» імені.
3. У **`longhorn-upgrade-responder.rancher.io`** лише **дві крапки** (три мітки) — менше порогу `ndots:5`, тому з’являється спроба резолвити, зокрема,  
   `longhorn-upgrade-responder.rancher.io.vcn09070439.oraclevcn.com`.
4. Такий запит іде в CoreDNS → `forward` на 8.8.8.8 / 1.1.1.1. Відповідь на неіснуюче ім’я може довго не приходити або виглядати як проблема мережі → у логах **`i/o timeout`**, хоча корінь — **не «блокування DNS»**, а **неправильне ім’я через search**.

## Рішення (пріоритет)

### 1a. Kubernetes (kubeadm): окремий `resolv.conf` для **kubelet** (OCI / systemd-resolved)

На **кожній** ноді, де kubelet використовує `resolvConf: /run/systemd/resolve/resolv.conf` (типово на Ubuntu + systemd-resolved), підтягується OCI `search …oraclevcn.com`.

1. Створіть файл **без** рядка `search` з `oraclevcn.com`:

```bash
sudo tee /etc/kubernetes/kubelet-resolv.conf <<'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
options ndots:2
EOF
```

2. У **`/var/lib/kubelet/config.yaml`** (поле `KubeletConfiguration`) встановіть:

```yaml
resolvConf: /etc/kubernetes/kubelet-resolv.conf
```

(замість `/run/systemd/resolve/resolv.conf`). Перед зміною зробіть резервну копію, наприклад:

```bash
sudo cp -a /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.bak-oci-dns
sudo sed -i.bak-oci-dns 's|^resolvConf:.*|resolvConf: /etc/kubernetes/kubelet-resolv.conf|' /var/lib/kubelet/config.yaml
```

3. Перезапустіть kubelet на ноді:

```bash
sudo systemctl restart kubelet
```

Повторіть на **усіх нодах** кластера (у тому числі **LAN**-воркери `beelinkeqr5`, `macmini7`, не лише OCI `master-node` / `work-node`). Якщо виправити лише частину нод, у логах **CoreDNS на будь-якій ноді** (наприклад `master-node`) усе одно з’являться запити з суфіксом `oraclevcn.com`: їх формує **клієнтський под** на **іншій** ноді, де kubelet ще підставляє `search` з systemd-resolved.

Після `kubeadm upgrade` перевірте, чи не перезаписався `config.yaml`.

**Швидка перевірка по всіх нодах** (без SSH): у репо **K8S** з кореня виконайте `./scripts/check-resolv-oraclevcn-all-nodes.sh` (див. також `K8S/docs/DNS_OCI_KUBELET_RESOLV.md`). Скрипт створює короткоживучий под на кожній ноді і друкує `/etc/resolv.conf`; має **не** містити `oraclevcn.com`.

### 1b. k3s: окремий `resolv.conf` і прапор `--resolv-conf`

На **кожній** ноді з k3s створіть `/etc/rancher/k3s/resolv.conf` з тим самим вмістом (nameserver + `options ndots:2`, **без** VCN `search`). Запустіть k3s з:

```text
--resolv-conf=/etc/rancher/k3s/resolv.conf
```

(деталі — у unit `k3s` / `k3s-agent`, перезапуск сервісу).

**Примітка:** `ndots:2` у файлі для kubelet/k3s впливає на те, як формується базовий resolv для подів; кластерні `search` kubelet додає окремо. Не додавайте в цей файл `search …oraclevcn.com`.

### 2. Upstream CoreDNS

Щоб зовнішні запити не йшли на `169.254.169.254`, залишайте **`forward . 8.8.8.8 1.1.1.1`** (див. **FIX_OCI_DNS_TIMEOUT.md**).

### 3. Точково для окремих workload (Longhorn тощо)

У Deployment / DaemonSet можна задати **`dnsConfig`**:

```yaml
dnsConfig:
  options:
    - name: ndots
      value: "2"
```

або прибрати зайві search через `dnsPolicy` + явний `dnsConfig` (рідше потрібно, якщо виправлено kubelet `resolvConf` або k3s `--resolv-conf`).

## Перевірка

1. У тимчасовому поді:

   ```bash
   kubectl run rcheck --rm -it --restart=Never --image=busybox:1.36 -- cat /etc/resolv.conf
   ```

   Переконайтеся, що **немає** `search ...oraclevcn.com` (або порядок/склад відповідає очікуванню після змін).

2. Резолв зовнішнього імені:

   ```bash
   kubectl run rcheck2 --rm -it --restart=Never --image=busybox:1.36 -- nslookup longhorn-upgrade-responder.rancher.io
   ```

3. Логи CoreDNS — не повинно з’являтися запитів до `*.rancher.io.*.oraclevcn.com` для цього кейсу.

## Пов’язані документи

- **FIX_OCI_DNS_TIMEOUT.md** — upstream CoreDNS і 169.254.169.254.
- **README.md** — Cilium egress до 8.8.8.8 / 1.1.1.1 для CoreDNS.
