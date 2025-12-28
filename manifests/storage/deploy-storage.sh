#!/bin/bash

# Скрипт для deployment OCFS2 shared storage в k3s cluster
# Використання: ./deploy-storage.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Deployment OCFS2 Shared Storage для k3s Cluster ==="
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

# Створення StorageClass
echo "3. Створення StorageClass..."
kubectl apply -f storageclass-ocfs2.yaml
echo "✅ StorageClass створено"
kubectl get storageclass ocfs2-shared
echo ""

# Створення PersistentVolumes
echo "4. Створення PersistentVolumes..."
echo "   Створення PV для sharedata1..."
kubectl apply -f persistentvolume-sharedata1.yaml
echo "   Створення PV для sharedata2..."
kubectl apply -f persistentvolume-sharedata2.yaml
echo "✅ PersistentVolumes створено"
kubectl get pv
echo ""

# Перевірка статусу PV
echo "5. Перевірка статусу PersistentVolumes..."
PV_STATUS=$(kubectl get pv -o jsonpath='{.items[*].status.phase}')
echo "   Статус PV: $PV_STATUS"
echo ""

# Опціонально: створення прикладів
read -p "6. Створити приклади PVC та Deployment? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "   Створення прикладів PVC..."
    kubectl apply -f persistentvolumeclaim-example.yaml
    echo "✅ Приклади PVC створено"
    kubectl get pvc
    echo ""
    
    read -p "   Створити приклад Deployment? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Створення прикладу Deployment..."
        kubectl apply -f deployment-example.yaml
        echo "✅ Приклад Deployment створено"
        echo ""
        echo "   Очікування готовності подів..."
        sleep 5
        kubectl get pods -l app=example-deployment
    fi
fi

echo ""
echo "=== Deployment завершено ==="
echo ""
echo "Корисні команди для перевірки:"
echo "  kubectl get storageclass"
echo "  kubectl get pv"
echo "  kubectl get pvc"
echo "  kubectl get pods -o wide"
echo ""
echo "Для перевірки OCFS2 на нодах:"
echo "  ssh master-node 'o2cb cluster-status && o2cb list-nodes ocfscluster && mount | grep ocfs2'"
echo "  ssh work-node 'o2cb cluster-status && o2cb list-nodes ocfscluster && mount | grep ocfs2'"

