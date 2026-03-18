#!/usr/bin/env bash
# Налаштування kubectl на ноуті: копіювання kubeconfig з master-node (malex@10.0.10.10)
# Запускати на ноуті: bash scripts/setup-kubectl-on-laptop.sh

set -e

SSH_USER="${SSH_USER:-malex}"
MASTER_IP="${MASTER_IP:-10.0.10.10}"
KUBECONFIG_LOCAL="${HOME}/.kube/k8s-config"

echo "=== Копіювання kubeconfig з ${SSH_USER}@${MASTER_IP} ==="
mkdir -p ~/.kube

# На сервері admin.conf часто доступний лише root — використовуємо sudo cat
if ssh "${SSH_USER}@${MASTER_IP}" "test -r /etc/kubernetes/admin.conf 2>/dev/null"; then
  scp "${SSH_USER}@${MASTER_IP}:/etc/kubernetes/admin.conf" "$KUBECONFIG_LOCAL"
else
  ssh "${SSH_USER}@${MASTER_IP}" "sudo cat /etc/kubernetes/admin.conf" > "$KUBECONFIG_LOCAL"
fi

echo "=== Встановлення server: https://${MASTER_IP}:6443 ==="
# Замінити server на IP master, щоб з ноута підключатись до 10.0.10.10
if sed --version 2>/dev/null | grep -q GNU; then
  sed -i "s|server:.*|server: https://${MASTER_IP}:6443|" "$KUBECONFIG_LOCAL"
else
  sed -i '' "s|server:.*|server: https://${MASTER_IP}:6443|" "$KUBECONFIG_LOCAL"
fi

echo "=== Kubeconfig збережено: $KUBECONFIG_LOCAL ==="
echo ""
echo "Далі виконай одну з команд:"
echo "  export KUBECONFIG=$KUBECONFIG_LOCAL"
echo "  kubectl get nodes"
echo ""
echo "Щоб зробити постійно (додати в ~/.zshrc):"
echo "  echo 'export KUBECONFIG=$KUBECONFIG_LOCAL' >> ~/.zshrc && source ~/.zshrc"
echo ""
echo "Або використати як основний config:"
echo "  cp $KUBECONFIG_LOCAL ~/.kube/config"
echo ""

# Одразу експортуємо для поточного шелу
export KUBECONFIG="$KUBECONFIG_LOCAL"
echo "Перевірка: kubectl get nodes"
kubectl get nodes
