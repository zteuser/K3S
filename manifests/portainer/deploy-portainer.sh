#!/bin/bash

# Скрипт для deployment Portainer в k3s cluster
# Використання: ./deploy-portainer.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Deployment Portainer для k3s Cluster ==="
echo ""

# Перевірка підключення до кластера
echo "1. Перевірка підключення до кластера..."
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Помилка: Не вдалося підключитися до кластера k3s"
    echo "   Перевірте що kubectl налаштований правильно"
    exit 1
fi
echo "✅ Підключення до кластера успішне"
echo ""

# Перевірка нод
echo "2. Перевірка нод кластера..."
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
echo "   Знайдено ноди: $NODES"
if ! echo "$NODES" | grep -q "master-node\|work-node"; then
    echo "⚠️  Попередження: Не знайдено ноди master-node або work-node"
    echo "   Переконайтеся що ноди правильно названі"
fi
echo ""

# Перевірка StorageClass
echo "3. Перевірка StorageClass ocfs2-shared..."
if ! kubectl get storageclass ocfs2-shared &>/dev/null; then
    echo "❌ Помилка: StorageClass ocfs2-shared не знайдено"
    echo "   Спочатку створіть storage: cd ../storage && ./deploy-storage.sh"
    exit 1
fi
echo "✅ StorageClass ocfs2-shared знайдено"
echo ""

# Перевірка PV
echo "4. Перевірка PersistentVolumes..."
PV_COUNT=$(kubectl get pv -o jsonpath='{.items[*].metadata.name}' | wc -w)
if [ "$PV_COUNT" -eq 0 ]; then
    echo "⚠️  Попередження: Не знайдено PersistentVolumes"
    echo "   Створіть PV: cd ../storage && ./deploy-storage.sh"
else
    echo "   Знайдено PV: $(kubectl get pv -o jsonpath='{.items[*].metadata.name}')"
fi
echo ""

# Створення Namespace
echo "5. Створення Namespace..."
kubectl apply -f namespace.yaml
echo "✅ Namespace portainer створено"
echo ""

# Створення ServiceAccount та RBAC
echo "6. Створення ServiceAccount та RBAC..."
kubectl apply -f serviceaccount.yaml
echo "✅ ServiceAccount та ClusterRole створено"
echo ""

# Створення PVC
echo "7. Створення PersistentVolumeClaim..."
kubectl apply -f persistentvolumeclaim.yaml
echo "✅ PVC створено"
echo "   Очікування зв'язування PVC з PV..."
sleep 3
kubectl get pvc -n portainer
echo ""

# Створення Deployment
echo "8. Створення Deployment..."
kubectl apply -f deployment.yaml
echo "✅ Deployment створено"
echo ""

# Створення Service
echo "9. Створення Service..."
kubectl apply -f service.yaml
echo "✅ Service створено"
echo ""

# Очікування готовності Pod
echo "10. Очікування готовності Pod..."
echo "   Це може зайняти кілька хвилин (завантаження образу)..."
kubectl wait --for=condition=ready pod -l app=portainer -n portainer --timeout=300s || {
    echo "⚠️  Pod не готовий за 5 хвилин, перевірте статус вручну"
}
echo ""

# Виведення інформації
echo "=== Deployment завершено ==="
echo ""
echo "📊 Статус ресурсів:"
kubectl get all -n portainer
echo ""
echo "🌐 Доступ до Portainer:"
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "   HTTP:  http://$NODE_IP:30900"
echo "   HTTPS: https://$NODE_IP:30943"
echo ""
echo "   Або через будь-який IP ноди кластера (master-node або work-node)"
echo ""
echo "📝 Корисні команди:"
echo "   kubectl get all -n portainer"
echo "   kubectl logs -f -l app=portainer -n portainer"
echo "   kubectl describe pod -l app=portainer -n portainer"
echo "   kubectl get pvc -n portainer"
echo ""
