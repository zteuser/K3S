#!/bin/bash
# Перевірка конективності з тієї ж ноди, що й Portainer (master-node):
# API 10.43.0.1, DNS 10.43.0.10, kubelet work-node 10.0.10.20:10250.
# Запуск з хоста з kubectl: ./test-connectivity-from-portainer-node.sh

set -e

NODE="${1:-master-node}"

echo "Running connectivity test from a pod on node: $NODE"
echo ""

kubectl run conn-test --rm -it --restart=Never \
  --image=curlimages/curl \
  --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$NODE\"}}}" \
  -- sh -c '
    echo "=== 1. API 10.43.0.1:443 ==="
    curl -ks -m 5 https://10.43.0.1:443/version 2>&1 | head -5 || echo "FAIL or timeout"
    echo ""
    echo "=== 2. DNS 10.43.0.10 (nslookup) ==="
    nslookup kubernetes.default.svc.cluster.local 10.43.0.10 2>&1 || echo "FAIL or timeout"
    echo ""
    echo "=== 3. Kubelet work-node 10.0.10.20:10250 (direct from pod) ==="
    curl -ks -m 5 https://10.0.10.20:10250/metrics 2>&1 | head -3 || echo "FAIL or timeout"
  '

echo ""
echo "Done. If 1 or 2 fail — check FORWARD/INPUT for 10.42/10.43 on all nodes."
echo "If 3 fails but nc from host to 10.0.10.20:10250 works — kubelet may reject direct pod connections; 502 in Portainer is from API server proxy (host -> work-node), check firewall on work-node for port 10250."
