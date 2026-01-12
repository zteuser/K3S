# Видалення дублікатів Prometheus

## Проблема

В Portainer відображаються дві однакові Prometheus applications. Це може бути через:
1. Старі deployment не були видалені перед створенням нового
2. Deployment створювався кілька разів
3. Помилка в Portainer UI

## Рішення

### Крок 1: Перевірка поточних deployment

**Через Portainer:**
1. Перейдіть до **Kubernetes** → **Applications** → **monitoring**
2. Знайдіть всі deployment з ім'ям `prometheus`
3. Перевірте статус кожного

**Через kubectl:**
```bash
kubectl get deployments -n monitoring | grep prometheus
kubectl get pods -n monitoring | grep prometheus
```

### Крок 2: Видалення зайвих deployment

**Через Portainer (рекомендовано):**
1. Перейдіть до **Kubernetes** → **Applications** → **monitoring**
2. Знайдіть всі Prometheus applications
3. Для кожного зайвого:
   - Виберіть checkbox біля назви
   - Натисніть кнопку **Remove** (або **Delete**)
   - Підтвердіть видалення

**Через kubectl:**
```bash
# Перевірте всі deployment
kubectl get deployments -n monitoring

# Видаліть зайві (замініть <deployment-name> на реальне ім'я)
kubectl delete deployment <deployment-name> -n monitoring

# Або видаліть всі prometheus deployment і створіть новий
kubectl delete deployment prometheus -n monitoring
```

### Крок 3: Перевірка ReplicaSets

Іноді залишаються старі ReplicaSets:

```bash
# Перевірте ReplicaSets
kubectl get replicasets -n monitoring | grep prometheus

# Видаліть старі ReplicaSets (якщо є)
kubectl delete replicaset <replicaset-name> -n monitoring
```

### Крок 4: Перевірка Pods

Перевірте, чи є застарілі поди:

```bash
# Перевірте всі поди
kubectl get pods -n monitoring | grep prometheus

# Видаліть застарілі поди (якщо є)
kubectl delete pod <pod-name> -n monitoring
```

### Крок 5: Очищення та створення нового deployment

Якщо є проблеми, видаліть все і створіть заново:

```bash
# Видаліть всі prometheus ресурси
kubectl delete deployment prometheus -n monitoring
kubectl delete replicaset -l app=prometheus -n monitoring
kubectl delete pod -l app=prometheus -n monitoring

# Перевірте, що все видалено
kubectl get all -n monitoring | grep prometheus

# Створіть новий deployment через Portainer або kubectl
kubectl apply -f prometheus/deployment.yaml
```

## Рекомендований порядок дій

1. **Видаліть всі старі Prometheus deployment через Portainer:**
   - Kubernetes → Applications → monitoring
   - Виберіть всі prometheus applications
   - Натисніть Remove

2. **Перевірте, що все видалено:**
   ```bash
   kubectl get deployments -n monitoring
   kubectl get pods -n monitoring
   ```

3. **Створіть новий deployment:**
   - Через Portainer: Kubernetes → Applications → monitoring → Create from code
   - Скопіюйте вміст `prometheus/deployment.yaml`
   - Або використайте `deployment-fix-permissions.yaml` якщо потрібні root права

4. **Перевірте статус:**
   ```bash
   kubectl get deployment prometheus -n monitoring
   kubectl get pods -n monitoring -l app=prometheus
   kubectl logs -n monitoring -l app=prometheus
   ```

## Важливо

⚠️ **Перед видаленням переконайтеся:**
- Видаляєте тільки зайві/непрацюючі deployment
- Залиште тільки один працюючий deployment
- Дані в PVC не будуть втрачені при видаленні deployment (тільки при видаленні PVC)

## Після очищення

Після видалення зайвих deployment:
1. Створіть новий deployment через Portainer
2. Використайте оновлений `prometheus/deployment.yaml` або `deployment-fix-permissions.yaml`
3. Перевірте, що pod запускається без помилок
