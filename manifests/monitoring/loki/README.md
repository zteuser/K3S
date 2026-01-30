# Loki (namespace: monitoring)

Loki деплоїться в **namespace `monitoring`** поруч з Prometheus та Grafana.

## Volume

- **PVC:** `loki-data`
- **Розмір:** 10 ГіБ
- **StorageClass:** `ocfs2-shared` (файл `manifests/storage/storageclass-ocfs2.yaml`)

Для no-provisioner (OCFS2) у репозиторії є **PV** `manifests/monitoring/loki/persistentvolume.yaml` (10 ГіБ, шлях `/sharedata1/loki` на нодах master-node/work-node). Застосуйте його **перед** PVC: `kubectl apply -f manifests/monitoring/loki/persistentvolume.yaml`.

## Деплой

Через Kustomize (разом з усім monitoring stack):

```bash
kubectl apply -k manifests/monitoring
```

Або окремо:

```bash
# 1. PV (щоб PVC міг прив'язатися)
kubectl apply -f manifests/monitoring/loki/persistentvolume.yaml
# 2. Решта
kubectl apply -f manifests/monitoring/loki/pvc.yaml
kubectl apply -f manifests/monitoring/loki/configmap.yaml
kubectl apply -f manifests/monitoring/loki/deployment.yaml
kubectl apply -f manifests/monitoring/loki/service.yaml
```

## Перевірка

```bash
kubectl -n monitoring get pods -l app=loki
kubectl -n monitoring get svc loki
kubectl -n monitoring logs -l app=loki --tail=20
```

Grafana: додати datasource **Loki**, URL: `http://loki:3100` (в тому ж namespace `monitoring`).

## Якщо PVC лишається Pending після створення PV

При `volumeBindingMode: WaitForFirstConsumer` PVC прив’язується до PV, коли под, який його використовує, планується на ноду. Після того як PV з’явився, перезапустіть под Loki — scheduler і volume binder знову спробують прив’язати PVC і запланувати под:

```bash
kubectl -n monitoring delete pod -l app=loki
```

Потім перевірте: `kubectl get pv pv-loki-10gi` (STATUS має бути Bound), `kubectl -n monitoring get pvc loki-data`, `kubectl -n monitoring get pods -l app=loki`.
