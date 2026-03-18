#!/bin/bash
# Замінює upstream DNS у CoreDNS на 8.8.8.8 / 1.1.1.1, щоб уникнути timeout на 169.254.169.254 (OCI)
set -e
echo "Patching CoreDNS ConfigMap to use 8.8.8.8 and 1.1.1.1 instead of /etc/resolv.conf..."
kubectl get configmap coredns -n kube-system -o yaml | \
  sed 's|forward \. /etc/resolv.conf|forward . 8.8.8.8 1.1.1.1|' | \
  kubectl apply -f -
echo "Restarting CoreDNS deployment..."
kubectl rollout restart deployment coredns -n kube-system
echo "Done. Check logs: kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50"
