#!/bin/bash

# Скрипт для перейменування PVC з -example на без суфікса
# Використання: ./rename-pvc.sh

set -e

echo "=== Перейменування PVC ==="
echo ""
echo "Перейменування:"
echo "  pvc-sharedata1-example → pvc-sharedata1"
echo "  pvc-sharedata2-example → pvc-sharedata2"
echo ""

# Перевірка активних Pods
echo "1. Перевірка активних Pods з PVC..."
PODS_WITH_PVC=$(kubectl get pods --all-namespaces -o json 2>/dev/null | \
  jq -r '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName | test("sharedata.*example")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

if [ -n "$PODS_WITH_PVC" ]; then
    echo "⚠️  Знайдено Pods що використовують старі PVC:"
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
        sleep 3
    else
        echo "❌ Скасовано - спочатку видаліть Pods вручну"
        exit 1
    fi
else
    echo "✅ Активних Pods не знайдено"
fi
echo ""

# Перевірка поточного стану
echo "2. Поточний стан PVC:"
kubectl get pvc -n default | grep sharedata || echo "   PVC не знайдено"
echo ""

# Збереження конфігурації старих PVC
echo "3. Збереження конфігурації старих PVC..."
PVC1_SPEC=$(kubectl get pvc pvc-sharedata1-example -n default -o json 2>/dev/null | jq -c '.spec' || echo "")
PVC2_SPEC=$(kubectl get pvc pvc-sharedata2-example -n default -o json 2>/dev/null | jq -c '.spec' || echo "")

if [ -z "$PVC1_SPEC" ] && [ -z "$PVC2_SPEC" ]; then
    echo "⚠️  Старі PVC не знайдено, створюємо нові з маніфестів..."
    kubectl apply -f persistentvolumeclaim-example.yaml
    echo "✅ Нові PVC створено"
    echo ""
    echo "4. Фінальний статус:"
    kubectl get pvc -n default | grep sharedata
    echo ""
    echo "=== Готово ==="
    exit 0
fi

# Видалення старих PVC
echo "4. Видалення старих PVC..."
kubectl delete pvc pvc-sharedata1-example pvc-sharedata2-example -n default --ignore-not-found=true
echo "✅ Старі PVC видалено"
echo ""

# Створення нових PVC
echo "5. Створення нових PVC з новими іменами..."
kubectl apply -f persistentvolumeclaim-example.yaml
echo "✅ Нові PVC створено"
echo ""

# Очікування зв'язування
echo "6. Очікування зв'язування PVC з PV..."
sleep 5

# Перевірка статусу
echo "7. Фінальний статус:"
echo ""
echo "PVC:"
kubectl get pvc -n default | grep sharedata
echo ""
echo "PV:"
kubectl get pv | grep sharedata
echo ""

echo "=== Перейменування завершено ==="
echo ""
echo "📊 Результат:"
echo "   ✅ pvc-sharedata1-example → pvc-sharedata1"
echo "   ✅ pvc-sharedata2-example → pvc-sharedata2"
echo ""
