#!/bin/bash

# Скрипт для виправлення RBAC прав Portainer
# Додає права для authorization.k8s.io API group

set -e

echo "=== Виправлення RBAC прав для Portainer ==="
echo ""

# 1. Оновлення ClusterRole
echo "1. Оновлення ClusterRole з правами для authorization.k8s.io..."
kubectl apply -f serviceaccount.yaml
echo "✅ ClusterRole оновлено"
echo ""

# 2. Перезапуск Portainer Pod для застосування нових прав
echo "2. Перезапуск Portainer Pod для застосування нових прав..."
kubectl rollout restart deployment/portainer -n portainer
echo "✅ Portainer Pod перезапущено"
echo ""

# 3. Очікування готовності Pod
echo "3. Очікування готовності Pod..."
kubectl wait --for=condition=ready pod -l app=portainer -n portainer --timeout=120s
echo "✅ Pod готовий"
echo ""

# 4. Перевірка прав
echo "4. Перевірка прав ServiceAccount..."
kubectl auth can-i create localsubjectaccessreviews --as=system:serviceaccount:portainer:portainer -n default
echo ""

echo "=== Готово ==="
echo ""
echo "📝 Перевірте Portainer UI - помилка RBAC має зникнути"
echo "   Якщо помилка все ще є, оновіть сторінку в браузері (Ctrl+F5)"
