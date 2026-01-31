#!/bin/bash
# Застосувати iptables-правила для доступу подів до DNS (10.43.0.10) і API (10.43.0.1).
# Запускати на КОЖНІЙ ноді кластера (master-node, macmini7, beelinkeqr5, work-node).
# Запуск: sudo ./apply-fix-dns-api.sh

set -e
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0"; exit 1; }

# INPUT: pod/service CIDR
iptables -I INPUT 1 -s 10.43.0.0/16 -j ACCEPT
iptables -I INPUT 1 -d 10.43.0.0/16 -j ACCEPT
iptables -I INPUT 1 -s 10.42.0.0/16 -j ACCEPT
iptables -I INPUT 1 -d 10.42.0.0/16 -j ACCEPT

# FORWARD: pod/service CIDR (на початок ланцюга, перед KUBE-ROUTER-FORWARD)
iptables -I FORWARD 1 -s 10.42.0.0/16 -j ACCEPT
iptables -I FORWARD 1 -d 10.42.0.0/16 -j ACCEPT
iptables -I FORWARD 1 -s 10.43.0.0/16 -j ACCEPT
iptables -I FORWARD 1 -d 10.43.0.0/16 -j ACCEPT

# На work-node: вхід з тунелю 192.168.200.x (OTV return path)
if [ "$(hostname)" = "work-node" ]; then
  iptables -I INPUT 1 -s 192.168.200.0/30 -j ACCEPT
fi

# На beelinkeqr5: вхід на kubelet (10250) і node-exporter (9100) для Prometheus
if [ "$(hostname)" = "beelinkeqr5" ]; then
  iptables -I INPUT 1 -p tcp --dport 10250 -s 10.0.0.0/8 -j ACCEPT
  iptables -I INPUT 1 -p tcp --dport 10250 -s 192.168.0.0/16 -j ACCEPT
  iptables -I INPUT 1 -p tcp --dport 9100 -s 10.0.0.0/8 -j ACCEPT
  iptables -I INPUT 1 -p tcp --dport 9100 -s 192.168.0.0/16 -j ACCEPT
fi

echo "Rules applied. FORWARD head:"
iptables -L FORWARD -n -v | head -10
echo ""
echo "Save rules: sudo netfilter-persistent save  (or sudo iptables-save | sudo tee /etc/iptables/rules.v4)"
