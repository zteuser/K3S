#!/bin/bash

# Скрипт для deployment Portainer Agent в k3s cluster
# Використання: ./deploy-agent.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Deployment Portainer Agent для k3s Cluster ==="
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

# Створення Namespace
echo "2. Створення Namespace..."
kubectl apply -f namespace.yaml
echo "✅ Namespace portainer-agent створено"
echo ""

# Створення ServiceAccount та RBAC
echo "3. Створення ServiceAccount та RBAC..."
kubectl apply -f serviceaccount.yaml
echo "✅ ServiceAccount та ClusterRole створено"
echo ""

# Створення Deployment
echo "4. Створення Deployment..."
kubectl apply -f deployment.yaml
echo "✅ Deployment створено"
echo ""

# Створення Service
echo "5. Створення Service..."
kubectl apply -f service.yaml
echo "✅ Service створено"
echo ""

# Очікування готовності Pod
echo "6. Очікування готовності Pod..."
echo "   Це може зайняти кілька хвилин (завантаження образу)..."
kubectl wait --for=condition=ready pod -l app=portainer-agent -n portainer-agent --timeout=300s || {
    echo "⚠️  Pod не готовий за 5 хвилин, перевірте статус вручну"
}
echo ""

# Виведення інформації
echo "=== Deployment завершено ==="
echo ""
echo "📊 Статус ресурсів:"
kubectl get all -n portainer-agent
echo ""
echo "🌐 Адреса Portainer Agent:"
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "   http://$NODE_IP:30901"
echo ""
echo "   Або через Service DNS:"
echo "   http://portainer-agent.portainer-agent.svc.cluster.local:9001"
echo ""
echo "📝 Інструкції для підключення в Portainer UI:"
echo "1. Відкрийте Portainer UI"
echo "2. Перейдіть до 'Add environment' → 'Kubernetes' → 'Agent'"
echo "3. Введіть:"
echo "   - Name: k3s-cluster (або будь-яка назва)"
echo "   - Environment address: $NODE_IP:30901"
echo "   Або: portainer-agent.portainer-agent.svc.cluster.local:9001"
echo "4. Натисніть 'Connect'"
echo ""
