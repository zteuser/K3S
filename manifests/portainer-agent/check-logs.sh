#!/bin/bash

# Скрипт для перевірки логів Portainer Agent

echo "=== Перевірка логів Portainer Agent ==="
echo ""

POD_NAME=$(kubectl get pods -n portainer-agent -l app=portainer-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo "❌ Pod не знайдено"
    exit 1
fi

echo "Pod: $POD_NAME"
echo ""
echo "=== Останні логи ==="
kubectl logs -n portainer-agent $POD_NAME --tail=50
echo ""
echo "=== Опис Pod ==="
kubectl describe pod -n portainer-agent $POD_NAME | tail -30
