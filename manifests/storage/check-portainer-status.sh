#!/bin/bash

# Скрипт для перевірки статусу Portainer PVC
# Використання: ./check-portainer-status.sh

echo "=== Перевірка статусу Portainer PVC ==="
echo ""

echo "1. Статус PVC:"
kubectl get pvc portainer-data -n portainer
echo ""

echo "2. Статус PV:"
kubectl get pv | grep -E "sharedata|portainer"
echo ""

echo "3. Статус Portainer Pod:"
kubectl get pods -n portainer -l app=portainer
echo ""

echo "4. Деталі Pod (volume mounts):"
POD_NAME=$(kubectl get pods -n portainer -l app=portainer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD_NAME" ]; then
    kubectl describe pod $POD_NAME -n portainer | grep -A 10 "Volumes:"
    echo ""
    echo "5. Події Pod:"
    kubectl get events -n portainer --field-selector involvedObject.name=$POD_NAME --sort-by='.lastTimestamp' | tail -5
else
    echo "   Pod не знайдено"
fi

echo ""
echo "=== Якщо PVC все ще Pending ==="
echo "Спробуйте перезапустити Pod:"
echo "  kubectl delete pod -n portainer -l app=portainer"
echo "Або:"
echo "  kubectl rollout restart deployment/portainer -n portainer"
