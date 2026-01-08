#!/bin/bash

# Скрипт для збільшення розміру PVC до 50Gi
# Використання: ./increase-pvc-size.sh

set -e

echo "=== Збільшення розміру PVC до 50Gi ==="
echo ""

# Перевірка поточного стану
echo "1. Поточний стан PVC:"
kubectl get pvc -n default | grep sharedata
echo ""

# Оновлення StorageClass для дозволу розширення
echo "2. Оновлення StorageClass для дозволу розширення..."
kubectl apply -f storageclass-ocfs2.yaml
echo "✅ StorageClass оновлено"
echo ""

# Важливо: PVC не можна зменшити, тільки збільшити
# Для збільшення існуючого PVC використовуємо kubectl patch
echo "3. Збільшення розміру існуючих PVC..."

# Збільшуємо pvc-sharedata1-example
echo "   Оновлення pvc-sharedata1-example..."
kubectl patch pvc pvc-sharedata1-example -n default -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}' || {
    echo "⚠️  Не вдалося оновити через patch, потрібно видалити і створити заново"
    echo "   Видалення pvc-sharedata1-example..."
    kubectl delete pvc pvc-sharedata1-example -n default
    echo "   Створення нового pvc-sharedata1-example з розміром 50Gi..."
    kubectl apply -f persistentvolumeclaim-example.yaml
}

# Збільшуємо pvc-sharedata2-example
echo "   Оновлення pvc-sharedata2-example..."
kubectl patch pvc pvc-sharedata2-example -n default -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}' || {
    echo "⚠️  Не вдалося оновити через patch, потрібно видалити і створити заново"
    echo "   Видалення pvc-sharedata2-example..."
    kubectl delete pvc pvc-sharedata2-example -n default
    echo "   Створення нового pvc-sharedata2-example з розміром 50Gi..."
    kubectl apply -f persistentvolumeclaim-example.yaml
}

echo ""
echo "4. Очікування оновлення PVC..."
sleep 5

# Перевірка нового стану
echo "5. Новий стан PVC:"
kubectl get pvc -n default | grep sharedata
echo ""

echo "=== Готово ==="
echo ""
echo "📝 Важливо:"
echo "   - Фактичний розмір залежить від реального розміру OCFS2 файлової системи"
echo "   - Якщо OCFS2 файлова система менше 50Gi, PVC не зможе використати весь простір"
echo "   - Для перевірки реального розміру виконайте на нодах:"
echo "     df -h | grep share"
