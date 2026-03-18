# Бекап перед міграцією на Cilium

Знімок стану кластера k3s перед заміною Flannel на Cilium.

## Файли (зроблено з control-plane)

| Файл | Опис |
|------|------|
| **all-resources.yaml** | Усі workload (pods, services, deployments, daemonsets, statefulsets, jobs, cronjobs) |
| **configmaps.yaml** | ConfigMaps з усіх namespace |
| **pvc.yaml** | PersistentVolumeClaims |
| **ingress.yaml** | Ingress ресурси |
| **helmchartconfig.yaml** | HelmChartConfig (Traefik тощо) |
| **secrets.yaml** | Secrets з усіх namespace |
| **nodes.txt** | Список нод (kubectl get nodes -o wide) |
| **cluster-info.txt** | Версія kubectl/k3s, API server |

## Що потрібно зробити вручну

**Конфіги k3s на кожній ноді** — запустити `backup-node-configs.sh` на кожній ноді:

```bash
# macmini7 (192.168.2.19)
ssh user@192.168.2.19 'bash -s' < backup-node-configs.sh > node-macmini7.txt

# beelinkeqr5 (192.168.1.19)
ssh user@192.168.1.19 'bash -s' < backup-node-configs.sh > node-beelinkeqr5.txt

# master-node (10.0.10.10)
ssh user@10.0.10.10 'bash -s' < backup-node-configs.sh > node-master-node.txt

# work-node (10.0.10.20)
ssh user@10.0.10.20 'bash -s' < backup-node-configs.sh > node-work-node.txt
```

Або скопіювати скрипт на ноду і запустити локально, результат зберегти.

## Відновлення

При відкаті міграції або перевстановленні кластера:

1. **Підготовка workload:** `python3 prepare-restore.py all-resources.yaml restore-workloads.yaml` (потребує `pip install pyyaml`)
2. Застосувати: configmaps, secrets, pvc, restore-workloads.yaml, ingress
3. Конфіги нод відновити вручну з `node-*.txt`

Детальний план: `manifests/K3S_FRESH_INSTALL_CILIUM_RESTORE.md`
