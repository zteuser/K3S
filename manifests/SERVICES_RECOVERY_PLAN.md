# План відновлення сервісів у новому кластері k3s + Cilium

> **Передумова:** вирішити проблему pod connectivity 10.244.0.0/24 ↔ 10.244.1.0/24 (див. `POD_CONNECTIVITY_FIX_10_244.md`). Без cross-node connectivity CoreDNS та інші поди не працюватимуть.

---

## 1. Сервіси зі старого кластера (backup-pre-cilium)

### 1.1 Системні (kube-system)

| Компонент | Джерело | Дія |
|-----------|---------|-----|
| **CoreDNS** | k3s вбудований | Автоматично з k3s; перевірити node affinity (master-node, macmini7) |
| **Traefik** | k3s HelmChartConfig | Відновити `helmchartconfig.yaml` |
| **local-path-provisioner** | k3s | Автоматично |
| **metrics-server** | k3s | Автоматично |
| **Cilium** | Helm | Встановити окремо (`manifests/cilium/`) |

### 1.2 Monitoring (namespace: monitoring)

| Сервіс | Тип | Манифести | Залежності |
|--------|-----|-----------|------------|
| **Prometheus** | Deployment | `monitoring/prometheus/` | PVC, ConfigMap |
| **Grafana** | Deployment | `monitoring/grafana/` | PVC, ConfigMap, Secret, datasources |
| **Loki** | Deployment | `monitoring/loki/` | PVC, ConfigMap |
| **Alloy** | DaemonSet | `monitoring/alloy/` | ConfigMap (заміна Promtail) |
| **node-exporter** | DaemonSet | `monitoring/node-exporter/` | — |
| **kube-state-metrics** | Deployment | `monitoring/kube-state-metrics/` | ClusterRole, ServiceAccount |
| **snmp-exporter** | Deployment | `monitoring/snmp-exporter/` | ConfigMap, Secret |

**Kustomize:** `kubectl apply -k manifests/monitoring/`

### 1.3 Portainer

| Сервіс | Тип | Манифести |
|--------|-----|-----------|
| **Portainer** | Deployment | `manifests/portainer/` |
| **portainer-agent** | Deployment | `manifests/portainer-agent/` |

### 1.4 Storage

| Ресурс | Призначення |
|--------|-------------|
| **sharedata1, sharedata2** | OCFS2 shared volumes (Amper master/work-node) |
| **StorageClass ocfs2-shared** | `manifests/storage/storageclass-ocfs2.yaml` |

---

## 2. Порядок відновлення

### Крок 0: Перевірка pod connectivity

```bash
kubectl run test-dns --image=busybox:1.36 --restart=Never -- nslookup kube-dns.kube-system.svc.cluster.local
kubectl logs test-dns
kubectl delete pod test-dns
```

Якщо timeout — спочатку вирішити `POD_CONNECTIVITY_FIX_10_244.md`.

---

### Крок 1: ConfigMaps, Secrets

```bash
kubectl apply -f backup-pre-cilium/configmaps.yaml
kubectl apply -f backup-pre-cilium/secrets.yaml
```

### Крок 2: PVC (перед workload)

```bash
kubectl apply -f backup-pre-cilium/pvc.yaml
```

**Важливо:** PVC для Loki, Grafana, Prometheus потребують PV. Якщо PV на OCFS2 — перевірити `manifests/storage/` та `manifests/monitoring/loki/persistentvolume.yaml`.

### Крок 3: Monitoring (Kustomize)

```bash
kubectl apply -k manifests/monitoring/
```

### Крок 4: Portainer

```bash
kubectl apply -f manifests/portainer/namespace.yaml
kubectl apply -k manifests/portainer/
kubectl apply -f manifests/portainer-agent/
```

### Крок 5: Ingress

```bash
kubectl apply -f backup-pre-cilium/ingress.yaml
```

### Крок 6: HelmChartConfig (Traefik)

```bash
kubectl apply -f backup-pre-cilium/helmchartconfig.yaml
```

---

## 3. Підготовка restore-workloads.yaml

Бекап `all-resources.yaml` містить Pods, ReplicaSets — їх не відновлюємо. Потрібно витягти лише Deployments, DaemonSets, StatefulSets, Services.

**З yq:**
```bash
yq eval '
  .items |= map(select(.kind != "Pod" and .kind != "ReplicaSet"))
' backup-pre-cilium/all-resources.yaml > restore-workloads.yaml
```

**Або скрипт prepare-restore.py** (якщо є):
```bash
python3 backup-pre-cilium/prepare-restore.py backup-pre-cilium/all-resources.yaml restore-workloads.yaml
```

**Виключити системні k3s:** coredns, traefik, local-path, metrics-server — вони вже є.

---

## 4. Що може потребувати виправлення

| Проблема | Рішення |
|----------|---------|
| Node affinity (nodeName) | Поди привʼязані до macmini7/master-node — перевірити nodeSelector, можливо змінити на nodeAffinity |
| PVC не знаходить PV | Створити PV вручну, перевірити StorageClass |
| CoreDNS node affinity | Манифест `manifests/coredns/coredns-node-affinity-patch.yaml` |
| Loki permissions | Див. `manifests/monitoring/loki/FIX_LOKI_PERMISSIONS.md` |
| Secrets | Відновити з backup; якщо vault — окремо |

---

## 5. Чеклист відновлення

- [ ] Pod connectivity 10.244.x.x cross-node працює
- [ ] ConfigMaps, Secrets застосовано
- [ ] PVC застосовано, PV існують
- [ ] Monitoring: `kubectl apply -k manifests/monitoring/`
- [ ] Portainer: `kubectl apply -k manifests/portainer/`
- [ ] Ingress застосовано
- [ ] HelmChartConfig (Traefik) застосовано
- [ ] `kubectl get pods -A` — усі Ready (окрім можливих Pending через PVC)
- [ ] Grafana доступна через Ingress
- [ ] Prometheus збирає метрики

---

## 6. Скрипт відновлення

Один виклик (з кореня репо k3s):

```bash
./manifests/scripts/restore-services.sh
```

Опції:
- `--skip-connectivity-check` — не виконувати крок 0 (перевірка DNS/pod connectivity)
- `--skip-backup-pvc` — не застосовувати PVC з `backup-pre-cilium/pvc.yaml` (якщо використовуєте лише PVC з manifests/monitoring/)
- `--dry-run` — вивести команди без виконання
