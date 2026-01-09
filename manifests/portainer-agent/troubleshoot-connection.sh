#!/bin/bash

# Скрипт для діагностики проблеми підключення Portainer UI до Agent

set -e

echo "=== Діагностика підключення Portainer UI до Agent ==="
echo ""

# 1. Перевірка статусу Agent Pod
echo "1. Статус Agent Pod:"
kubectl get pods -n portainer -l app=portainer-agent -o wide
echo ""

# 2. Перевірка Service
echo "2. Service конфігурація:"
kubectl get svc portainer-agent -n portainer -o yaml | grep -A 10 "spec:"
echo ""

# 3. Перевірка логів Agent (останні 50 рядків)
echo "3. Останні логи Agent (перевірка спроб підключення):"
kubectl logs -n portainer -l app=portainer-agent --tail=50 | tail -20
echo ""

# 4. Перевірка доступності через HTTPS
echo "4. Перевірка HTTPS доступності:"
NODE_PORT=$(kubectl get svc portainer-agent -n portainer -o jsonpath='{.spec.ports[0].nodePort}')
echo "   Тест на 192.168.2.19:$NODE_PORT..."
curl -k -s -o /dev/null -w "HTTP Code: %{http_code}\n" "https://192.168.2.19:$NODE_PORT/ping" || echo "   ❌ Помилка підключення"
echo ""

# 5. Перевірка, чи Portainer UI може досягти Agent
echo "5. Перевірка з IP Portainer UI (якщо Portainer працює на macmini7):"
echo "   Portainer UI має підключатися до: 192.168.2.19:$NODE_PORT"
echo ""

# 6. Перевірка firewall
echo "6. Перевірка firewall (якщо встановлено ufw):"
if command -v ufw &> /dev/null; then
    sudo ufw status | grep -E "(30778|$NODE_PORT)" || echo "   Порт не знайдено в правилах firewall"
else
    echo "   ufw не встановлено"
fi
echo ""

# 7. Перевірка, чи Portainer UI працює
echo "7. Перевірка Portainer UI:"
kubectl get pods -n portainer -l app=portainer 2>/dev/null && \
    echo "   ✅ Portainer Pod працює" || \
    echo "   ⚠️  Portainer Pod не знайдено в namespace portainer"
echo ""

echo "📝 Рекомендації:"
echo ""
echo "1. Переконайтеся, що в Portainer UI Environment address: 192.168.2.19:$NODE_PORT"
echo "2. Спробуйте видалити environment і створити новий через 'Add environment' → 'Kubernetes' → 'Agent'"
echo "3. Перевірте, чи Portainer UI може досягти IP 192.168.2.19 (перевірте мережеві налаштування)"
echo "4. Перевірте логи Portainer UI для деталей помилки підключення"
echo ""
echo "💡 Якщо Portainer UI працює на іншій машині, переконайтеся що:"
echo "   - IP 192.168.2.19 доступний з тієї машини"
echo "   - Порт $NODE_PORT не заблокований firewall"
echo "   - Використовується правильний протокол (HTTPS)"
