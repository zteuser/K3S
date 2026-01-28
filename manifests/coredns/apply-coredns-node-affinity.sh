#!/bin/bash
# Застосувати nodeAffinity до CoreDNS, щоб под планувався лише на нодах з доступом до API
# (master-node, macmini7). Виправляє "no route to host" та Readiness probe 503 на work-node.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Applying CoreDNS nodeAffinity patch (schedule only on master-node, macmini7)..."
kubectl patch deployment coredns -n kube-system --patch-file="${SCRIPT_DIR}/coredns-node-affinity-patch.yaml"
echo "Patch applied. CoreDNS will reschedule; check: kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide"
kubectl rollout status deployment/coredns -n kube-system --timeout=120s 2>/dev/null || true
