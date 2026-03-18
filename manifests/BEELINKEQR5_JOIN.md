# beelinkeqr5 — join k8s + Cilium як worker

> **IP:** 192.168.1.19 | **Інтерфейс:** enp1s0 | **Роль:** worker

---

## 1. Передумови

- [ ] Зв'язність beelinkeqr5 ↔ master-node (10.0.10.10) відновлена
- [ ] hostname: `beelinkeqr5` — якщо ні: `sudo hostnamectl set-hostname beelinkeqr5`

---

## 2. Очистка (якщо був k3s)

```bash
# На beelinkeqr5
sudo /usr/local/bin/k3s-uninstall.sh  2>/dev/null || true
sudo /usr/local/bin/k3s-agent-uninstall.sh  2>/dev/null || true
sudo rm -rf /etc/cni/net.d /var/lib/rancher/k3s/agent/etc/cni/ 2>/dev/null
```

---

## 3. Встановлення containerd

```bash
# На beelinkeqr5
sudo apt-get update && sudo apt-get install -y containerd curl apt-transport-https ca-certificates

sudo mkdir -p /etc/containerd
cat <<EOF | sudo tee /etc/containerd/config.toml
version = 2
[plugins."io.containerd.grpc.v1.cri"]
  systemd_cgroup = true
EOF
sudo systemctl restart containerd
sudo systemctl enable containerd
```

---

## 4. Встановлення kubeadm, kubelet, kubectl

```bash
# На beelinkeqr5
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

---

## 5. Swap (якщо увімкнено)

Якщо swap увімкнено — kubelet падає з "running with swap on is not supported":

```bash
# Варіант A: вимкнути swap
sudo swapoff -a

# Варіант B: дозволити swap (як на macmini7)
sudo sed -i "/^kind: KubeletConfiguration/a failSwapOn: false" /var/lib/kubelet/config.yaml 2>/dev/null || true
# (config.yaml з'явиться після першого kubeadm join)
```

---

## 6. kubeadm join

### 6.1 Отримати join-команду (на master-node)

```bash
# На master-node — згенерувати новий token (старі дійсні 24h)
kubeadm token create --print-join-command
```

Вивід: `kubeadm join 10.0.10.10:6443 --token XXXXX --discovery-token-ca-cert-hash sha256:...`

### 6.2 Виконати join (на beelinkeqr5)

```bash
# На beelinkeqr5 — підставити команду з п. 6.1
sudo kubeadm join 10.0.10.10:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:64ad9b8b382a5e306bdcb32ee5e3e7a4bb551ba6d6debff468572f0639040dfc
```

**Якщо failSwapOn: swap:** перед join додати `failSwapOn: false` у `/var/lib/kubelet/config.yaml` після першого невдалого join, потім перезапустити kubelet і повторити join.

---

## 7. Cilium (на master-node)

Cilium підхопиться автоматично — DaemonSet запустить pod на beelinkeqr5. Потрібно застосувати CiliumNodeConfig для beelinkeqr5 (інтерфейс enp1s0):

```bash
# На master-node з KUBECONFIG
kubectl apply -f manifests/cilium/cilium-node-configs.yaml

# Якщо Cilium pod на beelinkeqr5 падає — перезапустити
kubectl delete pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=beelinkeqr5
```

---

## 8. Перевірка

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
# Дочекатись cilium-* на beelinkeqr5 Running

# Cilium status
kubectl -n kube-system exec -it $(kubectl get pod -n kube-system -l k8s-app=cilium -o jsonpath='{.items[?(@.spec.nodeName=="beelinkeqr5")].metadata.name}') -c cilium-agent -- cilium-dbg status
```

---

## 9. Pod-to-pod connectivity

```bash
kubectl run test-beelink --image=nicolaka/netshoot --restart=Never --overrides='{"spec":{"nodeName":"beelinkeqr5"}}' -- sleep 3600
kubectl run test-master --image=nicolaka/netshoot --restart=Never --overrides='{"spec":{"nodeName":"master-node"}}' -- sleep 3600

# Дочекатись Running
kubectl get pods -o wide

# З beelink pod пінгувати master pod
BEELINK_POD=$(kubectl get pod test-beelink -o jsonpath='{.status.podIP}')
MASTER_POD=$(kubectl get pod test-master -o jsonpath='{.status.podIP}')
kubectl exec test-master -- ping -c 3 $BEELINK_POD
kubectl exec test-beelink -- ping -c 3 $MASTER_POD

kubectl delete pod test-beelink test-master
```

---

## Швидкий чеклист

| # | Дія | Де |
|---|-----|-----|
| 1 | Видалити k3s (якщо був) | beelinkeqr5 |
| 2 | containerd + kubeadm | beelinkeqr5 |
| 3 | failSwapOn: false (якщо swap) | beelinkeqr5 |
| 4 | kubeadm token create | master-node |
| 5 | kubeadm join | beelinkeqr5 |
| 6 | kubectl apply cilium-node-configs | master-node |
| 7 | Перевірити cilium pod | master-node |
