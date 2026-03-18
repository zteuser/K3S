#!/bin/bash
# Запустити з master-node (ubuntu@master-node) для відновлення кворуму
# Використання: bash run-from-master-node.sh

set -e

echo "=== 1. Перевірка портів etcd (2380) ==="
nc -zv -w3 192.168.2.19 2380 2>&1 || echo "macmini7:2380 — недоступний"
nc -zv -w3 192.168.1.19 2380 2>&1 || echo "beelinkeqr5:2380 — недоступний"

echo ""
echo "=== 2. Запуск k3s на macmini7 та beelinkeqr5 ==="
# Потрібен SSH з master-node до peer (ключ або пароль)
# User для SSH до macmini7/beelinkeqr5 (malex з backup, або ubuntu)
USER="${SSH_USER:-malex}"

ssh -o ConnectTimeout=10 $USER@192.168.2.19 'sudo systemctl start k3s' 2>&1 || echo "macmini7: не вдалося"
ssh -o ConnectTimeout=10 $USER@192.168.1.19 'sudo systemctl start k3s' 2>&1 || echo "beelinkeqr5: не вдалося"

echo ""
echo "=== 3. Очікування кворуму (30 с) ==="
sleep 30

echo ""
echo "=== 4. Перевірка k3s ==="
sudo systemctl status k3s --no-pager | head -15
