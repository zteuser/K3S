#!/bin/bash
# Встановлення k3s + Cilium на master-node (перша нода)
# Запускати на master-node: bash install-k3s-cilium-master-node.sh

set -e

echo "=== Крок 1: Встановлення k3s (cluster-init, flannel-backend=none) ==="
# КРИТИЧНО: --disable-kube-proxy обов'язковий при kubeProxyReplacement: true в Cilium!
curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --flannel-backend=none \
  --disable-network-policy \
  --disable-kube-proxy \
  --node-ip 10.0.10.10

echo ""
echo "=== Крок 2: Додавання tls-san до config ==="
CONFIG="/etc/rancher/k3s/config.yaml"
if ! grep -q "tls-san:" "$CONFIG" 2>/dev/null; then
  cat >> "$CONFIG" << 'EOF'

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
systemctl restart k3s
sleep 5

echo ""
echo "=== Крок 4: Перевірка k3s ==="
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
echo ""
echo "Token для інших нод:"
cat /var/lib/rancher/k3s/server/node-token

echo ""
echo "=== Крок 5: Встановлення Helm (якщо немає) ==="
if ! command -v helm &>/dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo ""
echo "=== Крок 6: Встановлення Cilium ==="
helm repo add cilium https://helm.cilium.io/
helm repo update

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

helm install cilium cilium/cilium \
  --version 1.19.0 \
  --namespace kube-system \
  --values "$VALUES_FILE"

echo ""
echo "=== Очікування готовності Cilium (2-3 хв) ==="
kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s 2>/dev/null || true

echo ""
echo "=== Статус ==="
kubectl get nodes -o wide
kubectl get pods -n kube-system -l k8s-app=cilium -o wide

echo ""
echo "=== Готово! ==="
echo "Token: $(cat /var/lib/rancher/k3s/server/node-token)"
echo "API: https://10.0.10.10:6443"
echo "Для macmini7/beelinkeqr5: https://192.168.100.5:6443"
