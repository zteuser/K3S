# Cilium для k3s

Helm values для встановлення Cilium CNI замість Flannel.

## Файли

| Файл | Опис |
|------|------|
| **values-k3s.yaml** | Helm values, адаптовані під топологію k3s (10.42/10.43, node мережі) |
| **K3S_CILIUM_NETWORK_DIAGRAM.pdf** | Мережева діаграма кластера після міграції на Cilium |
| **diagram_cilium_network.py** | Скрипт генерації діаграми (Python + matplotlib) |

## Перед встановленням

1. **k8sServiceHost** — замінити `CHANGE_ME` на IP API server, досяжний з усіх нод (наприклад `10.0.10.10` або `192.168.2.19`).

2. **devices** — якщо на нодах інший основний інтерфейс (не eth0), змінити на відповідний (наприклад `enp0s3` або regex `eth0|enp0s3`).

## Використання

Див. покроковий план: [CILIUM_MIGRATION_PLAN.md](../CILIUM_MIGRATION_PLAN.md).

## Помилка "cannot get resource leases" (L2 announcements)

Якщо в логах cilium-agent з’являється:
`leases.coordination.k8s.io ... is forbidden: User "system:serviceaccount:kube-system:cilium" cannot get resource "leases"` — Cilium використовує L2 announcements (leader election) для LoadBalancer-сервісів (Hubble UI, Grafana, Portainer тощо), але в RBAC немає прав на Lease.

**Рішення:** застосувати додатковий RBAC:

```bash
kubectl apply -f manifests/cilium/rbac-l2-announce-leases.yaml
```

Файл **rbac-l2-announce-leases.yaml** створює ClusterRole та ClusterRoleBinding для доступу SA `cilium` до ресурсів `leases` у API group `coordination.k8s.io`. Після застосування помилки в логах мають зникнути.

## Додаткові можливості (LB-IPAM, Egress, Gateway API)

Після базової міграції можна вмикати LB-IPAM, Egress Gateway, NetworkPolicy тощо — див. розділ 4 плану міграції та [офіційну документацію Cilium](https://docs.cilium.io/).
