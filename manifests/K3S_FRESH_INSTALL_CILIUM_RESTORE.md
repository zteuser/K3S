# Перевстановлення k3s з нуля з Cilium та відновлення з бекапу

Можливість **так, є**. Нижче — покроковий план.

> **Рекомендований підхід:** міграція існуючого кластера з Flannel на Cilium (`CILIUM_MIGRATION_PLAN.md`) **не працює** — призводить до втрати мережі, відкат не допомагає. Єдиний безпечний варіант — **свіжий кластер з Cilium з нуля** + відновлення з бекапу.

---

## 1. Що є в бекапі

| Файл | Що відновити |
|------|---------------|
| **all-resources.yaml** | Deployments, DaemonSets, StatefulSets, Services (без Pods, ReplicaSets — вони ефемерні) |
| **configmaps.yaml** | ConfigMaps |
| **secrets.yaml** | Secrets |
| **pvc.yaml** | PersistentVolumeClaims |
| **ingress.yaml** | Ingress |
| **helmchartconfig.yaml** | HelmChartConfig (Traefik) |
| **node-*.txt** | Конфіги k3s для кожної ноди |

---

## 2. Загальна схема

1. **Повністю видалити k3s** на всіх нодах
2. **Встановити k3s з нуля** з `flannel-backend: none` одразу
3. **Встановити Cilium** до відновлення workload
4. **Відновити ресурси** з бекапу (без Pods, ReplicaSets)

---

## 3. Крок 1: Видалення k3s на всіх нодах

На **кожній ноді** (macmini7, beelinkeqr5, master-node, work-node):

```bash
# Server-ноди (macmini7, beelinkeqr5, master-node)
/usr/local/bin/k3s-uninstall.sh

# Agent-нода (work-node)
/usr/local/bin/k3s-agent-uninstall.sh
```

Очистити залишки (опційно):

```bash
sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s /var/lib/kubelet
sudo rm -f /etc/cni/net.d/*
```

**Якщо після видалення мережа (SSH, ping) не працює** — виконати **reboot**. На практиці (master-node OCI) connectivity відновилась лише після reboot.

---

## 4. Крок 2: Встановлення k3s з Cilium-ready конфігом

**Перша нода:** master-node (10.0.10.10) — OCI.

### 4.1 Перша server-нода (master-node)

```bash
# Встановити k3s з cluster-init
# КРИТИЧНО: --disable-kube-proxy обов'язковий при kubeProxyReplacement: true в Cilium!
# Без нього kube-proxy і Cilium конфліктують (iptables, TPROXY) → втрата мережі.
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --cluster-init --flannel-backend=none --disable-network-policy --disable-kube-proxy --node-ip 10.0.10.10" sh -

# Відредагувати /etc/rancher/k3s/config.yaml — додати tls-san для доступу з інших мереж:
# tls-san: [192.168.100.5, 192.168.100.1, 192.168.100.6, 192.168.200.6, 141.144.254.42]
sudo systemctl restart k3s

# Зберегти token
sudo cat /var/lib/rancher/k3s/server/node-token
```

**API server URL:** `https://10.0.10.10:6443` (з OCI) або `https://192.168.100.5:6443` (з macmini7/beelinkeqr5 через WireGuard).

### 4.2 Інші server-ноди (macmini7, beelinkeqr5)

```bash
# Взяти token з master-node: sudo cat /var/lib/rancher/k3s/server/node-token
# macmini7/beelinkeqr5 — використати 192.168.100.5 (WireGuard) якщо досяжний
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.100.5:6443 K3S_TOKEN=<TOKEN> \
  INSTALL_K3S_EXEC="server --flannel-backend=none --disable-network-policy --disable-kube-proxy" sh -
```

### 4.3 Agent-нода (work-node)

```bash
curl -sfL https://get.k3s.io | K3S_URL=https://10.0.10.10:6443 K3S_TOKEN=<TOKEN> sh -
```

