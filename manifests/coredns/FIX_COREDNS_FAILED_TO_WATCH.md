# CoreDNS: «Failed to watch» / «watch ended with error»

## Симптоми

У логах CoreDNS:

```
[INFO] plugin/ready: Plugins not ready: "kubernetes"
[INFO] plugin/kubernetes: Warning: watch ended with error
[ERROR] plugin/kubernetes: Failed to watch
```

Под може бути в статусі Running, але плагін `kubernetes` не синхронізується з API — DNS по сервісах/подах може не працювати або працювати нестабільно.

---

## Можливі причини

1. **RBAC** — у service account CoreDNS немає прав на `list`/`watch` для EndpointSlices (та інших ресурсів).
2. **Доступ до API** — под CoreDNS не може стабільно досягти Kubernetes API (10.43.0.1:443): мережа, firewall, таймаути.
3. **Навантаження API / таймаути** — API сервер перевантажений або watch-з’єднання обриваються.

---

## Крок 1: Перевірити RBAC для CoreDNS

Переконайтесь, що service account `coredns` у `kube-system` має права на endpoints, services, pods, namespaces та **endpointslices** (API group `discovery.k8s.io`):

```bash
# Які ClusterRole прив’язані до system:serviceaccount:kube-system:coredns
kubectl get clusterrolebinding -o wide | grep coredns

# Деталі ролі (у k3s зазвичай system:coredns)
kubectl describe clusterrole system:coredns
```

Перевірте, чи в ClusterRole є правила для:

- `""` (core): `endpoints`, `services`, `pods`, `namespaces`
- `discovery.k8s.io`: `endpointslices` (list, watch)

Якщо правил для `endpointslices` немає — додайте їх. Приклад доповнення (якщо керуєте RBAC вручну):

```yaml
# fragment для ClusterRole
- apiGroups: ["discovery.k8s.io"]
  resources: ["endpointslices"]
  verbs: ["list", "watch"]
```

У k3s цей ClusterRole зазвичай вже є; якщо після оновлення k3s/CoreDNS з’явились помилки watch — перевірте версію та [release notes](https://github.com/k3s-io/k3s/releases).

---

## Крок 2: Перевірити доступ до API з мережі подів

Образ CoreDNS у k3s не містить `wget`/`curl`, тому перевірку доступу до API краще робити з тимчасового debug-пода:

```bash
# Запустити под з curl (на ноді, де біжить CoreDNS, або на master-node)
kubectl run debug-api --rm -it --restart=Never --image=curlimages/curl -- \
  curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 3 https://10.43.0.1:443/version
```

Очікується: HTTP код (наприклад 403 — API відповів, але для анонімного запиту заборонено; це нормально). Таймаут або «connection refused» означають проблему мережі між подом і API (див. **README.md** про «no route to host» та node affinity для CoreDNS).

---

## Крок 3: Мережа та node affinity

Якщо CoreDNS запланований на ноду, з якої **немає маршруту до 10.43.0.1** (наприклад work-node), watch буде падати. Застосуйте node affinity, щоб CoreDNS біг лише на нодах з доступом до API:

```bash
# з каталогу manifests/coredns
sudo ./apply-coredns-node-affinity.sh
# або
sudo kubectl patch deployment coredns -n kube-system --patch-file=coredns-node-affinity-patch.yaml
```

Деталі — у **README.md** (розділ «No route to host»).

---

## Крок 4: 502 Bad Gateway при «kubectl logs» (kubelet недоступний)

Помилка на кшталт:

```text
Get "https://192.168.2.19:10250/containerLogs/...": proxy error from 127.0.0.1:6443 while dialing 192.168.2.19:10250, code 502: 502 Bad Gateway
```

означає: **API server не може досягти kubelet на ноді** (тут — 192.168.2.19:10250). Це не помилка CoreDNS, а проблема зв’язку control plane ↔ нода. Можливі причини:

- Firewall блокує 10250 між control plane і нодою
- Нода 192.168.2.19 нестабільна або kubelet не слухає на 10250
- Маршрутизація між control plane і 192.168.2.19

**Що зробити:**

1. Перевірити стан ноди: `kubectl get nodes -o wide` — чи Ready нода з IP 192.168.2.19.
2. На самій ноді: `systemctl status k3s-agent` (або `k3s` на master), переконатися, що kubelet слухає на 10250.
3. Якщо CoreDNS запланований на цю ноду — застосувати **node affinity**, щоб CoreDNS біг лише на ноді з стабільним зв’язком до API (наприклад master-node): див. Крок 3. Тоді й логи можна буде читати без 502.

Після цього `kubectl logs` до подів на цій ноді може запрацювати, якщо зв’язок відновлено.

---

## Крок 5: Перезапуск CoreDNS та перевірка логів

Після змін RBAC або мережі:

```bash
kubectl rollout restart deployment coredns -n kube-system
kubectl rollout status deployment coredns -n kube-system
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50 -f
```

Якщо з’являється **502 Bad Gateway** при `kubectl logs` — API server не досягає kubelet на ноді, де біжить CoreDNS; див. Крок 4. Логи можна переглянути безпосередньо на ноді: `sudo crictl logs <container-id>`. **Важливо:** використовуйте **container ID** (перша колонка з `crictl ps`), а не image ID (друга колонка); інакше буде «container not found».

Очікується: зникнення повторюваних «Failed to watch» і «Plugins not ready: kubernetes». Можливі однократні «watch ended with error» під час перезапуску — це прийнятно.

---

## Крок 6: Cilium NetworkPolicy — egress до API server

Якщо в кластері Cilium з **default-deny** політиками, поди CoreDNS повинні мати явний **egress** до Kubernetes API (ClusterIP), порт 443/TCP. Без цього з’являється `dial tcp 10.96.0.1:443: i/o timeout` (або 10.43.0.1 залежно від Service CIDR).

**Застосувати готову політику** (дозволяє egress до 8.8.8.8/1.1.1.1:53 та до API 10.96.0.1:443):

```bash
kubectl apply -f manifests/cilium/networkpolicy-coredns-egress-upstream-dns.yaml
```

Якщо після цього поди CoreDNS на **окремих нодах** (наприклад beelinkeqr5, macmini7) лишаються 0/1 Ready і в логах той самий timeout — причина вже не політика, а **маршрутизація/зв’язність**: з pod network цієї ноди немає шляху до ноди, де слухає API server (наприклад master-node в іншій мережі). Тоді варіанти:

1. **Node affinity** — запускати CoreDNS лише на нодах з гарантованим доступом до API (наприклад master-node): див. Крок 3 та `apply-coredns-node-affinity.sh`.
2. Перевірити міжнодову зв’язність (Cilium `cilium connectivity test`, firewall між Syhiv17/VRN625/OCI).

---

## Підсумок

| Симптом | Що перевірити |
|--------|----------------|
| Багато «Failed to watch» | RBAC (EndpointSlices), доступ поду до API (10.43.0.1:443) |
| «No route to host» у логах | Node affinity для CoreDNS (тільки ноди з маршрутом до API) |
| Після оновлення k3s | Повторно застосувати node affinity та перевірити RBAC |
| 502 при `kubectl logs` | Зв’язок API server ↔ kubelet на ноді (firewall, kubelet, node affinity) |

Якщо після цих кроків помилки лишаються — варто переглянути логи API server (k3s server) та стан ноди (ресурси, мережеві інтерфейси).
