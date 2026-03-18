# macmini7 — join та перевірка Cilium

## Статус (2026-03-07)

- [x] kubeadm join виконано
- [x] failSwapOn: false додано в kubelet config (swap увімкнено на macmini7)
- [ ] Cilium pod на macmini7 — **падає** з "unable to determine direct routing device"
- [ ] Потрібно застосувати CiliumNodeConfig та перезапустити Cilium

## Що зроблено

1. **Swap:** kubelet падав з "running with swap on is not supported". Виправлено: `sudo sed -i "/^kind: KubeletConfiguration/a failSwapOn: false" /var/lib/kubelet/config.yaml` + restart kubelet.

2. **Cilium values:** оновлено `devices: "enp0s6,enp3s0f0,enp1s0"` для підтримки всіх нод.

3. **Cilium на macmini7:** падає бо `direct-routing-device: "enp0s6"` (глобально) — на macmini7 інтерфейс `enp3s0f0`. Рішення: застосувати CiliumNodeConfig.

## Команди (виконувати на master-node з KUBECONFIG)

```bash
# 1. Застосувати CiliumNodeConfig (macmini7=enp3s0f0)
kubectl apply -f manifests/cilium/cilium-node-configs.yaml

# 2. Перезапустити Cilium на macmini7 щоб підхопити config
kubectl delete pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=macmini7

# 3. Перевірити
kubectl get nodes -o wide
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
# Дочекатись cilium-* на macmini7 Running

# 4. (опційно) Оновити Cilium Helm з devices для всіх нод
helm upgrade cilium cilium/cilium -n kube-system -f manifests/cilium/values-k8s.yaml
```

## Перевірка pod-to-pod connectivity

```bash
# Pod на macmini7 → pod на master-node
kubectl run test-macmini --image=nicolaka/netshoot --restart=Never --overrides='{"spec":{"nodeName":"macmini7"}}' -- sleep 3600
kubectl run test-master --image=nicolaka/netshoot --restart=Never --overrides='{"spec":{"nodeName":"master-node"}}' -- sleep 3600

# Дочекатись Running
kubectl get pods -o wide

# З macmini7 pod пінгувати master pod
MACMINI_POD=$(kubectl get pod test-macmini -o jsonpath='{.status.podIP}')
kubectl exec test-master -- ping -c 3 $MACMINI_POD

# Або з test-macmini пінгувати test-master
MASTER_POD=$(kubectl get pod test-master -o jsonpath='{.status.podIP}')
kubectl exec test-macmini -- ping -c 3 $MASTER_POD

# Прибрати тестові поди
kubectl delete pod test-macmini test-master
```

## Cilium status на macmini7

```bash
kubectl -n kube-system exec -it ds/cilium -c cilium-agent -- cilium-dbg status
# або для конкретного поду на macmini7:
kubectl -n kube-system exec -it $(kubectl get pod -n kube-system -l k8s-app=cilium -l kubernetes.io/hostname=macmini7 -o name) -c cilium-agent -- cilium-dbg status
```
