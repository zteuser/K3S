# Як PVC prometheus-data зв'язується з PV pv-sharedata1

## Механізм прив'язки PVC до PV в Kubernetes

### Поточна ситуація

У вас є:
- **PV (PersistentVolume)**: `pv-sharedata1` - фізичний volume в кластері
- **PVC (PersistentVolumeClaim)**: `pvc-sharedata1` в namespace `default` - прив'язаний до `pv-sharedata1`
- **Потрібно**: Створити `prometheus-data` PVC в namespace `monitoring`, який використовує той самий `pv-sharedata1`

### Важливе обмеження Kubernetes

⚠️ **Один PV може бути прив'язаний тільки до ОДНОГО PVC одночасно**, навіть якщо PV має `ReadWriteMany` access mode.

Це означає, що якщо `pv-sharedata1` вже прив'язаний до `pvc-sharedata1`, він **не може** бути прив'язаний до `prometheus-data` одночасно.

---

## Варіанти рішення

### Варіант 1: Використати існуючий PVC напряму (найпростіше)

Якщо `pvc-sharedata1` не використовується (Unused), можна:

1. **Видалити старий PVC** `pvc-sharedata1` з namespace `default`
2. **Створити новий PVC** `prometheus-data` в namespace `monitoring` з посиланням на `pv-sharedata1`

**Переваги:**
- Просто
- Використовує той самий фізичний storage
- Не потребує додаткових налаштувань

**Недоліки:**
- Втрачаєте старий PVC (але дані залишаються, оскільки `reclaimPolicy: Retain`)

---

### Варіант 2: Використати volumeName для прямого посилання (рекомендовано)

Якщо ви хочете зберегти обидва PVC, але використати той самий PV:

1. **Спочатку видаліть або звільніть** `pvc-sharedata1` (якщо він не використовується)
2. **Створіть новий PVC** `prometheus-data` з `volumeName: pv-sharedata1`

**Крок 1: Знайдіть ім'я PV**

```bash
# Варіант 1: Через kubectl
kubectl get pv
# Шукайте PV з ім'ям типу pv-sharedata1

# Варіант 2: Через Portainer
# Kubernetes → Volumes → pvc-sharedata1 → поле "Volume"
```

**Крок 2: Перевірте статус PVC**

```bash
kubectl get pvc pvc-sharedata1 -n default
kubectl describe pvc pvc-sharedata1 -n default
```

Якщо статус `Unused` (як показано в Portainer), можна безпечно видалити або залишити.

**Крок 3: Створіть новий PVC з volumeName**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data
  namespace: monitoring
  labels:
    app: prometheus
spec:
  volumeName: pv-sharedata1  # Пряме посилання на PV
  accessModes:
    - ReadWriteOnce  # Або ReadWriteMany, якщо PV підтримує
  resources:
    requests:
      storage: 48Gi
  storageClassName: ocfs2-shared
```

**Важливо:** 
- `volumeName` вказує Kubernetes прив'язати саме цей PVC до конкретного PV
- PV має бути в статусі `Available` (не прив'язаний до іншого PVC)
- Access modes мають співпадати з PV

---

### Варіант 3: Використати selector (якщо PV має labels)

Якщо PV має labels, можна використати selector:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ocfs2-shared
  resources:
    requests:
      storage: 48Gi
  selector:
    matchLabels:
      storage: sharedata1  # Label з PV
```

---

## Покрокова інструкція для Portainer

### Крок 1: Перевірте поточний стан

1. Відкрийте Portainer UI
2. Перейдіть до **Kubernetes** → **Volumes**
3. Знайдіть `pvc-sharedata1`
4. Перевірте:
   - **Status**: Має бути `Unused` (якщо використовується, спочатку видаліть pod, який його використовує)
   - **Volume**: Запишіть ім'я PV (наприклад, `pv-sharedata1`)

### Крок 2: Знайдіть ім'я PV

**Через Portainer:**
1. Клікніть на `pvc-sharedata1`
2. Знайдіть поле **Volume** - це ім'я PV

**Через kubectl:**
```bash
# Варіант 1: Через PVC
kubectl get pvc pvc-sharedata1 -n default -o jsonpath='{.spec.volumeName}'

# Варіант 2: Список всіх PV
kubectl get pv

# Варіант 3: Детальна інформація про PV
kubectl describe pv pv-sharedata1
```

### Крок 3: Видаліть старий PVC (якщо не використовується)

⚠️ **Увага:** Це видалить PVC, але дані залишаться (оскільки `reclaimPolicy: Retain`)

1. В Portainer: **Kubernetes** → **Volumes** → виберіть `pvc-sharedata1` → **Remove**
2. Або через kubectl: `kubectl delete pvc pvc-sharedata1 -n default`

**Перевірка, що PV звільнений:**
```bash
kubectl get pv pv-sharedata1
# Статус має бути "Available"
```

### Крок 4: Створіть новий PVC в namespace monitoring

