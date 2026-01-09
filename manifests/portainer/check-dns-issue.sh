#!/bin/bash

# Скрипт для перевірки DNS проблеми в Portainer

set -e

echo "=== Перевірка DNS проблеми Portainer ==="
echo ""

# 1. Перевірка DNS в кластері
echo "1. Перевірка DNS в кластері..."
echo "   Тест DNS з Pod Portainer:"
kubectl run -it --rm --restart=Never --image=busybox:1.36 --namespace=portainer dns-test -- nslookup kubernetes.default.svc.cluster.local || echo "   ⚠️  DNS lookup не вдався"
echo ""

# 2. Перевірка CoreDNS
echo "2. Перевірка CoreDNS Pods:"
kubectl get pods -n kube-system -l k8s-app=kube-dns
echo ""

# 3. Перевірка Service kubernetes
echo "3. Перевірка Kubernetes API Service:"
kubectl get svc kubernetes -n default
echo ""

# 4. Перевірка, чи Portainer може досягти Kubernetes API
echo "4. Перевірка доступності Kubernetes API з Pod Portainer:"
PORTAINER_POD=$(kubectl get pods -n portainer -l app=portainer -o jsonpath='{.items[0].metadata.name}')
if [ -n "$PORTAINER_POD" ]; then
    echo "   Pod: $PORTAINER_POD"
    echo "   Тест підключення до kubernetes.default.svc:"
    kubectl exec -n portainer $PORTAINER_POD -- sh -c "nslookup kubernetes.default.svc.cluster.local || echo 'DNS lookup failed'" 2>/dev/null || echo "   ⚠️  Не вдалося виконати DNS lookup"
    echo "   Тест підключення до Kubernetes API:"
    kubectl exec -n portainer $PORTAINER_POD -- sh -c "curl -k https://kubernetes.default.svc:443/healthz 2>&1 | head -1" 2>/dev/null || echo "   ⚠️  Не вдалося підключитися до Kubernetes API"
else
    echo "   ⚠️  Portainer Pod не знайдено"
fi
echo ""

# 5. Перевірка environment налаштувань
echo "5. Рекомендації:"
echo "   Якщо DNS не працює, можна використати IP адресу Kubernetes API:"
K8S_API_IP=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}')
echo "   Kubernetes API IP: $K8S_API_IP"
echo ""
echo "   Або використати повне DNS ім'я:"
echo "   kubernetes.default.svc.cluster.local:443"
echo ""

echo "=== Готово ==="
