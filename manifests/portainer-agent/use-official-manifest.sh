#!/bin/bash

# Скрипт для заміни власного Agent на офіційний маніфест
# Використання: ./use-official-manifest.sh

set -e

echo "=== Заміна на офіційний Portainer Agent маніфест ==="
echo ""

# 1. Видалення власного deployment
echo "1. Видалення власного Agent deployment..."
kubectl delete -f . --ignore-not-found=true
echo "✅ Власний deployment видалено"
echo ""

# 2. Використання офіційного маніфесту
echo "2. Застосування офіційного Portainer Agent маніфесту..."
kubectl apply -f https://downloads.portainer.io/ce2-33/portainer-agent-k8s-nodeport.yaml
echo "✅ Офіційний маніфест застосовано"
echo ""

# 3. Очікування готовності
echo "3. Очікування готовності Pod..."
sleep 10
# Офіційний маніфест створює ресурси в namespace portainer
kubectl wait --for=condition=ready pod -l app=portainer-agent -n portainer --timeout=120s 2>/dev/null || {
    echo "⚠️  Pod не готовий за 2 хвилини, перевірте статус вручну"
}
echo ""

# 4. Перевірка статусу
echo "4. Статус ресурсів:"
kubectl get all -n portainer | grep portainer-agent || kubectl get all -n portainer-agent | grep portainer-agent
echo ""

# 5. Отримання NodePort
echo "5. Адреса Portainer Agent:"
# Перевіряємо обидва namespaces
NODE_PORT=$(kubectl get svc portainer-agent -n portainer -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || \
            kubectl get svc portainer-agent -n portainer-agent -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || \
            echo "не знайдено")
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "   http://$NODE_IP:$NODE_PORT"
echo ""
echo "   Або через Service DNS:"
echo "   http://portainer-agent.portainer.svc.cluster.local:9001"
echo ""

echo "=== Готово ==="
echo ""
echo "📝 Використайте адресу вище для підключення в Portainer UI"
