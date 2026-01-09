#!/bin/bash

# Скрипт для перевірки логів Agent та спроб підключення від Portainer UI

echo "=== Перевірка логів Portainer Agent ==="
echo ""

# Перевірка останніх логів
echo "Останні 100 рядків логів Agent:"
echo "----------------------------------------"
kubectl logs -n portainer -l app=portainer-agent --tail=100
echo ""

# Перевірка помилок
echo "Пошук помилок у логах:"
echo "----------------------------------------"
kubectl logs -n portainer -l app=portainer-agent --tail=200 | grep -iE "(error|fail|refused|timeout|unreachable)" || echo "Помилок не знайдено"
echo ""

# Перевірка спроб підключення
echo "Спроби підключення (останні 10 хвилин):"
echo "----------------------------------------"
kubectl logs -n portainer -l app=portainer-agent --since=10m | grep -iE "(connect|request|client)" || echo "Спроб підключення не знайдено"
echo ""

# Статус Pod
echo "Статус Pod:"
echo "----------------------------------------"
kubectl get pods -n portainer -l app=portainer-agent -o wide
echo ""

# Статус Service
echo "Статус Service:"
echo "----------------------------------------"
kubectl get svc portainer-agent -n portainer
echo ""

echo "💡 Якщо в логах немає спроб підключення від Portainer UI, можливо:"
echo "   1. Portainer UI не може досягти IP 192.168.2.19"
echo "   2. Порт заблокований firewall"
echo "   3. Portainer UI працює на іншій машині і не має маршруту до 192.168.2.19"
