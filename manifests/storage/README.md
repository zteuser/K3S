# OCFS2 Shared Storage для k3s Cluster

Ця директорія містить Kubernetes маніфести для налаштування shared storage на основі OCFS2 для кластера k3s.

## Архітектура

- **Control plane node**: macmini7
- **Worker nodes**: 
  - master-node (10.0.10.10)
  - work-node (10.0.10.20)
- **Shared OCFS2 storage**: sharedata1, sharedata2 (спільні для master-node та work-node)
- **OCFS2 Cluster**: ocfscluster

## Передумови

1. OCFS2 вже налаштований на рівні ОС на нодах master-node та work-node
2. OCFS2 volumes змонтовані в `/sharedata1` та `/sharedata2`
3. Перевірка статусу OCFS2:
   ```bash
   # На нодах master-node та work-node
   o2cb cluster-status
   o2cb list-nodes ocfscluster
   mount | grep ocfs2
   df -h | grep share
   ```

## Структура файлів

- `storageclass-ocfs2.yaml` - StorageClass для OCFS2 з manual provisioner
- `persistentvolume-sharedata1.yaml` - PersistentVolume для sharedata1
- `persistentvolume-sharedata2.yaml` - PersistentVolume для sharedata2
- `persistentvolumeclaim-example.yaml` - Приклади PVC для використання
- `statefulset-example.yaml` - Приклад StatefulSet з використанням shared storage
- `deployment-example.yaml` - Приклад Deployment з використанням shared storage

## Deployment

### 1. Налаштування маніфестів

Маніфести вже налаштовані з правильними параметрами:
- **Розмір storage**: 45Gi для кожного volume (5Gi залишається для системи)
- **Шляхи до mount points**: `/sharedata1` та `/sharedata2`
- **Ноди**: master-node та work-node

### 2. Створення ресурсів

```bash
# Створення StorageClass
kubectl apply -f storageclass-ocfs2.yaml

# Створення PersistentVolumes
kubectl apply -f persistentvolume-sharedata1.yaml
kubectl apply -f persistentvolume-sharedata2.yaml

# Перевірка статусу
kubectl get storageclass
kubectl get pv
```

### 3. Створення PVC (за потреби)

```bash
# Створення прикладів PVC
kubectl apply -f persistentvolumeclaim-example.yaml

# Перевірка статусу
kubectl get pvc
```

### 4. Deployment прикладів (опціонально)

```bash
# Deployment прикладу StatefulSet
kubectl apply -f statefulset-example.yaml

# Або Deployment прикладу
kubectl apply -f deployment-example.yaml

# Перевірка статусу
kubectl get pods -o wide
kubectl describe pod <pod-name>
```

## Використання в ваших додатках

### Приклад 1: StatefulSet з shared storage

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: my-app
spec:
  serviceName: my-app
  replicas: 2
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - master-node
                - work-node
      containers:
      - name: app
        image: my-app:latest
        volumeMounts:
        - name: shared-storage
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: shared-storage
    spec:
      accessModes:
        - ReadWriteMany
      storageClassName: ocfs2-shared
      resources:
        requests:
          storage: 10Gi
      selector:
        matchLabels:
          storage: sharedata1
```

### Приклад 2: Deployment з існуючим PVC

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 2
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - master-node
                - work-node
      containers:
      - name: app
        image: my-app:latest
        volumeMounts:
        - name: shared-data
          mountPath: /data
      volumes:
      - name: shared-data
        persistentVolumeClaim:
          claimName: pvc-sharedata1
```

## Важливі зауваження

1. **NodeAffinity**: Всі PersistentVolumes мають nodeAffinity до master-node та work-node, оскільки OCFS2 доступний тільки на цих нодах.

2. **AccessMode**: Використовується `ReadWriteMany` (RWX), оскільки OCFS2 підтримує одночасний доступ з кількох нод.

3. **ReclaimPolicy**: Встановлено `Retain` для захисту даних при видаленні PVC.

4. **StorageClass**: Використовується `kubernetes.io/no-provisioner` з `WaitForFirstConsumer`, що означає що PV створюються вручну.

5. **Перевірка перед deployment**: Завжди перевіряйте OCFS2 статус перед deployment:
   ```bash
   o2cb cluster-status
   o2cb list-nodes ocfscluster
   mount | grep ocfs2
   df -h | grep share
   ```

## Troubleshooting

### Перевірка статусу PV

```bash
kubectl get pv
kubectl describe pv pv-sharedata1
kubectl describe pv pv-sharedata2
```

### Перевірка статусу PVC

```bash
kubectl get pvc
kubectl describe pvc <pvc-name>
```

### Перевірка подів з volumes

```bash
kubectl get pods -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Перевірка на нодах

```bash
# На нодах master-node та work-node
o2cb cluster-status
o2cb list-nodes ocfscluster
mount | grep ocfs2
df -h | grep share
ls -la /sharedata1
ls -la /sharedata2
```

### Типові проблеми

1. **PV не знайдено**: Перевірте nodeAffinity та шляхи до OCFS2 mount points
2. **Pod не може примонтувати volume**: Перевірте що OCFS2 змонтований на ноді та pod має правильний nodeAffinity
3. **Permission denied**: Перевірте права доступу до директорій OCFS2

## Оновлення

Для оновлення конфігурації:

```bash
kubectl apply -f <manifest-file>.yaml
```

Для видалення:

```bash
# Спочатку видаліть всі PVC та Pods що використовують PV
kubectl delete pvc --all
kubectl delete pv pv-sharedata1 pv-sharedata2
kubectl delete storageclass ocfs2-shared
```

## Додаткові ресурси

- [K3s Documentation](https://docs.k3s.io/)
- [Kubernetes PersistentVolumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [OCFS2 Documentation](https://oss.oracle.com/projects/ocfs2/)

