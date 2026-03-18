#!/bin/bash
# Видалення k3s та залишків CNI
# Запускати на КОЖНІЙ ноді: master-node, work-node, macmini7, beelinkeqr5

set -e

echo "=== Видалення k3s ==="

# Server або agent — пробуємо обидва
/usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
/usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true

echo "=== Видалення залишків ==="
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/rancher/k3s
sudo rm -rf /var/lib/kubelet
sudo rm -rf /etc/rancher/k3s
sudo rm -rf /var/lib/etcd
sudo rm -rf /var/lib/cni
sudo rm -rf /opt/cni

# k3s-specific
sudo rm -f /usr/local/bin/k3s /usr/local/bin/k3s-agent 2>/dev/null || true
sudo rm -f /usr/local/bin/k3s-uninstall.sh /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true

# Сервіси (якщо залишились)
sudo systemctl stop k3s k3s-agent 2>/dev/null || true
sudo systemctl disable k3s k3s-agent 2>/dev/null || true
sudo rm -f /etc/systemd/system/k3s*.service 2>/dev/null || true
sudo systemctl daemon-reload

echo "=== Готово ==="
echo "Перевірка:"
ls -la /etc/cni/net.d 2>/dev/null || echo "  /etc/cni/net.d — порожній або відсутній (ок)"
ls /var/lib/rancher/k3s 2>/dev/null || echo "  /var/lib/rancher/k3s — видалено (ок)"
