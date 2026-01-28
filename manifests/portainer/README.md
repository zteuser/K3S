# Portainer для k3s Cluster

Ця директорія містить Kubernetes маніфести для розгортання Portainer CE в кластері k3s.

## Що таке Portainer?

Portainer - це легкий веб-інтерфейс для управління Kubernetes кластерами, Docker контейнерами та іншими контейнерними платформами.

## Архітектура

- **Namespace**: `portainer`
- **ServiceAccount**: `portainer` з ClusterRole для доступу до Kubernetes API
- **Deployment**: 1 replica Portainer CE
- **Service**: NodePort (порти 30900 для HTTP, 30943 для HTTPS)
- **Ingress**: доступ через **https://portainer.lan** (Traefik, TLS) — див. `PORTAINER_INGRESS.md`
- **Storage**: PVC з використанням OCFS2 shared storage (sharedata1)

## Передумови

1. **Storage**: OCFS2 storage має бути налаштований та створені PV
   ```bash
   cd ../storage
   ./deploy-storage.sh
   ```

2. **Ноди**: Deployment обмежений на ноди `master-node` та `work-node` (через nodeAffinity)

3. **Kubectl**: Налаштований доступ до k3s кластера

## Структура файлів

- `namespace.yaml` - Namespace для Portainer
- `serviceaccount.yaml` - ServiceAccount та RBAC (ClusterRole, ClusterRoleBinding)
- `persistentvolumeclaim.yaml` - PVC для збереження даних Portainer
- `deployment.yaml` - Deployment з Portainer контейнером
- `service.yaml` - NodePort Service для доступу до Portainer
- `ingress.yaml` - Ingress для доступу через https://portainer.lan
- `kustomization.yaml` - Kustomize конфігурація
- `PORTAINER_INGRESS.md` - налаштування https://portainer.lan та TLS secret
- `deploy-portainer.sh` - Скрипт автоматичного deployment

## Deployment

### Швидкий старт

```bash
cd /path/to/k3s/manifests/portainer
./deploy-portainer.sh
```

### Вручну (крок за кроком)

```bash
# 1. Створення Namespace
kubectl apply -f namespace.yaml

# 2. Створення ServiceAccount та RBAC
kubectl apply -f serviceaccount.yaml

# 3. Створення PVC
kubectl apply -f persistentvolumeclaim.yaml

# 4. Створення Deployment
kubectl apply -f deployment.yaml

# 5. Створення Service
kubectl apply -f service.yaml

# 6. Перевірка статусу
kubectl get all -n portainer
```

### Використання Kustomize

```bash
kubectl apply -k .
```

## Доступ до Portainer

Після deployment Portainer буде доступний через NodePort:

- **HTTP**: `http://<node-ip>:30900`
- **HTTPS**: `https://<node-ip>:30943`

Де `<node-ip>` - це IP адреса будь-якої ноди кластера (master-node або work-node).

### Приклад

```bash
# Отримати IP адресу ноди
kubectl get nodes -o wide

# Доступ через master-node (10.0.10.10)
http://10.0.10.10:30900

# Доступ через work-node (10.0.10.20)
http://10.0.10.20:30900
```

## Перший вхід

При першому відкритті Portainer:

1. Вам буде запропоновано створити адміністративний акаунт
2. Після створення акаунту ви зможете підключити k3s кластер
3. Portainer автоматично виявить Kubernetes environment

## Налаштування

### Зміна портів NodePort

Відредагуйте `service.yaml`:

```yaml
ports:
- name: http
  nodePort: 30900  # Змініть на потрібний порт
- name: https
  nodePort: 30943   # Змініть на потрібний порт
```

### Зміна розміру storage

Відредагуйте `persistentvolumeclaim.yaml`:

```yaml
resources:
  requests:
    storage: 1Gi  # Змініть на потрібний розмір
```

### Зміна ресурсів контейнера

Відредагуйте `deployment.yaml`:

```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

## Перевірка статусу

```bash
# Перевірка всіх ресурсів
kubectl get all -n portainer

# Перевірка статусу Pod
kubectl get pods -n portainer -o wide

# Перевірка логів
kubectl logs -f -l app=portainer -n portainer

# Перевірка PVC
kubectl get pvc -n portainer

# Детальна інформація про Pod
kubectl describe pod -l app=portainer -n portainer
```

## Troubleshooting

### Pod не запускається

```bash
# Перевірте статус Pod
kubectl describe pod -l app=portainer -n portainer

# Перевірте логи
kubectl logs -l app=portainer -n portainer

# Перевірте події
kubectl get events -n portainer --sort-by='.lastTimestamp'
```

### PVC не зв'язується з PV

```bash
# Перевірте статус PVC
kubectl describe pvc portainer-data -n portainer

# Перевірте доступні PV
kubectl get pv

# Переконайтеся що PV має правильні labels
kubectl get pv -o yaml | grep -A 5 labels
```

### Не можу підключитися до Portainer

1. Перевірте що Service створено:
   ```bash
   kubectl get svc -n portainer
   ```

2. Перевірте що Pod працює:
   ```bash
   kubectl get pods -n portainer
   ```

3. Перевірте firewall на нодах:
   ```bash
   # На нодах master-node та work-node
   sudo ufw status
   # Або
   sudo iptables -L -n | grep 30900
   ```

4. Перевірте доступність портів:
   ```bash
   # З іншої машини
   telnet <node-ip> 30900
   ```

### Проблеми з правами доступу

Перевірте що ServiceAccount має правильні права:

```bash
kubectl describe clusterrolebinding portainer
kubectl describe clusterrole portainer
```

## Оновлення

Для оновлення Portainer:

```bash
# Оновлення образу в deployment.yaml
# Змініть image: portainer/portainer-ce:latest на потрібну версію

# Застосуйте зміни
kubectl apply -f deployment.yaml

# Або виконайте rolling update
kubectl rollout restart deployment/portainer -n portainer
```

## Видалення

```bash
# Видалення всіх ресурсів
kubectl delete -f .

# Або через Kustomize
kubectl delete -k .

# Видалення namespace (видалить всі ресурси)
kubectl delete namespace portainer
```

**Увага**: При видаленні PVC дані Portainer будуть втрачені, якщо PV має `reclaimPolicy: Retain`. Для збереження даних спочатку зробіть backup.

## Backup та Restore

### Backup

```bash
# Створення backup PVC
kubectl get pvc portainer-data -n portainer -o yaml > portainer-pvc-backup.yaml

# Backup даних з PV (на ноді)
# Дані знаходяться в /sharedata1/portainer-data (або інший шлях залежно від PV)
```

### Restore

```bash
# Відновлення PVC
kubectl apply -f portainer-pvc-backup.yaml

# Відновлення даних на PV
# Скопіюйте дані назад в /sharedata1/portainer-data
```

## Додаткові ресурси

- [Portainer Documentation](https://docs.portainer.io/)
- [Portainer CE GitHub](https://github.com/portainer/portainer)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [K3s Documentation](https://docs.k3s.io/)
