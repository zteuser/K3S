#!/bin/bash

# Скрипт для діагностики проблем з підключенням Portainer до Kubernetes API

echo "=== Діагностика підключення Portainer до Kubernetes API ==="
echo ""

# 1. Перевірка Kubernetes API сервісу
echo "1. Перевірка Kubernetes API сервісу..."
kubectl get svc kubernetes -n default
echo ""

# 2. Перевірка доступу до API з Pod
echo "2. Тестування доступу до Kubernetes API з Pod..."
POD_NAME=$(kubectl get pods -n portainer -l app=portainer -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD_NAME" ]; then
    echo "   Pod: $POD_NAME"
    echo "   Тестування DNS резолюції..."
    kubectl exec -n portainer $POD_NAME -- nslookup kubernetes.default.svc.cluster.local || echo "   ❌ DNS не працює"
    echo ""
    echo "   Тестування підключення до API..."
    kubectl exec -n portainer $POD_NAME -- curl -k https://kubernetes.default.svc:443/version 2>/dev/null || \
    kubectl exec -n portainer $POD_NAME -- curl -k https://10.43.0.1:443/version 2>/dev/null || \
    echo "   ❌ Не вдалося підключитися до API"
    echo ""
    echo "   Перевірка ServiceAccount token..."
    kubectl exec -n portainer $POD_NAME -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | head -c 20
    echo "... (token наявний)"
    echo ""
else
    echo "   ❌ Pod не знайдено"
fi
echo ""

# 3. Перевірка CoreDNS
echo "3. Перевірка CoreDNS..."
kubectl get pods -n kube-system | grep coredns || kubectl get pods -n kube-system | grep dns
echo ""

# 4. Рекомендації
echo "=== Рекомендації ==="
echo ""
echo "Якщо DNS не працює, спробуйте:"
echo "1. Видалити поточний environment 'local' в Portainer UI"
echo "2. Додати новий environment через 'Add environment' → 'Kubernetes' → 'Import from cluster'"
echo "   Це автоматично використає ServiceAccount token і обійде проблеми з DNS"
echo ""
echo "Або вручну вкажіть:"
echo "- Environment URL: https://10.43.0.1:443"
echo "- Skip TLS verification: увімкнено"
echo "- Service account token: (залишити порожнім для автоматичного використання)"
echo ""
