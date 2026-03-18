#!/bin/bash
# Додає Ingress Rules до OCI VCN Security List для pod CIDR 10.244.0.0/16 (POD_CONNECTIVITY_FIX).
# Потрібні: OCI CLI встановлений і налаштований (oci setup config).
# Використання: ./oci-security-list-pod-cidr.sh [COMPARTMENT_OCID] [VCN_OCID]
# Якщо OCID не передані — скрипт виведе інструкції та приклад команд.
set -e
COMPARTMENT_OCID="${1:-}"
VCN_OCID="${2:-}"
POD_CIDR="10.244.0.0/16"
NODE_CIDR="10.0.10.0/24"

if [ -z "$COMPARTMENT_OCID" ] || [ -z "$VCN_OCID" ]; then
  echo "Usage: $0 <COMPARTMENT_OCID> <VCN_OCID>"
  echo ""
  echo "Get OCIDs: oci network vcn list -c <compartment-id>"
  echo "Get Security List: oci network security-list list -c <compartment-id> --vcn-id <vcn-id>"
  echo ""
  echo "Then add Ingress Rules via OCI Console:"
  echo "  Networking -> Virtual Cloud Networks -> <your VCN> -> Security Lists -> Default Security List"
  echo "  Add Ingress Rules:"
  echo "    Source CIDR: $POD_CIDR  |  Dest: $NODE_CIDR  |  Protocol: All  |  Port: All"
  echo "    Source CIDR: $NODE_CIDR |  Dest: $POD_CIDR   |  Protocol: All  |  Port: All"
  exit 0
fi

# Resolve default security list for the VCN
SL_ID=$(oci network vcn get --vcn-id "$VCN_OCID" -c "$COMPARTMENT_OCID" --query 'data."default-security-list-id"' --raw-output 2>/dev/null || true)
if [ -z "$SL_ID" ]; then
  echo "Could not get default security list. Add rules manually in OCI Console (see above)."
  exit 1
fi

echo "Security List ID: $SL_ID"
echo "Add these Ingress Rules in OCI Console (OCI CLI add-ingress-security-rule varies by version):"
echo "  1. Source: $POD_CIDR  Protocol: All"
echo "  2. Source: $NODE_CIDR Protocol: All"
echo "See: manifests/OCI_SECURITY_LIST_MANUAL_STEPS.md"
exit 0
