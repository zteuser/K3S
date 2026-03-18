#!/bin/bash
# Видалення orphaned HelmChart (traefik-crd, traefik) — залишки від k3s після міграції на k8s.
# Помилка: garbage-collector "unable to get REST mapping for helm.cattle.io/v1/HelmChart"
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "1. Застосування CRD helmcharts.helm.cattle.io..."
kubectl apply -f "$SCRIPT_DIR/helmchart-crd.yaml"

echo "2. Очікування реєстрації CRD (5s)..."
sleep 5

echo "3. Видалення orphaned HelmCharts у kube-system..."
kubectl delete helmchart traefik-crd -n kube-system --ignore-not-found
kubectl delete helmchart traefik -n kube-system --ignore-not-found

echo "4. Перевірка — залишились HelmCharts?"
kubectl get helmcharts.helm.cattle.io -A 2>/dev/null || true

echo "Готово. Помилки garbage-collector мають зникнути протягом 1–2 хвилин."
