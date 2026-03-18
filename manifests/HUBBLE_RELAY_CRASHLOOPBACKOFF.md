# Hubble Relay — CrashLoopBackOff (DNS timeout)

## Симптоми

- Pod `hubble-relay-*` у стані **CrashLoopBackOff**.
- Логи: `Failed to create peer notify client ... dns: A record lookup error: lookup hubble-peer.kube-system.svc.cluster.local. on 10.96.0.10:53: read udp ... i/o timeout`.
- Startup/Liveness probe: `NOT_SERVING` → контейнер убивається (exit 137).

## Root cause

**Cross-node pod connectivity:** hubble-relay працює на **master-node** (pod 10.244.0.x). Він звертається до CoreDNS (10.96.0.10:53), який відповідає з подів на **work-node** (10.244.1.x) або **beelinkeqr5** (10.244.4.x). Трафік 10.244.0.x → 10.244.1.x (або 10.244.4.x) не проходить — таймаут DNS. Типова причина: **OCI VCN Security List** не дозволяє pod CIDR 10.244.0.0/16 між нодами.

## Рішення

### Варіант A: Обхід — перенести hubble-relay на work-node (застосовано в values)

У `manifests/cilium/values-k8s.yaml` та `values-k3s.yaml` додано:

```yaml
hubble:
  relay:
    nodeSelector:
      kubernetes.io/hostname: work-node
```

Це не вирішує проблему повністю: навіть на work-node DNS-запити до `kube-dns` (10.96.0.10) можуть йти на CoreDNS на **beelinkeqr5** (10.244.4.x), і трафік 10.244.1.x → 10.244.4.x так само блокується. Тому **обовʼязково** потрібен варіант B.

**Застосування (після виконання варіанту B):**

```bash
cd /path/to/k3s
helm upgrade cilium cilium/cilium -n kube-system -f manifests/cilium/values-k8s.yaml
kubectl rollout status deployment/hubble-relay -n kube-system
kubectl get pods -n kube-system -l app.kubernetes.io/name=hubble-relay
```

### Варіант B: Повне — виправити pod connectivity (обовʼязково)

Якщо потрібна повна взаємодія pod-ів між усіма нодами (не лише hubble-relay):

1. **OCI Security List (рекомендовано):** додати Ingress для 10.244.0.0/16 — див. `manifests/POD_CONNECTIVITY_FIX_10_244.md` (варіант A).
2. **Або Cilium VXLAN:** увімкнути тунель, щоб pod-трафік йшов під node IP:
   ```bash
   cd /path/to/k3s
   helm upgrade cilium cilium/cilium -n kube-system \
     -f manifests/cilium/values-k8s.yaml \
     -f manifests/cilium/values-k8s-vxlan.yaml
   ```

Після застосування варіанту B hubble-relay перейде в стан **Running** (поточний nodeSelector на work-node залишається, можна прибрати після фіксу мережі).
