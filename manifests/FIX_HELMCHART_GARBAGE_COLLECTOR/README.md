# Виправлення помилки garbage-collector: unable to get REST mapping for helm.cattle.io/v1/HelmChart

## Проблема

У логах kube-controller-manager повторюється:
```
"error syncing item" err="unable to get REST mapping for helm.cattle.io/v1/HelmChart."
item="[helm.cattle.io/v1/HelmChart, name: traefik-crd, ...]"
item="[helm.cattle.io/v1/HelmChart, name: traefik, ...]"
```

**Причина:** Залишки від k3s в etcd (traefik-crd, traefik) після міграції на k8s з Cilium. CRD `helm.cattle.io` відсутній, тому API не може обробити ці об'єкти.

## Рішення

1. Встановити CRD `helmcharts.helm.cattle.io`
2. Видалити orphaned HelmCharts через kubectl

## Виконання

```bash
cd manifests/FIX_HELMCHART_GARBAGE_COLLECTOR
chmod +x fix-helmchart-garbage-collector.sh
./fix-helmchart-garbage-collector.sh
```

Або вручну:
```bash
kubectl apply -f manifests/FIX_HELMCHART_GARBAGE_COLLECTOR/helmchart-crd.yaml
sleep 5
kubectl delete helmchart traefik-crd -n kube-system --ignore-not-found
kubectl delete helmchart traefik -n kube-system --ignore-not-found
```

Після виконання помилки в логах зникнуть протягом 1–2 хвилин.