1. Перейдіть до **Kubernetes** → **Namespaces** → **monitoring**
2. **PVCs** → **Add PVC**
3. **Editor** mode
4. Скопіюйте та вставте:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data
  namespace: monitoring
  labels:
    app: prometheus
spec:
  volumeName: pv-sharedata1  # Замініть на реальне ім'я PV з кроку 2
  accessModes:
    - ReadWriteMany  # Або ReadWriteOnce, залежно від PV
  resources:
    requests:
      storage: 48Gi
  storageClassName: ocfs2-shared
```

5. **Важливо:** Замініть `pv-sharedata1` на реальне ім'я PV
6. Перевірте `accessModes` - вони мають співпадати з PV (зазвичай `ReadWriteMany` для OCFS2)
7. Натисніть **Create the PVC**

### Крок 5: Перевірка прив'язки

```bash
# Перевірка статусу PVC
kubectl get pvc prometheus-data -n monitoring

# Перевірка, що PVC прив'язаний до правильного PV
kubectl describe pvc prometheus-data -n monitoring | grep -A 5 "Volume:"

# Перевірка статусу PV
kubectl get pv pv-sharedata1
# Статус має бути "Bound"
```

---

## Як працює volumeName

Коли ви вказуєте `volumeName` в PVC spec:

1. **Kubernetes шукає PV** з вказаним ім'ям
2. **Перевіряє сумісність:**
   - Access modes мають співпадати
   - Storage class має співпадати (або бути відсутнім)
   - Розмір має бути достатнім
3. **Прив'язує PVC до PV**, якщо всі умови виконані
4. **PV отримує статус "Bound"**

**Без `volumeName`:**
- Kubernetes автоматично знаходить відповідний PV за storage class та access modes
- Може вибрати будь-який доступний PV, що відповідає вимогам

**З `volumeName`:**
- Kubernetes прив'язує PVC саме до вказаного PV
- Гарантує використання конкретного фізичного storage

---

## Troubleshooting

### Помилка: "volume is already bound"

**Причина:** PV вже прив'язаний до іншого PVC

**Рішення:**
1. Перевірте, який PVC використовує PV:
   ```bash
   kubectl get pv pv-sharedata1 -o jsonpath='{.spec.claimRef.name}'
   ```
2. Видаліть старий PVC або звільніть його
3. Перевірте, що PV має статус "Available":
   ```bash
   kubectl get pv pv-sharedata1
   ```

### Помилка: "no persistent volumes available"

**Причина:** Немає доступного PV, що відповідає вимогам

**Рішення:**
1. Перевірте доступні PV:
   ```bash
   kubectl get pv
   ```
2. Перевірте, що access modes співпадають
3. Перевірте storage class

### Помилка: "access modes do not match"

**Причина:** Access modes PVC не співпадають з PV

**Рішення:**
1. Перевірте access modes PV:
   ```bash
   kubectl get pv pv-sharedata1 -o jsonpath='{.spec.accessModes}'
   ```
2. Змініть access modes в PVC на ті, що підтримує PV
3. Для OCFS2 зазвичай це `ReadWriteMany`

---

## Приклад повного процесу

```bash
# 1. Знайдіть ім'я PV
kubectl get pv
# NAME            CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM
# pv-sharedata1   48Gi       RWX            Retain           Bound    default/pvc-sharedata1

# 2. Перевірте, що PVC не використовується
kubectl get pvc pvc-sharedata1 -n default
# NAME            STATUS   VOLUME          CAPACITY   ACCESS MODES
# pvc-sharedata1  Bound    pv-sharedata1  48Gi       RWX

# 3. Видаліть старий PVC (якщо не використовується)
kubectl delete pvc pvc-sharedata1 -n default

# 4. Перевірте, що PV звільнений
kubectl get pv pv-sharedata1
# NAME            CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM
# pv-sharedata1   48Gi       RWX            Retain           Available   

# 5. Створіть новий PVC з volumeName
kubectl apply -f prometheus/pvc.yaml
# (з volumeName: pv-sharedata1)

# 6. Перевірка
kubectl get pvc prometheus-data -n monitoring
# NAME              STATUS   VOLUME          CAPACITY   ACCESS MODES
# prometheus-data   Bound    pv-sharedata1   48Gi       RWX
```

---

## Висновок

**Для прив'язки `prometheus-data` до `pv-sharedata1`:**

1. ✅ Використайте поле `volumeName: pv-sharedata1` в PVC spec
2. ✅ Переконайтеся, що PV має статус "Available" (не прив'язаний до іншого PVC)
3. ✅ Переконайтеся, що access modes співпадають
4. ✅ Створіть PVC в namespace `monitoring`

**Результат:** `prometheus-data` PVC буде прив'язаний до `pv-sharedata1` PV, і Prometheus використовуватиме той самий фізичний storage, що раніше використовував `pvc-sharedata1`.
