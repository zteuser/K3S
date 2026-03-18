#!/bin/bash
# Скрипт для збереження конфігурації k3s на кожній ноді.
# Запускати на КОЖНІЙ ноді кластера (SSH або локально).
#
# Використання:
#   ssh user@macmini7 'bash -s' < backup-node-configs.sh
#   або скопіювати на ноду і запустити: ./backup-node-configs.sh
#
# Результат виводиться в stdout — перенаправити у файл:
#   ssh user@macmini7 'bash -s' < backup-node-configs.sh > node-macmini7.txt

echo "=== $(hostname) @ $(date -Iseconds) ==="
echo ""

echo "--- /etc/rancher/k3s/config.yaml ---"
if [ -f /etc/rancher/k3s/config.yaml ]; then
  cat /etc/rancher/k3s/config.yaml
else
  echo "(файл не знайдено)"
fi
echo ""

echo "--- systemctl cat k3s (або k3s-agent) ---"
if systemctl is-active --quiet k3s 2>/dev/null; then
  systemctl cat k3s 2>/dev/null || true
elif systemctl is-active --quiet k3s-agent 2>/dev/null; then
  systemctl cat k3s-agent 2>/dev/null || true
else
  echo "(сервіс не знайдено)"
fi
echo ""

echo "--- ip route (default) ---"
ip route | grep default || true
echo ""

echo "--- інтерфейс для Cilium (ip route get 8.8.8.8) ---"
ip route get 8.8.8.8 2>/dev/null || true
