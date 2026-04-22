#!/bin/bash
# Встановлення k3s + Cilium на master-node (перша нода)
# Запускати на master-node: bash install-k3s-cilium-master-node.sh

set -e

CONFIG="/etc/rancher/k3s/config.yaml"
K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
# k3s, systemd, /etc/rancher, /var/lib/rancher потребують root; sudo безпечний і для root.
kubectl_k3s() { sudo kubectl --kubeconfig "$K3S_KUBECONFIG" "$@"; }
helm_k3s() { sudo helm --kubeconfig "$K3S_KUBECONFIG" "$@"; }

echo "=== Крок 1: Встановлення k3s (cluster-init, flannel-backend=none) ==="
# КРИТИЧНО: --disable-kube-proxy обов'язковий при kubeProxyReplacement: true в Cilium!
curl -sfL https://get.k3s.io | sudo sh -s - server \
  --cluster-init \
  --flannel-backend=none \
  --disable-network-policy \
  --disable-kube-proxy \
  --node-ip 10.0.10.10

echo ""
echo "=== Крок 2: Додавання tls-san до config ==="
if ! sudo grep -q "tls-san:" "$CONFIG" 2>/dev/null; then
  sudo tee -a "$CONFIG" << 'EOF' >/dev/null

tls-san:
  - 192.168.100.5
  - 192.168.100.1
  - 192.168.100.6
  - 192.168.200.6
  - 141.144.254.42
EOF
  echo "tls-san додано"
else
  echo "tls-san вже є в config"
fi

echo ""
echo "=== Крок 3: Перезапуск k3s ==="
sudo systemctl restart k3s
sleep 5

echo ""
echo "=== Крок 4: Перевірка k3s ==="
kubectl_k3s get nodes
echo ""
echo "Token для інших нод:"
sudo cat /var/lib/rancher/k3s/server/node-token

echo ""
echo "=== Крок 5: Встановлення Helm (якщо немає) ==="
if ! command -v helm &>/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
fi

echo ""
echo "=== Крок 6: Встановлення Cilium ==="
helm_k3s repo add cilium https://helm.cilium.io/
helm_k3s repo update

# values-k3s.yaml: передати як аргумент або має бути поруч зі скриптом
VALUES_FILE="${1:-$(dirname "$0")/cilium/values-k3s.yaml}"
if [ ! -f "$VALUES_FILE" ]; then
  VALUES_FILE="./values-k3s.yaml"
fi
if [ ! -f "$VALUES_FILE" ]; then
  echo "ПОМИЛКА: values-k3s.yaml не знайдено."
  echo "Скопіюйте на master-node: scp manifests/cilium/values-k3s.yaml ubuntu@141.144.254.42:~/"
  echo "Запустіть: bash install-k3s-cilium-master-node.sh ~/values-k3s.yaml"
  exit 1
fi
echo "Використовую values: $VALUES_FILE"

helm_k3s install cilium cilium/cilium \
  --version 1.19.0 \
  --namespace kube-system \
  --values "$VALUES_FILE"

echo ""
echo "=== Очікування готовності Cilium (2-3 хв) ==="
kubectl_k3s wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s 2>/dev/null || true

echo ""
echo "=== Статус ==="
kubectl_k3s get nodes -o wide
kubectl_k3s get pods -n kube-system -l k8s-app=cilium -o wide

echo ""
echo "=== Готово! ==="
echo "Token: $(sudo cat /var/lib/rancher/k3s/server/node-token)"
echo "API: https://10.0.10.10:6443"
echo "Для macmini7/beelinkeqr5: https://192.168.100.5:6443"
