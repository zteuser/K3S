#!/bin/bash

# Скрипт для оновлення PV та PVC до 45Gi
# Використання: ./update-to-45gb.sh

set -e

echo "=== Оновлення PV та PVC до 45Gi ==="
echo ""
echo "⚠️  УВАГА: Цей скрипт видалить існуючі PVC та PV!"
echo "   Переконайтеся що немає активних Pods, які використовують ці volumes"
echo ""
read -p "Продовжити? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Скасовано"
    exit 1
fi

echo ""

# Перевірка активних Pods
echo "1. Перевірка активних Pods з PVC..."
PODS_WITH_PVC=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName | test("sharedata")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")
if [ -n "$PODS_WITH_PVC" ]; then
    echo "⚠️  Знайдено Pods що використовують PVC:"
    echo "$PODS_WITH_PVC"
    echo ""
    read -p "Видалити ці Pods? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$PODS_WITH_PVC" | while read pod; do
            namespace=$(echo $pod | cut -d'/' -f1)
            name=$(echo $pod | cut -d'/' -f2)
            echo "   Видалення $namespace/$name..."
            kubectl delete pod $name -n $namespace --grace-period=0 --force 2>/dev/null || true
        done
        echo "   Очікування завершення..."
        sleep 5
    else
        echo "❌ Скасовано - спочатку видаліть Pods вручну"
        exit 1
    fi
else
    echo "✅ Активних Pods не знайдено"
fi
echo ""

# Видалення PVC
echo "2. Видалення існуючих PVC..."
kubectl delete pvc pvc-sharedata1-example pvc-sharedata2-example -n default --ignore-not-found=true
echo "✅ PVC видалено"
echo ""

# Видалення PV
echo "3. Видалення існуючих PV..."
kubectl delete pv pv-sharedata1 pv-sharedata2 --ignore-not-found=true
echo "✅ PV видалено"
echo ""

# Оновлення StorageClass
echo "4. Оновлення StorageClass..."
kubectl apply -f storageclass-ocfs2.yaml
echo "✅ StorageClass оновлено"
echo ""

# Створення нових PV з 45Gi
echo "5. Створення нових PV з 45Gi..."
kubectl apply -f persistentvolume-sharedata1.yaml
kubectl apply -f persistentvolume-sharedata2.yaml
echo "✅ PV створено"
kubectl get pv
echo ""

# Створення нових PVC з 45Gi
echo "6. Створення нових PVC з 45Gi..."
kubectl apply -f persistentvolumeclaim-example.yaml
echo "✅ PVC створено"
echo ""

# Очікування зв'язування
echo "7. Очікування зв'язування PVC з PV..."
sleep 5
kubectl get pvc -n default | grep sharedata
echo ""

# Перевірка статусу
echo "8. Фінальний статус:"
echo ""
echo "PV:"
kubectl get pv -o custom-columns=NAME:.metadata.name,CAPACITY:.spec.capacity.storage,STATUS:.status.phase
echo ""
echo "PVC:"
kubectl get pvc -n default -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName,STORAGE:.spec.resources.requests.storage
echo ""

echo "=== Оновлення завершено ==="
echo ""
echo "📊 Результат:"
echo "   - PV мають розмір: 45Gi"
echo "   - PVC запитують: 45Gi"
echo "   - Залишок для системи: 5Gi на кожен OCFS2 volume"
echo ""
