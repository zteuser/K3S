# Як перезапустити Prometheus через Portainer UI

## Спосіб 1: Через Deployment (рекомендовано)

1. **Перейдіть до Deployment:**
   - Kubernetes → Applications → monitoring
   - Знайдіть **Deployment** в списку ресурсів (не Pod)
   - Натисніть на **prometheus**

2. **Перезапустіть через Deployment:**
   - В деталях Deployment знайдіть кнопку **"Restart"** або **"Recreate"**
   - Або знайдіть меню з трьома крапками (⋮) → **Restart**

## Спосіб 2: Видалити Pod (Deployment автоматично створить новий)

1. **Знайдіть Pod:**
   - Kubernetes → Applications → monitoring
   - Application containers → знайдіть pod `prometheus-...`

2. **Видаліть Pod:**
   - Натисніть на pod
   - В деталях pod знайдіть кнопку **"Delete"** або **"Remove"**
   - Підтвердіть видалення

3. **Deployment автоматично створить новий pod** з новою конфігурацією

## Спосіб 3: Через YAML Editor (змінити deployment)

1. **Відкрийте Deployment:**
   - Kubernetes → Applications → monitoring
   - Deployment → prometheus

2. **Перейдіть до вкладки YAML:**
   - Натисніть вкладку **"<> YAML"**

3. **Додайте/змініть annotation для перезапуску:**
   - Знайдіть секцію `spec:` → `template:` → `metadata:` → `annotations:`
   - Додайте або змініть:
     ```yaml
     annotations:
       kubectl.kubernetes.io/restartedAt: "2026-01-14T15:30:00Z"
     ```
   - Натисніть **"Update Deployment"**

## Спосіб 4: Через Console (вручну)

1. **Відкрийте Console:**
   - Application containers → prometheus pod
   - Натисніть **"Console"**

2. **Відправте сигнал для перезапуску:**
   - Або просто закрийте консоль - pod перезапуститься

## Найпростіший спосіб: Видалити Pod

**Рекомендований спосіб:**

1. Kubernetes → Applications → monitoring
2. Application containers
3. Знайдіть pod `prometheus-85bb6fdfc5-k948v` (або подібний)
4. Натисніть на pod
5. В деталях pod знайдіть кнопку **"Delete"** / **"Remove"**
6. Підтвердіть видалення

Deployment автоматично створить новий pod, який завантажить оновлену конфігурацію з ConfigMap.

## Перевірка після перезапуску

1. **Перевірте статус pod:**
   - Application containers → prometheus
   - Статус має бути **Running**

2. **Перевірте логи:**
   - Натисніть **"Logs"** на prometheus pod
   - Має бути без помилок типу "Error loading config"

3. **Перевірте targets в Prometheus UI:**
   - Відкрийте `http://<node-ip>:30001/targets`
   - Job `snmp-routers` має з'явитися з 2 targets

## Якщо немає кнопки Delete

Якщо в Portainer немає кнопки Delete для pod:

1. **Спробуйте через Deployment:**
   - Знайдіть Deployment prometheus
   - Можливо там є кнопка Restart або Recreate

2. **Або через YAML:**
   - Відкрийте Deployment в YAML view
   - Зробіть будь-яку незначну зміну (наприклад, додайте annotation)
   - Це викличе перезапуск

3. **Або налаштуйте kubectl:**
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   kubectl delete pods -n monitoring -l app=prometheus
   ```
