#!/bin/bash

# Скрипт для виправлення PVC portainer-data (версія 2)
# Використання: ./fix-portainer-pvc-v2.sh

set -e

echo "=== Виправлення PVC portainer-data ==="
echo ""

# 1. Зупинка Portainer Pod
echo "1. Зупинка Portainer Pod..."
kubectl scale deployment portainer -n portainer --replicas=0
echo "   Очікування завершення..."
sleep 5
echo "✅ Pod зупинено"
echo ""

# 2. Перевірка чи Pod зупинено
POD_COUNT=$(kubectl get pods -n portainer -l app=portainer --no-headers 2>/dev/null | wc -l)
if [ "$POD_COUNT" -gt 0 ]; then
    echo "⚠️  Pod все ще працює, примусово видаляємо..."
    kubectl delete pods -n portainer -l app=portainer --grace-period=0 --force
    sleep 3
fi
echo ""

# 3. Видалення finalizers з PVC
echo "2. Видалення finalizers з PVC..."
kubectl patch pvc portainer-data -n portainer -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || echo "   Finalizers вже видалено або PVC не існує"
echo ""

# 4. Видалення PVC
echo "3. Видалення PVC portainer-data..."
kubectl delete pvc portainer-data -n portainer --wait=false --timeout=5s 2>/dev/null || true
sleep 2

# Перевірка чи PVC видалено
if kubectl get pvc portainer-data -n portainer &>/dev/null; then
    echo "⚠️  PVC все ще існує, спробуємо примусово..."
    kubectl patch pvc portainer-data -n portainer -p '{"metadata":{"finalizers":[]}}' --type=merge
    kubectl delete pvc portainer-data -n portainer --grace-period=0 --force --wait=false
    sleep 3
fi

# Фінальна перевірка
if kubectl get pvc portainer-data -n portainer &>/dev/null; then
    echo "❌ Не вдалося видалити PVC, спробуйте вручну:"
    echo "   kubectl patch pvc portainer-data -n portainer -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge"
    echo "   kubectl delete pvc portainer-data -n portainer --grace-period=0 --force"
    exit 1
fi

echo "✅ PVC видалено"
echo ""

# 5. Створення нового PVC
echo "4. Створення нового PVC portainer-data..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: portainer-data
  namespace: portainer
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ocfs2-shared
  resources:
    requests:
      storage: 1Gi
  selector:
    matchLabels:
      storage: sharedata2
EOF

echo "✅ PVC створено"
echo ""

# 6. Очікування зв'язування
echo "5. Очікування зв'язування з PV..."
sleep 5

# Перевірка статусу
echo "6. Статус PVC:"
kubectl get pvc portainer-data -n portainer
echo ""

# 7. Запуск Portainer Pod
echo "7. Запуск Portainer Pod..."
kubectl scale deployment portainer -n portainer --replicas=1
echo "✅ Pod запущено"
echo ""

# Очікування готовності
echo "8. Очікування готовності Pod..."
sleep 10
kubectl get pods -n portainer -l app=portainer
echo ""

echo "=== Готово ==="
echo ""
echo "📝 Перевірте Portainer UI - попередження має зникнути"
