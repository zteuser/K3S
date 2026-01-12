#!/bin/bash

# Скрипт для перевірки статусу Grafana
# Використання: ./CHECK_STATUS.sh

echo "=== Перевірка статусу Grafana ==="
echo ""

echo "1. Статус PVC:"
kubectl get pvc grafana-data -n monitoring
echo ""

echo "2. Статус PV:"
kubectl get pv pv-grafana-data
echo ""

echo "3. Статус Deployment:"
kubectl get deployment grafana -n monitoring
echo ""

echo "4. Статус Pods:"
kubectl get pods -n monitoring -l app=grafana
echo ""

echo "5. Останні події:"
kubectl get events -n monitoring --field-selector involvedObject.name=grafana --sort-by='.lastTimestamp' | tail -10
echo ""

echo "6. Логи Grafana (останні 20 рядків):"
POD_NAME=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD_NAME" ]; then
    kubectl logs -n monitoring $POD_NAME --tail=20
else
    echo "   Pod не знайдено"
fi
echo ""

echo "7. Логи InitContainer (якщо є):"
if [ -n "$POD_NAME" ]; then
    kubectl logs -n monitoring $POD_NAME -c fix-grafana-permissions --tail=20 2>/dev/null || echo "   InitContainer не знайдено або не запускався"
fi
echo ""

echo "=== Готово ==="