---

## 5. Крок 3: Встановлення Cilium

Після того як усі server-ноди в кластері:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium \
  --version 1.19.0 \
  --namespace kube-system \
  --values manifests/cilium/values-k3s.yaml

# Дочекатись готовності
cilium status --wait
# або: kubectl get pods -n kube-system -l k8s-app=cilium -w
```

Застосувати CiliumNodeConfig (per-node інтерфейси):

```bash
kubectl apply -f manifests/cilium/cilium-node-configs.yaml
```

---

## 6. Крок 4: Відновлення ресурсів з бекапу

### 6.1 Підготовка YAML (видалити Pods, ReplicaSets, status)

Бекап містить Pods і ReplicaSets — їх не відновлюємо (створюються автоматично з Deployments).

**Скрипт prepare-restore.py** (потребує Python + PyYAML: `pip install pyyaml`):

```bash
cd /path/to/k3s
python3 backup-pre-cilium/prepare-restore.py backup-pre-cilium/all-resources.yaml restore-workloads.yaml
```

Скрипт видаляє Pods, ReplicaSets, системні k3s (coredns, traefik, local-path, metrics-server) та очищує metadata.

**Варіант з yq** (якщо встановлено):

```bash
yq eval '
  .items |= map(select(.kind != "Pod" and .kind != "ReplicaSet"))
' backup-pre-cilium/all-resources.yaml > restore-workloads.yaml
```

### 6.2 Порядок відновлення

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 1. ConfigMaps, Secrets (перед workload)
kubectl apply -f backup-pre-cilium/configmaps.yaml
kubectl apply -f backup-pre-cilium/secrets.yaml

# 2. PVC (перед Pods)
kubectl apply -f backup-pre-cilium/pvc.yaml

# 3. Workload (Deployments, DaemonSets, StatefulSets, Services)
kubectl apply -f restore-workloads.yaml

# 4. Ingress
kubectl apply -f backup-pre-cilium/ingress.yaml

# 5. HelmChartConfig (Traefik) — опційно
kubectl apply -f backup-pre-cilium/helmchartconfig.yaml
```

---

## 7. Що може потребувати ручного виправлення

| Проблема | Рішення |
|----------|---------|
| Конфлікт імен (resource вже існує) | `kubectl apply -f file.yaml --force` або видалити і застосувати знову |
| PVC не знаходить PV | Перевірити StorageClass, створити PV вручну |
| Node affinity (nodeName) | Поди можуть бути прив’язані до старих нод — перевірити nodeSelector |
| Secrets з закодованими даними | Відновити з secrets.yaml; якщо vault — окремо |
| Ingress class | Traefik — перевірити ingressClassName |

---

## 8. Чеклист

- [ ] Видалено k3s на всіх нодах
- [ ] Встановлено k3s з `--flannel-backend=none` на server-нодах
- [ ] Встановлено k3s-agent на work-node
- [ ] Всі ноди в кластері (`kubectl get nodes`)
- [ ] Встановлено Cilium, `cilium status` — OK
- [ ] Застосовано CiliumNodeConfig
- [ ] Підготовлено restore-workloads.yaml (python3 prepare-restore.py)
- [ ] Відновлено ConfigMaps, Secrets, PVC
- [ ] Відновлено Deployments, DaemonSets, StatefulSets, Services
- [ ] Відновлено Ingress
- [ ] Перевірено поди: `kubectl get pods -A`

---

## 9. Ризики та обмеження

1. **Downtime** — кластер буде недоступний під час перевстановлення (години).
2. **Дані в PVC** — якщо PV на локальних дисках нод, після uninstall дані можуть залишитись у `/var/lib/rancher/k3s/`; перевірити перед видаленням.
3. **etcd** — повністю новий кластер, історія та ідентифікатори змінюються.
4. **Токени, сертифікати** — нові; оновить доступ (kubeconfig, RBAC тощо).
