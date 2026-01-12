# Виправлення прив'язки PVC grafana-data

## Поточна проблема

З виводу `kubectl get pv pv-sharedata2` видно:
```
pv-sharedata2   45Gi   RWX   Retain   Bound   portainer/portainer-data
```

`pv-sharedata2` вже прив'язаний до `portainer/portainer-data`, тому `grafana-data` не може його використати.

## Рішення

### Варіант 1: Створити новий PV для Grafana (рекомендовано)

Оскільки OCFS2 дозволяє одночасний доступ, можна створити новий PV, який використовує той самий фізичний storage `/sharedata2`.

**Крок 1: Створіть новий PV**

Через Portainer:
1. Перейдіть до **Kubernetes** → **Storage**
2. Натисніть **Add PV** (або **Create PV**)
3. Виберіть **Editor**
4. Скопіюйте вміст з `grafana/persistentvolume.yaml`
5. Натисніть **Create**

Або через kubectl:
```bash
kubectl apply -f grafana/persistentvolume.yaml
```

**Крок 2: Оновіть PVC з volumeName**

1. Перейдіть до **Kubernetes** → **Applications** → **monitoring**
2. Знайдіть PVC `grafana-data`
3. Натисніть **Editor**
4. Розкоментуйте рядок `volumeName: pv-grafana-data` в `grafana/pvc.yaml`
5. Оновіть PVC

### Варіант 2: Використати PVC без volumeName (якщо storage class підтримує dynamic provisioning)

Якщо storage class `ocfs2-shared` має dynamic provisioning, просто приберіть `volumeName` з PVC:

1. Відкрийте PVC `grafana-data` в Portainer
2. Натисніть **Editor**
3. Приберіть рядок `volumeName: pv-sharedata2` (закоментуйте або видаліть)
4. Оновіть PVC

### Варіант 3: Використати той самий фізичний storage (OCFS2 дозволяє)

Оскільки OCFS2 підтримує `ReadWriteMany`, можна створити новий PV на тому ж `/sharedata2`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-grafana-data
spec:
  capacity:
    storage: 48Gi
  accessModes:
    - ReadWriteMany
  storageClassName: ocfs2-shared
  hostPath:
    path: /sharedata2  # Той самий фізичний storage
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - master-node
          - work-node
```

## Швидке рішення

### 1. Видаліть поточний PVC grafana-data

**Через Portainer:**
- **Kubernetes** → **Volumes** → **monitoring**
- Виберіть `grafana-data`
- Натисніть **Remove**

**Або через kubectl:**
```bash
kubectl delete pvc grafana-data -n monitoring
```

### 2. Створіть новий PV для Grafana

```bash
kubectl apply -f grafana/persistentvolume.yaml
```

### 3. Створіть новий PVC з volumeName

1. **Kubernetes** → **Applications** → **monitoring** → **Create from code**
2. Скопіюйте вміст з `grafana/pvc.yaml`
3. Розкоментуйте `volumeName: pv-grafana-data`
4. **Deploy**

### 4. Перевірка

```bash
# Перевірка PV
kubectl get pv pv-grafana-data
# Статус має бути "Available"

# Перевірка PVC
kubectl get pvc grafana-data -n monitoring
# Статус має бути "Bound"

# Перевірка pod
kubectl get pods -n monitoring -l app=grafana
```

## Важливо

⚠️ **OCFS2 дозволяє одночасний доступ**, тому кілька PV можуть використовувати той самий фізичний storage `/sharedata2`. Це безпечно для OCFS2.

⚠️ **Дані не будуть втрачені** - всі дані зберігаються в `/sharedata2` на нодах.
