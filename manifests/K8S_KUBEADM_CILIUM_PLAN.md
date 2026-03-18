# План: k8s (kubeadm) + Cilium — 1 control-plane → 3 control-plane HA

> **Архітектура:** OCI control-plane only + локальні mixed (control-plane + worker)

---

## 1. Фінальна топологія

```
┌─────────────────────────────────────────────────────────────────┐
│  OCI (control-plane only)                                        │
│  master-node  10.0.10.10  — control-plane only (2 cores)         │
│  work-node    10.0.10.20  — worker only (2 cores)                │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┼─────────────────────────────────────┐
│  Локальна мережа            │                                       │
│  macmini7    192.168.2.19   — control-plane + worker (4 cores)    │
│  beelinkeqr5 192.168.1.19   — control-plane + worker (12 cores)   │
└───────────────────────────────────────────────────────────────────┘
```

**etcd quorum:** 3 control-plane → можна втратити 1 ноду.

---

## 2. Передумови

### 2.1 Мережева досяжність

Усі 4 ноди мають досягати одна одну (WireGuard, VPN або direct routing):

| З \ До | master-node | work-node | macmini7 | beelinkeqr5 |
|--------|-------------|-----------|----------|-------------|
| master-node | — | ✓ | ✓ | ✓ |
| work-node | ✓ | — | ✓ | ✓ |
| macmini7 | ✓ | ✓ | — | ✓ |
| beelinkeqr5 | ✓ | ✓ | ✓ | — |

**Control-plane endpoint:** IP або DNS, до якого всі ноди підключаються до API. Рекомендовано: `10.0.10.10` (master-node) або DNS (наприклад `k8s-api.local`).

### 2.2 Інтерфейси (для Cilium)

| Нода | Інтерфейс (ip route get 8.8.8.8) |
|------|-----------------------------------|
| master-node | enp0s6 |
| work-node | enp0s6 |
| macmini7 | enp3s0f0 |
| beelinkeqr5 | enp1s0 |

Cilium потребує `devices` — на різних нодах різні. Використовувати `auto` або перелік через кому: `enp0s6,enp3s0f0,enp1s0`.

### 2.3 Програмне забезпечення (Ubuntu)

```bash
# На всіх нодах
sudo apt-get update && sudo apt-get install -y \
  containerd curl apt-transport-https ca-certificates

# containerd config для Cilium
sudo mkdir -p /etc/containerd
cat <<EOF | sudo tee /etc/containerd/config.toml
version = 2
[plugins."io.containerd.grpc.v1.cri"]
  systemd_cgroup = true
EOF
sudo systemctl restart containerd
```

### 2.4 kubeadm, kubelet, kubectl

```bash
# На всіх нодах
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

---

## 3. Фаза 1: 1 control-plane + 3 worker

### 3.1 На master-node (10.0.10.10)

```bash
# Ініціалізація з pod CIDR для Cilium (10.244.0.0/16 — стандарт kubeadm)
# --upload-certs — для подальшого join control-plane
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --control-plane-endpoint=10.0.10.10:6443 \
  --upload-certs \
  --apiserver-advertise-address=10.0.10.10

# Після успіху — налаштувати kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**Зберегти вивід** — знадобляться:
- `kubeadm join ... --token ...` для worker
- `kubeadm join ... --control-plane --certificate-key ...` для control-plane (або згенерувати пізніше)

### 3.2 Cilium (до join worker — інакше pods в Pending)

```bash
# На master-node — скопіювати values-k8s.yaml з репо або створити локально
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium --version 1.19.0 \
  -n kube-system \
  -f values-k8s.yaml
# values-k8s.yaml: manifests/cilium/values-k8s.yaml
```

### 3.3 Join worker-нод

> **Join-команди збережено в** `manifests/scripts/k8s-join-commands.txt`

> **macmini7, beelinkeqr5 (swap увімкнено):** перед join додати `failSwapOn: false` у `/var/lib/kubelet/config.yaml` (після `kind: KubeletConfiguration`), інакше kubelet падатиме. Або вимкнути swap: `sudo swapoff -a`.

**Worker (work-node, macmini7, beelinkeqr5):**
```bash
sudo kubeadm join 10.0.10.10:6443 --token 3pki2x.8yfddbsl5ch6ifw4 \
  --discovery-token-ca-cert-hash sha256:64ad9b8b382a5e306bdcb32ee5e3e7a4bb551ba6d6debff468572f0639040dfc
```

