#!/usr/bin/env bash
# Замінює upstream DNS у CoreDNS на 8.8.8.8 / 1.1.1.1, щоб уникнути timeout на 169.254.169.254 (OCI)
set -euo pipefail

echo "Patching CoreDNS ConfigMap to use 8.8.8.8 and 1.1.1.1 instead of /etc/resolv.conf..."

tmp=$(mktemp)
tmp_new="${tmp}.new"
trap 'rm -f "$tmp" "$tmp_new"' EXIT

kubectl get configmap coredns -n kube-system -o yaml >"$tmp"

sed 's|forward \. /etc/resolv.conf|forward . 8.8.8.8 1.1.1.1|' "$tmp" >"$tmp_new"

if cmp -s "$tmp" "$tmp_new"; then
  if grep -qE 'forward[[:space:]]+\.[[:space:]]+8\.8\.8\.8' "$tmp"; then
    echo "CoreDNS Corefile already uses public DNS forward; nothing to do."
  else
    echo "Expected line 'forward . /etc/resolv.conf' not found (or sed made no change). Edit Corefile manually." >&2
    exit 1
  fi
else
  if ! grep -qE 'forward[[:space:]]+\.[[:space:]]+8\.8\.8\.8' "$tmp_new"; then
    echo "Patched YAML does not contain expected forward . 8.8.8.8 — aborting apply." >&2
    exit 1
  fi
  kubectl apply -f "$tmp_new"
fi

live=$(kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}')
if ! echo "$live" | grep -qE 'forward[[:space:]]+\.[[:space:]]+8\.8\.8\.8'; then
  echo "Post-apply check failed: Corefile still missing forward . 8.8.8.8" >&2
  exit 1
fi

echo "Restarting CoreDNS deployment..."
kubectl rollout restart deployment coredns -n kube-system
echo "Done. Check logs: kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50"
