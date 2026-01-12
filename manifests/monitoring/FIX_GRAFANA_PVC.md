# Виправлення проблеми з PVC для Grafana

## Проблема

Grafana pod не може запуститися через помилку:
```
0/3 nodes are available: 3 node(s) didn't find available persistent volumes to bind
```

## Причина

PVC `grafana-data` не може прив'язатися до PV, тому що:
1. `pv-sharedata2` вже прив'язаний до `pvc-sharedata2` в namespace `default`
2. PVC не має `volumeName` для прямого посилання на PV
3. Kubernetes не може знайти доступний PV з правильними параметрами

## Рішення

### Крок 1: Перевірте поточний стан

```bash
# Перевірте статус PV
kubectl get pv | grep sharedata2

# Перевірте статус PVC в default namespace
kubectl get pvc pvc-sharedata2 -n default

# Перевірте статус PVC в monitoring namespace
kubectl get pvc grafana-data -n monitoring
```

### Крок 2: Видаліть старий PVC (якщо не використовується)

Якщо `pvc-sharedata2` в namespace `default` не використовується:

```bash
# Видаліть старий PVC
kubectl delete pvc pvc-sharedata2 -n default

# Перевірте, що PV звільнений
kubectl get pv pv-sharedata2
# Статус має бути "Available"
```

**Через Portainer:**
1. Перейдіть до **Kubernetes** → **Volumes**
2. Знайдіть `pvc-sharedata2` в namespace `default`
3. Виберіть checkbox біля назви
4. Натисніть **Remove**
5. Підтвердіть видалення

### Крок 3: Оновіть PVC для Grafana

**Через Portainer:**

1. Перейдіть до **Kubernetes** → **Applications** → **monitoring**
2. Знайдіть PVC `grafana-data` (або **Volumes** → **monitoring**)
3. Натисніть на `grafana-data`
4. Натисніть **Editor**
5. Скопіюйте оновлений вміст з `grafana/pvc.yaml`
6. **Важливо:** Переконайтеся, що `volumeName: pv-sharedata2` розкоментовано
7. Натисніть **Update**

**Або видаліть і створіть заново:**

1. Видаліть старий PVC `grafana-data`
2. Створіть новий через **Kubernetes** → **Applications** → **monitoring** → **Create from code**
3. Скопіюйте вміст з `grafana/pvc.yaml` (з `volumeName: pv-sharedata2`)

### Крок 4: Перевірка прив'язки

```bash
# Перевірка статусу PVC
kubectl get pvc grafana-data -n monitoring
# Статус має бути "Bound"

# Перевірка, що PVC прив'язаний до правильного PV
kubectl describe pvc grafana-data -n monitoring | grep -A 5 "Volume:"

# Перевірка статусу PV
kubectl get pv pv-sharedata2
# Статус має бути "Bound"
```

### Крок 5: Перезапустіть Grafana deployment

Після того, як PVC прив'язаний:

```bash
# Перезапустіть deployment
kubectl rollout restart deployment/grafana -n monitoring

# Або через Portainer:
# Kubernetes → Applications → monitoring → grafana → Editor → Update
```

## Альтернативне рішення (якщо PV не доступний)

Якщо `pv-sharedata2` не може бути звільнений, створіть новий PVC без `volumeName`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-data
  namespace: monitoring
  labels:
    app: grafana
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 48Gi
  storageClassName: ocfs2-shared
```

Це створить новий PVC, який буде використовувати той самий storage class (можливо, створить новий PV або використає інший доступний).

## Troubleshooting

### Помилка: "volume is already bound"

**Рішення:**
1. Видаліть старий PVC `pvc-sharedata2` з namespace `default`
2. Перевірте, що PV має статус "Available"
3. Створіть новий PVC з `volumeName: pv-sharedata2`

### Помилка: "access modes do not match"

**Рішення:**
1. Перевірте access modes PV:
   ```bash
   kubectl get pv pv-sharedata2 -o jsonpath='{.spec.accessModes}'
   ```
2. Переконайтеся, що в PVC вказано `ReadWriteMany` (RWX)

### Помилка: "storage class not found"

**Рішення:**
1. Перевірте доступні storage classes:
   ```bash
   kubectl get storageclass
   ```
2. Переконайтеся, що `ocfs2-shared` існує

## Після виправлення

Після того, як PVC прив'язаний:

1. Grafana pod має запуститися
2. Перевірте статус:
   ```bash
   kubectl get pods -n monitoring -l app=grafana
   ```
3. Доступ до Grafana: `http://<node-ip>:30000`
