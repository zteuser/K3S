#!/bin/bash
# k8s + Cilium — setup master-node (10.0.10.10)
# Запускати на master-node після відновлення connectivity
#
# Передумова: SSH на master-node, sudo доступ

set -e

echo "=== Крок 1: Видалити k3s ==="
/usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
sudo rm -rf /etc/cni/net.d /var/lib/rancher/k3s /var/lib/kubelet /etc/rancher/k3s
sudo rm -rf /var/lib/etcd 2>/dev/null || true

echo "=== Крок 2: containerd ==="
sudo apt-get update && sudo apt-get install -y containerd curl apt-transport-https ca-certificates
sudo mkdir -p /etc/containerd
cat <<'EOF' | sudo tee /etc/containerd/config.toml
version = 2
[plugins."io.containerd.grpc.v1.cri"]
  systemd_cgroup = true
EOF
sudo systemctl restart containerd
sudo systemctl enable containerd

echo "=== Крок 3: Kernel modules (для kubeadm) ==="
sudo modprobe br_netfilter
sudo modprobe overlay
echo 'br_netfilter' | sudo tee -a /etc/modules-load.d/k8s.conf 2>/dev/null || true
echo 'overlay' | sudo tee -a /etc/modules-load.d/k8s.conf 2>/dev/null || true
echo 'net.bridge.bridge-nf-call-iptables = 1' | sudo tee -a /etc/sysctl.d/99-kubernetes.conf 2>/dev/null || true
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-kubernetes.conf 2>/dev/null || true
sudo sysctl --system 2>/dev/null || true

echo "=== Крок 4: kubeadm, kubelet, kubectl ==="
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "=== Крок 5: kubeadm init ==="
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --control-plane-endpoint=10.0.10.10:6443 \
  --upload-certs \
  --apiserver-advertise-address=10.0.10.10

echo "=== Крок 6: kubeconfig ==="
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo ""
echo "=== ГОТОВО ==="
echo "Збережіть вивід 'kubeadm join' для worker та control-plane."
echo "Далі: helm install cilium (див. K8S_KUBEADM_CILIUM_PLAN.md)"
