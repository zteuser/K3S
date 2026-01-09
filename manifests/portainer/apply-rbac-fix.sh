#!/bin/bash

# Скрипт для застосування виправлення RBAC прав Portainer

set -e

echo "=== Застосування виправлення RBAC прав для Portainer ==="
echo ""

# 1. Перевірка поточного ClusterRole
echo "1. Перевірка поточного ClusterRole..."
echo "   Перевірка authorization.k8s.io..."
kubectl get clusterrole portainer -o yaml | grep -A 5 "authorization.k8s.io" || echo "   ⚠️  API group authorization.k8s.io не знайдено"
echo "   Перевірка autoscaling..."
kubectl get clusterrole portainer -o yaml | grep -A 5 "autoscaling" || echo "   ⚠️  API group autoscaling не знайдено"
echo ""

# 2. Застосування оновленого ClusterRole
echo "2. Застосування оновленого ClusterRole..."
kubectl apply -f serviceaccount.yaml
echo "✅ ClusterRole оновлено"
echo ""

# 3. Перевірка, що права додані
echo "3. Перевірка оновленого ClusterRole..."
kubectl get clusterrole portainer -o yaml | grep -A 5 "authorization.k8s.io" && echo "   ✅ API group authorization.k8s.io знайдено" || echo "   ⚠️  API group authorization.k8s.io не знайдено"
kubectl get clusterrole portainer -o yaml | grep -A 5 "autoscaling" && echo "   ✅ API group autoscaling знайдено" || echo "   ⚠️  API group autoscaling не знайдено"
echo ""

# 4. Перезапуск Portainer Pod
echo "4. Перезапуск Portainer Pod для застосування нових прав..."
kubectl rollout restart deployment/portainer -n portainer
echo "✅ Portainer Pod перезапущено"
echo ""

# 5. Очікування готовності Pod
echo "5. Очікування готовності Pod..."
echo "   Це може зайняти 30-60 секунд..."
kubectl wait --for=condition=ready pod -l app=portainer -n portainer --timeout=120s
echo "✅ Pod готовий"
echo ""

# 6. Перевірка прав
echo "6. Перевірка прав ServiceAccount..."
echo "   Перевірка localsubjectaccessreviews..."
if kubectl auth can-i create localsubjectaccessreviews --as=system:serviceaccount:portainer:portainer -n default 2>/dev/null; then
    echo "   ✅ ServiceAccount має права на створення localsubjectaccessreviews"
else
    echo "   ⚠️  ServiceAccount не має прав на створення localsubjectaccessreviews"
fi
echo "   Перевірка horizontalpodautoscalers..."
if kubectl auth can-i list horizontalpodautoscalers --as=system:serviceaccount:portainer:portainer --all-namespaces 2>/dev/null; then
    echo "   ✅ ServiceAccount має права на перелік horizontalpodautoscalers"
else
    echo "   ⚠️  ServiceAccount не має прав на перелік horizontalpodautoscalers"
fi
echo ""

echo "=== Готово ==="
echo ""
echo "📝 Наступні кроки:"
echo "   1. Оновіть сторінку Portainer UI (Ctrl+F5 або Cmd+Shift+R)"
echo "   2. Перевірте Notifications - помилка RBAC має зникнути"
echo "   3. Перевірте статус environment - має стати 'Up'"
echo ""
echo "💡 Якщо помилка все ще є, перевірте логи Portainer:"
echo "   kubectl logs -n portainer -l app=portainer --tail=50"
