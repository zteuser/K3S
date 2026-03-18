#!/usr/bin/env bash
# Відновлення сервісів у кластері k3s + Cilium згідно з manifests/SERVICES_RECOVERY_PLAN.md
# Запуск з кореня репо k3s: ./manifests/scripts/restore-services.sh [опції]

set -e
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKUP_DIR="${REPO_ROOT}/backup-pre-cilium"
MANIFESTS_DIR="${REPO_ROOT}/manifests"

cd "$REPO_ROOT"

usage() {
  echo "Usage: $0 [--skip-connectivity-check] [--skip-backup-pvc] [--dry-run]"
  echo "  --skip-connectivity-check  не перевіряти pod connectivity (крок 0)"
  echo "  --skip-backup-pvc          не застосовувати PVC з бекапу (крок 2)"
  echo "  --dry-run                  лише показати команди, не виконувати"
  exit 0
}

SKIP_CONNECTIVITY=
SKIP_BACKUP_PVC=
DRY_RUN=
for arg in "$@"; do
  case "$arg" in
    --skip-connectivity-check) SKIP_CONNECTIVITY=1 ;;
    --skip-backup-pvc)         SKIP_BACKUP_PVC=1 ;;
    --dry-run)                 DRY_RUN=1 ;;
    -h|--help)                 usage ;;
  esac
done

run() {
  if [[ -n "$DRY_RUN" ]]; then
    echo "[DRY-RUN] $*"
  else
    echo ">>> $*"
    "$@"
  fi
}

echo "=== Відновлення сервісів (репо: $REPO_ROOT) ==="

# --- Крок 0: перевірка pod connectivity ---
if [[ -z "$SKIP_CONNECTIVITY" ]]; then
  echo ""
  echo "--- Крок 0: перевірка pod connectivity (10.244.x.x cross-node) ---"
  if [[ -z "$DRY_RUN" ]]; then
    run kubectl run test-dns --image=busybox:1.36 --restart=Never -- nslookup kube-dns.kube-system.svc.cluster.local 2>/dev/null || true
    sleep 3
    if kubectl logs test-dns 2>/dev/null | head -5; then
      echo "DNS test pod: перевірте вивід вище. Якщо timeout — спочатку вирішіть POD_CONNECTIVITY_FIX_10_244.md"
    fi
    kubectl delete pod test-dns --ignore-not-found 2>/dev/null || true
  else
    echo "[DRY-RUN] kubectl run test-dns ... ; kubectl logs test-dns ; kubectl delete pod test-dns"
  fi
else
  echo "--- Крок 0 пропущено (--skip-connectivity-check) ---"
fi

# --- Крок 1: ConfigMaps, Secrets ---
echo ""
echo "--- Крок 1: ConfigMaps, Secrets ---"
if [[ ! -f "$BACKUP_DIR/configmaps.yaml" ]]; then
  echo "Попередження: $BACKUP_DIR/configmaps.yaml не знайдено, пропускаю."
else
  run kubectl apply -f "$BACKUP_DIR/configmaps.yaml"
fi
if [[ ! -f "$BACKUP_DIR/secrets.yaml" ]]; then
  echo "Попередження: $BACKUP_DIR/secrets.yaml не знайдено, пропускаю."
else
  run kubectl apply -f "$BACKUP_DIR/secrets.yaml"
fi

# --- Крок 2: PVC з бекапу ---
echo ""
echo "--- Крок 2: PVC (з бекапу) ---"
if [[ -n "$SKIP_BACKUP_PVC" ]]; then
  echo "Пропущено (--skip-backup-pvc)."
elif [[ ! -f "$BACKUP_DIR/pvc.yaml" ]]; then
  echo "Попередження: $BACKUP_DIR/pvc.yaml не знайдено. Для Prometheus/Grafana/Loki використовуються PVC з manifests/monitoring/."
else
  run kubectl apply -f "$BACKUP_DIR/pvc.yaml"
fi

# --- Крок 3: Monitoring (Kustomize) ---
echo ""
echo "--- Крок 3: Monitoring (Prometheus, Grafana, Loki, Alloy, node-exporter, snmp-exporter, kube-state-metrics) ---"
run kubectl apply -k "$MANIFESTS_DIR/monitoring/"

# --- Крок 4: Portainer + agent ---
echo ""
echo "--- Крок 4: Portainer ---"
run kubectl apply -f "$MANIFESTS_DIR/portainer/namespace.yaml"
run kubectl apply -k "$MANIFESTS_DIR/portainer/"
if [[ -d "$MANIFESTS_DIR/portainer-agent" ]]; then
  for f in "$MANIFESTS_DIR/portainer-agent"/*.yaml; do
    [[ -f "$f" ]] && run kubectl apply -f "$f"
  done
fi

# --- Крок 5: Ingress ---
echo ""
echo "--- Крок 5: Ingress ---"
if [[ ! -f "$BACKUP_DIR/ingress.yaml" ]]; then
  echo "Попередження: $BACKUP_DIR/ingress.yaml не знайдено, пропускаю."
else
  run kubectl apply -f "$BACKUP_DIR/ingress.yaml"
fi

# --- Крок 6: HelmChartConfig (Traefik) ---
echo ""
echo "--- Крок 6: HelmChartConfig (Traefik) ---"
if [[ ! -f "$BACKUP_DIR/helmchartconfig.yaml" ]]; then
  echo "Попередження: $BACKUP_DIR/helmchartconfig.yaml не знайдено, пропускаю."
else
  run kubectl apply -f "$BACKUP_DIR/helmchartconfig.yaml"
fi

echo ""
echo "=== Готово. Перевірка: kubectl get pods -A ==="
if [[ -z "$DRY_RUN" ]]; then
  run kubectl get pods -A
fi
