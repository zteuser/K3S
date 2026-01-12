# Використання існуючих volumes для моніторингу

Якщо у вас вже є volumes `pvc-sharedata1` та `pvc-sharedata2` і ви хочете використати їх для моніторингу, є кілька варіантів.

**📖 Детальне пояснення механізму прив'язки:** Див. `HOW_PVC_BINDS_TO_PV.md`

## Поточна ситуація

З Portainer UI видно, що у вас є:
- `pvc-sharedata1` (48.3 GB, ocfs2-shared, namespace: default, Unused)
- `pvc-sharedata2` (48.3 GB, ocfs2-shared, namespace: default, Unused)

## Варіанти використання

### Варіант 1: Використати існуючі PVC напряму (рекомендовано)

Якщо ви хочете використати саме ці PVC, потрібно:

1. **Перемістити PVC в namespace monitoring** або **створити нові PVC в monitoring**, які посилаються на той самий PV

#### Крок 1: Знайдіть імена PersistentVolumes

```bash
kubectl get pv
# Знайдіть PV, які використовуються pvc-sharedata1 та pvc-sharedata2
```

#### Крок 2: Створіть нові PVC в namespace monitoring

Використайте файли `pvc-existing.yaml`:

**Для Prometheus (використовує pvc-sharedata1):**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data
  namespace: monitoring
spec:
  volumeName: <PV_NAME_FOR_SHAREDATA1>  # Вкажіть ім'я PV
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 48Gi
  storageClassName: ocfs2-shared
```

**Для Grafana (використовує pvc-sharedata2):**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-data
  namespace: monitoring
spec:
  volumeName: <PV_NAME_FOR_SHAREDATA2>  # Вкажіть ім'я PV
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 48Gi
  storageClassName: ocfs2-shared
```

#### Крок 3: Розгорніть через Portainer

1. Створіть namespace `monitoring` (якщо ще не створено)
2. Створіть PVC `prometheus-data` з посиланням на PV для sharedata1
3. Створіть PVC `grafana-data` з посиланням на PV для sharedata2
4. Розгорніть решту компонентів як зазвичай

---

### Варіант 2: Використати існуючі PVC напряму (якщо вони в monitoring namespace)

Якщо ви перемістите або створите PVC в namespace `monitoring` з іменами `pvc-sharedata1` та `pvc-sharedata2`, просто змініть deployment файли:

**prometheus/deployment.yaml:**
```yaml
      - name: prometheus-storage
        persistentVolumeClaim:
          claimName: pvc-sharedata1  # Замість prometheus-data
```

**grafana/deployment.yaml:**
```yaml
      - name: grafana-storage
        persistentVolumeClaim:
          claimName: pvc-sharedata2  # Замість grafana-data
```

---

### Варіант 3: Створити нові PVC на тому ж storage (найпростіше)

Якщо ви хочете створити нові PVC, які використовують той самий storage class `ocfs2-shared`:

1. Використайте файли `pvc-existing.yaml` (або оновлені `pvc.yaml`)
2. Вони створять нові PVC з тим самим storage class
3. OCFS2 дозволяє одночасний доступ, тому це безпечно

**Через Portainer:**
1. Створіть PVC `prometheus-data` з `storageClassName: ocfs2-shared`
2. Створіть PVC `grafana-data` з `storageClassName: ocfs2-shared`
3. Розгорніть решту компонентів

---

## Покрокова інструкція для Portainer (Варіант 1)

### Крок 1: Знайдіть імена PV

1. Відкрийте Portainer UI
2. Перейдіть до **Kubernetes** → **Volumes**
3. Клікніть на `pvc-sharedata1`
4. Знайдіть поле **Volume** - це ім'я PV
5. Повторіть для `pvc-sharedata2`

Або через kubectl:
```bash
kubectl get pvc pvc-sharedata1 -n default -o jsonpath='{.spec.volumeName}'
kubectl get pvc pvc-sharedata2 -n default -o jsonpath='{.spec.volumeName}'
```

### Крок 2: Створіть namespace monitoring

1. **Kubernetes** → **Namespaces** → **Add namespace**
2. Назва: `monitoring`
3. **Create the namespace**

### Крок 3: Створіть PVC для Prometheus

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. **PVCs** → **Add PVC**
3. **Editor** mode
4. Скопіюйте вміст:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data
  namespace: monitoring
  labels:
    app: prometheus
spec:
  volumeName: <PV_NAME_FOR_SHAREDATA1>  # Замініть на реальне ім'я PV
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 48Gi
  storageClassName: ocfs2-shared
```

5. Замініть `<PV_NAME_FOR_SHAREDATA1>` на реальне ім'я PV
6. **Create the PVC**

### Крок 4: Створіть PVC для Grafana

1. **PVCs** → **Add PVC**
2. **Editor** mode
3. Скопіюйте вміст:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-data
  namespace: monitoring
  labels:
    app: grafana
spec:
  volumeName: <PV_NAME_FOR_SHAREDATA2>  # Замініть на реальне ім'я PV
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 48Gi
  storageClassName: ocfs2-shared
```

4. Замініть `<PV_NAME_FOR_SHAREDATA2>` на реальне ім'я PV
5. **Create the PVC**

### Крок 5: Розгорніть решту компонентів

Далі розгортайте компоненти моніторингу як зазвичай (див. `DEPLOYMENT_GUIDE.md`), але **пропустіть кроки створення PVC** для Prometheus та Grafana, оскільки вони вже створені.

---

## Перевірка

Після розгортання перевірте:

```bash
# Перевірка PVC
kubectl get pvc -n monitoring

# Перевірка, що вони використовують правильні PV
kubectl describe pvc prometheus-data -n monitoring
kubectl describe pvc grafana-data -n monitoring

# Перевірка подів
kubectl get pods -n monitoring

# Перевірка, що volumes підключені
kubectl describe pod -n monitoring -l app=prometheus | grep -A 5 "Volumes:"
kubectl describe pod -n monitoring -l app=grafana | grep -A 5 "Volumes:"
```

---

## Важливі нотатки

⚠️ **OCFS2 дозволяє одночасний доступ**, тому якщо ви створите нові PVC на тому ж storage class, вони можуть використовувати той самий фізичний storage. Це нормально для OCFS2.

⚠️ **Якщо ви використовуєте `volumeName`**, переконайтеся що:
- PV існує
- PV не вже використовується іншим PVC
- PV має правильний access mode (ReadWriteOnce)

⚠️ **Якщо PVC вже використовується**, вам потрібно або:
- Видалити старий PVC (якщо він не використовується)
- Або створити новий PVC на новому storage

---

## Troubleshooting

### Помилка: "volume is already bound"

Це означає, що PV вже прив'язаний до іншого PVC. Рішення:
- Використайте інший PV
- Або створіть новий PVC без `volumeName` (він створить новий PV)

### Помилка: "PVC not found"

Переконайтеся що:
- PVC створено в правильному namespace (`monitoring`)
- Ім'я PVC правильне в deployment файлах

### Помилка: "Storage class not found"

Переконайтеся що:
- Storage class `ocfs2-shared` існує: `kubectl get storageclass`
- Використовуєте правильне ім'я storage class
