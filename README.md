# Kubernetes кластер (k8s)

Проєкт спочатку використовував **k3s**; виконано **міграцію на стандартний Kubernetes (k8s)** з kubeadm. Поточна платформа — **k8s**.

---

## Поточний стан

- **Control-plane:** master-node та інші control-plane ноди (kubeadm).
- **CNI:** Cilium.
- **Kubeconfig на master-node:** `/etc/kubernetes/admin.conf`

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get nodes
```

Для роботи з кластером з іншої машини — скопіюйте `admin.conf` і вкажіть у ньому правильний `server:` (IP/DNS API сервера).

---

## Структура репозиторію

- **manifests/** — Cilium, monitoring (Loki, Promtail, Alloy), Portainer, BGP, storage тощо.
- **backup-pre-cilium/** — бекапи та скрипти до міграції.
- **wireguard-configs/** — конфіги WireGuard для зв’язності нод.
- Документація з планами міграції, відновлення та join нод залишена для історії (k3s → k8s).
