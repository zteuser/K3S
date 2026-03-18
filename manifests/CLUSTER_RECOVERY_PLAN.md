# План відновлення кластера k3s після збою

**Поточний стан:**
- **macmini7** (192.168.2.19) — переінстальований Ubuntu, є SSH
- **master-node** (10.0.10.10) — OCI, лише Cloud Shell (немає SSH)
- **work-node** (10.0.10.20) — OCI, є SSH
- **beelinkeqr5** (192.168.1.19) — немає фізичного доступу

**Проблема:** etcd без кворуму, старий кластер не відновити.

**Рішення:** новий кластер з нуля на **Flannel** (без Cilium), відновлення workload з бекапу.

---

## Передумови

1. **Зв'язність:** macmini7 і beelinkeqr5 мають досягати master-node — через WireGuard (192.168.100.5) або публічний IP.
2. **Новий token:** старий токен прив’язаний до мертвого etcd — потрібен новий.

---

## Фаза 1: Новий кластер (master-node + work-node + macmini7)

**Перша нода:** master-node (10.0.10.10) — OCI, завжди доступна.

### Крок 1.1. master-node — перший server (cluster-init)

На master-node (SSH або Cloud Shell):

```bash
# Видалити залишки старого k3s (якщо є)
/usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s /var/lib/kubelet /etc/cni

# Встановити k3s (Flannel за замовчуванням)
curl -sfL https://get.k3s.io | sh -s - server --cluster-init --node-ip 10.0.10.10

# Відредагувати /etc/rancher/k3s/config.yaml — додати tls-san для доступу з інших мереж:
# tls-san: [192.168.100.5, 192.168.100.1, 192.168.100.6, 192.168.200.6, 141.144.254.42]
sudo systemctl restart k3s

# Зберегти новий token
sudo cat /var/lib/rancher/k3s/server/node-token
# Скопіювати — потрібен для work-node та macmini7

# Перевірити
sudo kubectl get nodes
```

**API server URL:** `https://10.0.10.10:6443` (з OCI) або `https://192.168.100.5:6443` (з macmini7/beelinkeqr5 через WireGuard).

### Крок 1.2. work-node — agent (через SSH)

На work-node (SSH з вашого Mac):

```bash
# Видалити старий k3s-agent
/usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true
sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s /var/lib/kubelet /etc/cni

# Встановити k3s agent (приєднатися до master-node)
curl -sfL https://get.k3s.io | sh -s - agent \
  --server https://10.0.10.10:6443 \
  --token <NEW_TOKEN>
```

### Крок 1.3. macmini7 — другий server (через SSH)

На macmini7 (SSH):

```bash
# Видалити залишки старого k3s
/usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s /var/lib/kubelet /etc/cni

# Встановити k3s server (приєднатися до master-node)
# Використати 192.168.100.5 якщо WireGuard до master-node працює
curl -sfL https://get.k3s.io | sh -s - server \
  --server https://192.168.100.5:6443 \
  --token <NEW_TOKEN>
# Або: --server https://10.0.10.10:6443 (якщо є маршрут з macmini7)
```

### Крок 1.4. Перевірка

На master-node:

```bash
kubectl get nodes -o wide
# Має бути: master-node, work-node, macmini7 — Ready
```

---

## Фаза 2: Відновлення workload з бекапу

На master-node (або macmini7):

```bash
# Підготувати restore
cd /path/to/k3s
python3 backup-pre-cilium/prepare-restore.py backup-pre-cilium/all-resources.yaml restore-workloads.yaml

# Відновити
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl apply -f backup-pre-cilium/configmaps.yaml
kubectl apply -f backup-pre-cilium/secrets.yaml
kubectl apply -f backup-pre-cilium/pvc.yaml
kubectl apply -f restore-workloads.yaml
kubectl apply -f backup-pre-cilium/ingress.yaml
kubectl apply -f backup-pre-cilium/helmchartconfig.yaml 2>/dev/null || true
```

---

## Фаза 3: beelinkeqr5 (коли буде доступ)

На beelinkeqr5:

```bash
/usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s /var/lib/kubelet /etc/cni

curl -sfL https://get.k3s.io | sh -s - server \
  --server https://192.168.100.5:6443 \
  --token <NEW_TOKEN>
```

---

## Чеклист

- [ ] master-node: k3s server --cluster-init --node-ip 10.0.10.10, token збережено
- [ ] work-node: k3s agent --server https://10.0.10.10:6443
- [ ] macmini7: k3s server --server https://192.168.100.5:6443
- [ ] kubectl get nodes — 3 ноди Ready
- [ ] restore-workloads.yaml застосовано
- [ ] beelinkeqr5 — додано пізніше (опційно)
