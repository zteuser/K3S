#!/bin/bash
# Тест резолву hostname через CoreDNS у кластері.
# Запускає тимчасовий pod і виконує nslookup для внутрішніх та зовнішніх імен.
# Запуск: sudo ./test-coredns-resolve.sh   (якщо потрібен sudo для kubectl)
set -e
# default namespace — щоб коротке ім'я "kubernetes" резолвилось (сервіс у default)
NAMESPACE="${NAMESPACE:-default}"
IMAGE="${IMAGE:-busybox:1.36}"

echo "=== CoreDNS resolve test ==="
echo ""

# Cluster DNS (kube-dns Service)
DNS_IP=$(kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "10.43.0.10")
echo "Cluster DNS (kube-dns): $DNS_IP"
echo ""

# Один под виконує всі nslookup (швидше, менше створюється подів)
echo "Running nslookup from a temporary pod (uses cluster DNS by default)..."
echo ""

kubectl run dns-test-resolve --rm -i --restart=Never -n "$NAMESPACE" --image="$IMAGE" -- sh -c '
  echo "1. kubernetes.default.svc.cluster.local (Kubernetes API):"
  nslookup kubernetes.default.svc.cluster.local
  echo ""
  echo "2. kube-dns.kube-system.svc.cluster.local (CoreDNS):"
  nslookup kube-dns.kube-system.svc.cluster.local
  echo ""
  echo "3. kubernetes (short name — працює лише з namespace default):"
  nslookup kubernetes
  echo ""
  echo "4. google.com (external):"
  nslookup google.com
  echo ""
  echo "5. prometheus.monitoring.svc (if monitoring namespace exists):"
  nslookup prometheus.monitoring.svc.cluster.local 2>/dev/null || echo "(skip or not found)"
' 2>&1

echo ""
echo "=== Test done ==="
