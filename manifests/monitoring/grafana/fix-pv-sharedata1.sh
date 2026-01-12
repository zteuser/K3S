#!/bin/bash

# Скрипт для звільнення pv-sharedata1 та використання його для Grafana
# Використання: ./fix-pv-sharedata1.sh

set -e

echo "=== Звільнення pv-sharedata1 для Grafana ==="
echo ""

# 1. Перевірка поточного стану
echo "1. Поточний стан PV:"
kubectl get pv pv-sharedata1
echo ""

# 2. Звільнення PV від старого claimRef
echo "2. Звільнення PV від claimRef..."
kubectl patch pv pv-sharedata1 -p '{"spec":{"claimRef":null}}'
echo "✅ PV звільнено"
echo ""

# 3. Перевірка статусу
echo "3. Перевірка статусу PV:"
kubectl get pv pv-sharedata1
echo ""

# 4. Очікування зміни статусу
echo "4. Очікування зміни статусу на Available..."
sleep 3
STATUS=$(kubectl get pv pv-sharedata1 -o jsonpath='{.status.phase}')
if [ "$STATUS" = "Available" ]; then
    echo "✅ PV має статус Available"
else
    echo "⚠️  PV має статус: $STATUS"
    echo "   Спробуйте вручну: kubectl patch pv pv-sharedata1 -p '{\"spec\":{\"claimRef\":null}}'"
fi
echo ""

# 5. Інструкції для оновлення PVC
echo "5. Наступні кроки:"
echo "   1. Відкрийте grafana/pvc.yaml"
echo "   2. Розкоментуйте рядок: volumeName: pv-sharedata1"
echo "   3. Оновіть PVC через Portainer або: kubectl apply -f grafana/pvc.yaml"
echo ""

echo "=== Готово ==="
