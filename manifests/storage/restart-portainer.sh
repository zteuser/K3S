#!/bin/bash

# Скрипт для перезапуску Portainer після таймауту
# Використання: ./restart-portainer.sh

set -e

echo "=== Перезапуск Portainer ==="
echo ""

# 1. Перевірка поточного стану
echo "1. Поточний стан Portainer Pod:"
kubectl get pods -n portainer -l app=portainer
echo ""

# 2. Перезапуск Deployment
echo "2. Перезапуск Portainer Deployment..."
kubectl rollout restart deployment/portainer -n portainer
echo "✅ Deployment перезапущено"
echo ""

# 3. Очікування готовності нового Pod
echo "3. Очікування готовності нового Pod..."
kubectl rollout status deployment/portainer -n portainer --timeout=120s
echo ""

# 4. Перевірка статусу
echo "4. Статус Pod:"
kubectl get pods -n portainer -l app=portainer
echo ""

# 5. Перевірка логів
echo "5. Останні логи Pod:"
POD_NAME=$(kubectl get pods -n portainer -l app=portainer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD_NAME" ]; then
    kubectl logs -n portainer $POD_NAME --tail=20
else
    echo "   Pod не знайдено"
fi

echo ""
echo "=== Готово ==="
echo ""
echo "📝 Оновіть сторінку Portainer в браузері (Ctrl+F5 або Cmd+Shift+R)"
echo "   Якщо помилка залишається, зачекайте 1-2 хвилини і спробуйте знову"
