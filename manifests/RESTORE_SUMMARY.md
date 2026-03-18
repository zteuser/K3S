# Підсумок відновлення з backup (2026-03-09)

## Що відновлено

### Storage
- StorageClass `ocfs2-shared`
- PV: pv-sharedata1, pv-sharedata2, pv-grafana-data, pv-loki-10gi, pv-prometheus-data
- PVC: grafana-data, loki-data, prometheus-data, portainer-data

### Monitoring (namespace: monitoring)
- **Grafana** — Running, LoadBalancer 10.0.10.51:3000
- **Prometheus** — Running
- **Loki** — Running
- **Alloy** — DaemonSet Running
- **node-exporter** — DaemonSet Running
- **kube-state-metrics** — Running
- Ingress: grafana (monitoring.lan), prometheus (prometheus.monitoring.lan)

### Зміни в манифестах
- Додано `tolerations` для control-plane taint у grafana, prometheus, loki
- Ingress: прибрано traefik class (Traefik не встановлено)
- Створено `pv-prometheus-data` (persistentvolume.yaml)
- Створено `pvc-restore.yaml` з коректними volumeName

## Доступ

| Сервіс | URL / IP | Порт |
|--------|----------|------|
| Grafana | http://10.0.10.51:3000 | 3000 |
| Hubble UI | http://10.0.10.53 | 80 |
| Prometheus | NodePort 30001 | 9090 |

## Що залишилось (опційно)

- **Portainer** — `kubectl apply -k manifests/portainer/`
- **ConfigMaps/Secrets з backup** — частково застосовано через Kustomize
- **Ingress з backup** — `kubectl apply -f backup-pre-cilium/ingress.yaml`
- **HelmChartConfig (Traefik)** — не застосовувати (Traefik відсутній)

## Примітки

- hostPath volumes (/sharedata1, /sharedata2, /sharedata1/loki тощо) створюються на master-node/work-node при першому mount
- Якщо OCFS2 не налаштовано — дані зберігаються локально на ноді
