# Hubble UI — траблшутінг pod-to-pod connectivity

## Проблема

- **macmini7 → OCI pods:** працює ✓
- **OCI (master-node) → macmini7 pods:** 100% packet loss ✗
- tcpdump: ICMP request виходить з master-node через wg1, reply не повертається

---

## Крок 1: Підготовка

### 1.1 Переконайся, що тестові поди запущені

```bash
KUBECONFIG=~/.kube/k8s-admin.conf kubectl get pods test-master test-macmini -o wide
```

Якщо немає — створи:

```bash
KUBECONFIG=~/.kube/k8s-admin.conf kubectl delete pod test-master test-macmini --ignore-not-found
KUBECONFIG=~/.kube/k8s-admin.conf kubectl run test-master --image=nicolaka/netshoot --restart=Never \
  --overrides='{"spec":{"nodeName":"master-node","tolerations":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}]}}' \
  -- sleep 3600
KUBECONFIG=~/.kube/k8s-admin.conf kubectl run test-macmini --image=nicolaka/netshoot --restart=Never \
  --overrides='{"spec":{"nodeName":"macmini7"}}' -- sleep 3600
KUBECONFIG=~/.kube/k8s-admin.conf kubectl get pods test-master test-macmini -o wide
```

### 1.2 Відкрий Hubble UI

```bash
KUBECONFIG=~/.kube/k8s-admin.conf kubectl port-forward -n kube-system svc/hubble-ui 12000:80
```

Відкрий http://localhost:12000

---

## Крок 2: Генерація трафіку

### 2.1 Пінг master → macmini7 (напрямок, що не працює)

```bash
MACMINI_IP=$(KUBECONFIG=~/.kube/k8s-admin.conf kubectl get pod test-macmini -o jsonpath='{.status.podIP}')
echo "Pinging $MACMINI_IP from test-master..."
KUBECONFIG=~/.kube/k8s-admin.conf kubectl exec test-master -- ping -c 10 $MACMINI_IP
```

### 2.2 Пінг macmini7 → master (напрямок, що працює)

```bash
MASTER_IP=$(KUBECONFIG=~/.kube/k8s-admin.conf kubectl get pod test-master -o jsonpath='{.status.podIP}')
echo "Pinging $MASTER_IP from test-macmini..."
KUBECONFIG=~/.kube/k8s-admin.conf kubectl exec test-macmini -- ping -c 5 $MASTER_IP
```

---

## Крок 3: Аналіз у Hubble UI

### 3.1 Namespace та фільтри

1. **Namespace:** вибери `default`
2. **Filter:** можна додати `IP: 10.244.2.121` або `IP: 10.244.0.x` для фокусу на тестових подах

### 3.2 Що перевірити

| Напрямок | Очікування | Що шукати |
|----------|------------|------------|
| **test-master → test-macmini** | Request виходить, reply не повертається | Flows з source=test-master, dest=test-macmini. Verdict: forwarded (request) vs відсутність reply |
| **test-macmini → test-master** | Обидва напрямки | Flows з source=test-macmini, dest=test-master. Verdict: forwarded для обох |

### 3.3 Інтерпретація

- **Якщо бачиш тільки request (test-master → test-macmini), без reply:** проблема на зворотному шляху (macmini7 → Vern625 → master-node) або reply не проходить через Cilium datapath
- **Якщо бачиш DROP:** перевір причину drop у Hubble (policy, no backend тощо)
- **Якщо flows взагалі немає:** трафік не проходить через Cilium (маршрутизація на рівні мережі)

### 3.4 Hubble CLI (опційно, потребує hubble CLI локально)

```bash
# Port-forward до relay
KUBECONFIG=~/.kube/k8s-admin.conf kubectl port-forward -n kube-system svc/hubble-relay 4245:4245 &

# Локально (якщо встановлено: brew install hubble)
hubble observe --server localhost:4245 --namespace default --from-pod default/test-master --to-ip 10.244.2.121 --protocol icmp -n 20
hubble observe --server localhost:4245 --verdict DROPPED -n 10
```

---

## Крок 4: Діагностика зворотного шляху

Якщо Hubble показує request, але не reply:

1. **tcpdump на macmini7** — чи приходять request і чи виходять reply:
   ```bash
   ssh malex@192.168.2.19 'sudo timeout 15 tcpdump -i any -n "icmp and (host 10.244.0.164 or host 10.244.2.121)" -c 15'
   ```

2. **tcpdump на master-node wg1** — чи приходять reply:
   ```bash
   ssh malex@10.0.10.10 'sudo timeout 15 tcpdump -i wg1 -n "icmp and host 10.244.0.164" -c 10'
   ```

3. **Маршрут з macmini7 до master pod:**
   ```bash
   ssh malex@192.168.2.19 'ip route get 10.244.0.164'
   ```

---

## Швидкий чеклист

- [ ] test-master, test-macmini Running
- [ ] Hubble UI відкрито, namespace=default
- [ ] Запустити ping master→macmini7
- [ ] Перевірити flows у Hubble: request є? reply є?
- [ ] Запустити ping macmini7→master
- [ ] Порівняти flows обох напрямків
