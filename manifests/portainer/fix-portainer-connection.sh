#!/bin/bash

# Скрипт для отримання правильного Kubernetes API URL для Portainer

echo "=== Знаходження Kubernetes API URL ==="
echo ""

# Отримуємо IP адресу Kubernetes API сервісу
K8S_API_IP=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}')
K8S_API_PORT=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.ports[0].port}')

echo "Kubernetes API Service IP: $K8S_API_IP"
echo "Kubernetes API Service Port: $K8S_API_PORT"
echo ""
echo "✅ Environment URL для Portainer:"
echo "   https://$K8S_API_IP:$K8S_API_PORT"
echo ""
echo "Або з skip TLS verification можна використати:"
echo "   https://kubernetes.default.svc.cluster.local:443"
echo ""
echo "📝 Інструкції:"
echo "1. Відкрийте Portainer UI"
echo "2. Перейдіть до Environment details для 'local'"
echo "3. Оновіть 'Environment URL' на: https://$K8S_API_IP:$K8S_API_PORT"
echo "4. Увімкніть 'Skip TLS verification'"
echo "5. Натисніть 'Update environment'"
echo ""
