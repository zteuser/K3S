#!/bin/bash
# Крок 1 міграції: додати flannel-backend:none + зупинити k3s
# Запускати з машини з SSH до нод (malex@)
#
# Використання: ./run-migration-step1.sh

set -e
USER="${SSH_USER:-malex}"

echo "=== 1. Додаємо flannel-backend:none на server-нодах ==="
for node in macmini7:192.168.2.19 beelinkeqr5:192.168.1.19 master-node:10.0.10.10; do
  name="${node%%:*}"
  ip="${node##*:}"
  echo "  $name ($ip)..."
  ssh "$USER@$ip" "sudo bash -c 'grep -q flannel-backend /etc/rancher/k3s/config.yaml 2>/dev/null || echo -e \"\n# Cilium migration\nflannel-backend: none\ndisable-network-policy: true\" >> /etc/rancher/k3s/config.yaml'"
done

echo ""
echo "=== 2. Зупиняємо k3s-agent на work-node ==="
ssh "$USER@10.0.10.20" "sudo systemctl stop k3s-agent" || { echo "Помилка work-node"; exit 1; }

echo ""
echo "=== 3. Зупиняємо k3s на server-нодах ==="
for node in macmini7:192.168.2.19 beelinkeqr5:192.168.1.19 master-node:10.0.10.10; do
  name="${node%%:*}"
  ip="${node##*:}"
  echo "  $name ($ip)..."
  ssh "$USER@$ip" "sudo systemctl stop k3s" || { echo "Помилка $name"; exit 1; }
done

echo ""
echo "=== 4. Видаляємо flannel.1 (опційно) ==="
for node in macmini7:192.168.2.19 beelinkeqr5:192.168.1.19 master-node:10.0.10.10 work-node:10.0.10.20; do
  name="${node%%:*}"
  ip="${node##*:}"
  ssh "$USER@$ip" "sudo ip link delete flannel.1 2>/dev/null || true"
done

echo ""
echo "Готово. Далі: запустити k3s на server-нодах, встановити Cilium, запустити agent."
