#!/bin/bash

# Скрипт для виправлення PVC portainer-data
# Використання: ./fix-portainer-pvc.sh

set -e

echo "=== Виправлення PVC portainer-data ==="
echo ""

# Перевірка поточного стану
echo "1. Поточний стан PVC portainer-data:"
kubectl get pvc portainer-data -n portainer
echo ""

# Перевірка доступних PV
echo "2. Доступні PV:"
kubectl get pv | grep sharedata
echo ""

# Перевірка чи є доступний PV для portainer
PV_SHAREDATA1=$(kubectl get pv pv-sharedata1 -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
PV_SHAREDATA2=$(kubectl get pv pv-sharedata2 -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

if [ "$PV_SHAREDATA1" = "Available" ]; then
    echo "✅ pv-sharedata1 доступний, використаємо його"
    PV_TO_USE="pv-sharedata1"
elif [ "$PV_SHAREDATA2" = "Available" ]; then
    echo "✅ pv-sharedata2 доступний, використаємо його"
    PV_TO_USE="pv-sharedata2"
else
    echo "⚠️  Жоден PV не доступний, потрібно створити новий"
    echo "   Створення нового PV для Portainer..."
    
    # Створюємо новий PV для Portainer
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-portainer-data
  labels:
    type: ocfs2
    storage: portainer
spec:
  capacity:
    storage: 45Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ocfs2-shared
  hostPath:
    path: /sharedata1
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - master-node
          - work-node
EOF
    PV_TO_USE="pv-portainer-data"
    echo "✅ Новий PV створено: $PV_TO_USE"
fi

echo ""
echo "3. Оновлення PVC portainer-data..."

# Видаляємо finalizers та оновлюємо PVC
kubectl patch pvc portainer-data -n portainer -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true

# Видаляємо старий PVC
echo "   Видалення старого PVC..."
kubectl delete pvc portainer-data -n portainer --grace-period=0 --force 2>/dev/null || true
sleep 2

# Створюємо новий PVC
echo "   Створення нового PVC..."
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
      storage: portainer
EOF

# Якщо використовуємо існуючий PV, потрібно оновити labels
if [ "$PV_TO_USE" != "pv-portainer-data" ]; then
    echo "   Оновлення labels на PV для зв'язування..."
    kubectl label pv $PV_TO_USE storage=portainer --overwrite
fi

echo "✅ PVC створено"
echo ""

# Очікування зв'язування
echo "4. Очікування зв'язування..."
sleep 5

# Перезапуск Portainer Pod для підключення нового PVC
echo "5. Перезапуск Portainer Pod..."
kubectl rollout restart deployment/portainer -n portainer
echo "✅ Pod перезапущено"
echo ""

# Перевірка статусу
echo "6. Фінальний статус:"
echo ""
echo "PVC:"
kubectl get pvc portainer-data -n portainer
echo ""
echo "PV:"
kubectl get pv | grep -E "sharedata|portainer"
echo ""

echo "=== Готово ==="
echo ""
echo "📝 Перевірте Portainer UI - попередження має зникнути після перезапуску Pod"
