#!/bin/bash
# Діагностика доступу до Grafana (NodePort 30000 / ERR_CONNECTION_REFUSED)
# Запуск: з машини з kubectl; частину перевірок потрібно виконати на ноді 10.0.10.10

set -e
NAMESPACE="${NAMESPACE:-monitoring}"
NODE_IP="${NODE_IP:-10.0.10.10}"

echo "=== Діагностика доступу до Grafana (UI не відкривається) ==="
echo ""

echo "1. Service grafana (NodePort 30000):"
kubectl get svc -n "$NAMESPACE" grafana -o wide 2>/dev/null || { echo "   Service grafana не знайдено"; exit 1; }
echo ""

echo "2. Endpoints (мають бути не порожні):"
kubectl get endpoints -n "$NAMESPACE" grafana 2>/dev/null
EP_COUNT=$(kubectl get endpoints -n "$NAMESPACE" grafana -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
if [ "$EP_COUNT" -eq 0 ]; then
    echo "   УВАГА: Endpoints порожні — под не підходить під selector Service."
fi
echo ""

echo "3. Pod Grafana (Running):"
kubectl get pods -n "$NAMESPACE" -l app=grafana -o wide
echo ""

echo "4. Доступ зсередини кластера (curl до Service:3000):"
CODE=$(kubectl run curl-grafana-check --rm --restart=Never -n "$NAMESPACE" --image=curlimages/curl -- curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://grafana."$NAMESPACE".svc.cluster.local:3000/api/health 2>/dev/null) || CODE=""
if [ -n "$CODE" ] && [ "$CODE" = "200" ]; then
    echo "   HTTP code: $CODE — Grafana по Service доступна."
else
    echo "   Не вдалося отримати 200 (код: ${CODE:-error})."
fi
echo ""

echo "5. Що зробити на ноді $NODE_IP:"
echo "   - Перевірити, чи слухає порт 30000:"
echo "     ss -tlnp | grep 30000"
echo "   - Локально на ноді:"
echo "     curl -s -w '%{http_code}' http://127.0.0.1:30000/api/health"
echo "   - Якщо localhost:30000 працює, а з браузера 10.0.10.10:30000 — ні: відкрити фаєрвол для 30000/tcp."
echo ""

echo "6. Альтернатива — через Ingress (Traefik):"
echo "   Додайте в /etc/hosts (або C:\\Windows\\System32\\drivers\\etc\\hosts):"
echo "   $NODE_IP  monitoring.lan"
echo "   Відкрийте в браузері: http://monitoring.lan"
echo ""

echo "Детальні кроки: див. FIX_GRAFANA_UI.md"
echo "=== Готово ==="
