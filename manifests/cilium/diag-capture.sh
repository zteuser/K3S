#!/bin/bash
# Capture network state for Cilium connectivity diagnosis
# Run: BEFORE Cilium (baseline) and AFTER Cilium (when connectivity lost)
# Usage: sudo ./diag-capture.sh [before|after]

set -e
DIR="${1:-after}"
OUT="/tmp/cilium-diag/${DIR}"
mkdir -p "$OUT"

echo "=== Cilium connectivity diag: $DIR @ $(date -Iseconds) ==="

# iptables (legacy or nft)
( iptables-save 2>/dev/null || iptables-legacy-save 2>/dev/null ) > "$OUT/iptables.txt"
( iptables-save -t nat 2>/dev/null || iptables-legacy-save -t nat 2>/dev/null ) > "$OUT/iptables-nat.txt" 2>/dev/null || true

# routing
ip rule > "$OUT/ip-rule.txt"
ip route > "$OUT/ip-route.txt"
ip addr > "$OUT/ip-addr.txt"
ip link > "$OUT/ip-link.txt"

# interfaces
ip -d link show > "$OUT/ip-link-detail.txt" 2>/dev/null || true

# tc (traffic control) on main interface
for dev in enp0s6 enp3s0f0 enp1s0 eth0; do
  if ip link show "$dev" &>/dev/null; then
    tc filter show dev "$dev" ingress 2>/dev/null > "$OUT/tc-${dev}-ingress.txt" || true
    tc filter show dev "$dev" egress 2>/dev/null > "$OUT/tc-${dev}-egress.txt" || true
  fi
done

echo "Saved to $OUT"
ls -la "$OUT"
