#!/usr/bin/env bash
# Відновлення лише Portainer у кластері k8s (після міграції або коли сервіси перестали працювати після налаштування ingress).
# Запуск з кореня репо k3s: ./manifests/scripts/restore-portainer.sh [--no-agent] [--dry-run]

set -e
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFESTS_DIR="${REPO_ROOT}/manifests"
PORTAINER_DIR="${MANIFESTS_DIR}/portainer"
AGENT_DIR="${MANIFESTS_DIR}/portainer-agent"

cd "$REPO_ROOT"

NO_AGENT=
DRY_RUN=
for arg in "$@"; do
  case "$arg" in
    --no-agent)  NO_AGENT=1 ;;
    --dry-run)   DRY_RUN=1 ;;
    -h|--help)   echo "Usage: $0 [--no-agent] [--dry-run]"; exit 0 ;;
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

echo "=== Відновлення Portainer (репо: $REPO_ROOT) ==="

# 1. Portainer: namespace, SA, RBAC, PVC, Deployment, Service, Ingress (ingressClassName: cilium), NetworkPolicy
echo ""
echo "--- 1. Portainer (kustomize) ---"
run kubectl apply -k "$PORTAINER_DIR/"

# 2. Portainer Agent (опційно): спочатку namespace, потім решта (інакше deployment падає з "namespace not found")
if [[ -z "$NO_AGENT" ]] && [[ -d "$AGENT_DIR" ]]; then
  echo ""
  echo "--- 2. Portainer Agent ---"
  if [[ -f "$AGENT_DIR/namespace.yaml" ]]; then
    run kubectl apply -f "$AGENT_DIR/namespace.yaml"
  fi
  for f in "$AGENT_DIR"/*.yaml; do
    [[ -f "$f" ]] && [[ "$(basename "$f")" != "namespace.yaml" ]] && run kubectl apply -f "$f"
  done
else
  echo ""
  echo "--- 2. Portainer Agent пропущено (--no-agent або каталог відсутній) ---"
fi

echo ""
echo "--- Перевірка ---"
if [[ -z "$DRY_RUN" ]]; then
  kubectl get pods,svc,ingress -n portainer
  echo ""
  echo "Доступ:"
  echo "  - Ingress: http://portainer.lan (потрібен Cilium Ingress + DNS/hosts)"
  echo "  - NodePort: http://<node-IP>:30900 або https://<node-IP>:30943"
  echo "Якщо под Pending: kubectl describe pvc -n portainer portainer-data (перевірити PV/StorageClass)"
  echo "Якщо local unreachable: див. manifests/portainer/RESTORE.md"
fi
