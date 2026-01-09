#!/bin/bash

# Скрипт для перевірки HTTPS доступності Portainer Agent

set -e

echo "=== Перевірка HTTPS доступності Portainer Agent ==="
echo ""

# Отримуємо NodePort
NODE_PORT=$(kubectl get svc portainer-agent -n portainer -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "не знайдено")

if [ "$NODE_PORT" == "не знайдено" ]; then
    echo "❌ Помилка: Не вдалося знайти NodePort для portainer-agent"
    exit 1
fi

echo "📊 Поточна конфігурація:"
echo "   NodePort: $NODE_PORT"
echo ""

# Отримуємо IP адреси всіх нод
echo "🌐 Перевірка доступності Agent на всіх нодах:"
echo ""

NODES=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')

for NODE_IP in $NODES; do
    echo "   Перевірка $NODE_IP:$NODE_PORT..."
    
    # Перевірка HTTPS доступності
    RESPONSE=$(curl -k -s -w "\n%{http_code}" --max-time 5 "https://$NODE_IP:$NODE_PORT/ping" 2>/dev/null || echo -e "\n000")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "400" ]; then
        echo "   ✅ Agent доступний на $NODE_IP:$NODE_PORT (HTTPS)"
        if [ -n "$BODY" ]; then
            echo "      Відповідь: $BODY"
        fi
    elif [ "$HTTP_CODE" == "000" ]; then
        echo "   ❌ Agent недоступний на $NODE_IP:$NODE_PORT (timeout або connection refused)"
    else
        echo "   ⚠️  Agent відповідає з кодом $HTTP_CODE на $NODE_IP:$NODE_PORT"
        if [ -n "$BODY" ]; then
            echo "      Відповідь: $BODY"
        fi
    fi
    echo ""
done

echo "📝 Інструкції для Portainer UI:"
echo ""
echo "1. Відкрийте Portainer UI"
echo "2. Перейдіть до Environment details для 'k3s-cluster-vrn625'"
echo "3. Переконайтеся, що Environment address: 192.168.2.19:$NODE_PORT"
echo "4. Якщо є опція 'TLS' або 'Skip TLS verification', увімкніть її"
echo "5. Натисніть 'Update environment'"
echo ""
echo "💡 Примітка: Agent працює на HTTPS, тому Portainer має підключатися через HTTPS."
echo "   Якщо Portainer намагається підключитися через HTTP, це викличе помилку."