**Control-plane (macmini7, beelinkeqr5 — для фази 2):**
```bash
sudo kubeadm join 10.0.10.10:6443 --token 3pki2x.8yfddbsl5ch6ifw4 \
  --discovery-token-ca-cert-hash sha256:64ad9b8b382a5e306bdcb32ee5e3e7a4bb551ba6d6debff468572f0639040dfc \
  --control-plane --certificate-key e1ea162b619905a51e4faf70600db604906c473b6eac33ddfc1bc0bfccc05019
```

> **Certificate-key** дійсний ~2 години. Потім: `kubeadm init phase upload-certs --upload-certs` на master-node.

### 3.4 Перевірка

```bash
kubectl get nodes
# Всі 4 ноди Ready
kubectl get pods -n kube-system
# cilium, coredns Running
```

---

## 4. Фаза 2: Promote macmini7 та beelinkeqr5 до control-plane

### 4.1 Отримати certificate-key (якщо не зберегли)

```bash
# На master-node
sudo kubeadm init phase upload-certs --upload-certs
# Вивід: certificate-key — зберегти
```

### 4.2 Отримати join-команду для control-plane

```bash
kubeadm token create --print-join-command
# Додати --control-plane --certificate-key <KEY>
```

### 4.3 На macmini7

```bash
sudo kubeadm join 10.0.10.10:6443 \
  --token 3pki2x.8yfddbsl5ch6ifw4 \
  --discovery-token-ca-cert-hash sha256:64ad9b8b382a5e306bdcb32ee5e3e7a4bb551ba6d6debff468572f0639040dfc \
  --control-plane \
  --certificate-key e1ea162b619905a51e4faf70600db604906c473b6eac33ddfc1bc0bfccc05019 \
  --apiserver-advertise-address=192.168.2.19
```

### 4.4 На beelinkeqr5

```bash
sudo kubeadm join 10.0.10.10:6443 \
  --token 3pki2x.8yfddbsl5ch6ifw4 \
  --discovery-token-ca-cert-hash sha256:64ad9b8b382a5e306bdcb32ee5e3e7a4bb551ba6d6debff468572f0639040dfc \
  --control-plane \
  --certificate-key e1ea162b619905a51e4faf70600db604906c473b6eac33ddfc1bc0bfccc05019 \
  --apiserver-advertise-address=192.168.1.19
```

### 4.5 Налаштувати kubeconfig на нових control-plane

```bash
# На macmini7 та beelinkeqr5
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 4.6 Control-plane endpoint

Після додавання control-plane нод, клієнти (kubectl, kubelet) мають підключатися до **одного** endpoint. Варіанти:

- **A.** Використовувати IP master-node `10.0.10.10` — всі йдуть туди (просто, але SPOF для доступу).
- **B.** Load balancer перед 10.0.10.10, 192.168.2.19, 192.168.1.19 (HA для клієнтів).
- **C.** DNS round-robin (менш надійно для etcd, краще для kubectl).

Для початку достатньо **10.0.10.10** — etcd вже HA (3 ноди), API запити йдуть на будь-яку control-plane.

---

## 5. Підсумок ролей

| Нода | Роль | Після Фази 2 |
|------|------|--------------|
| master-node | control-plane | control-plane only |
| work-node | worker | worker only |
| macmini7 | worker → control-plane | control-plane + worker |
| beelinkeqr5 | worker → control-plane | control-plane + worker |

---

## 6. Cilium values для k8s

Файл `manifests/cilium/values-k8s.yaml`:

| Параметр | Значення |
|----------|----------|
| `pod-network-cidr` | 10.244.0.0/16 (kubeadm) |
| `devices` | `auto` (різні інтерфейси на нодах) |
| `ipv4NativeRoutingCIDR` | 10.244.0.0/16 |
| `k8sServiceHost` | 10.0.10.10 |
| `l7Proxy` | false (уникнення TPROXY/host connectivity issues) |
| `gatewayAPI` | false (потребує l7Proxy) |

---

## 7. Відновлення з k3s

Перед початком:

1. **Бекап** manifests, secrets, PVC з поточного кластера.
2. **Видалити k3s** на всіх нодах:
   ```bash
   /usr/local/bin/k3s-uninstall.sh   # або k3s-agent-uninstall.sh
   sudo rm -rf /etc/cni/net.d /var/lib/rancher/k3s/agent/etc/cni/
   ```
3. Встановити containerd, kubeadm (див. 2.3, 2.4).
4. Виконати Фазу 1, потім Фазу 2.

---

## 8. Ingress після міграції

k8s не має вбудованого Traefik. Варіанти:

- **Traefik** — встановити вручну (Helm або manifests).
- **Cilium Ingress** — потребує `l7Proxy: true`; якщо вимкнено — використовувати Traefik або Nginx Ingress.
