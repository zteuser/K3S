# Виправлення Loki: permission denied у tsdb-shipper-cache

## Проблема

Под Loki в стані **CrashLoopBackOff**, у логах:

```
open /loki/tsdb-shipper-cache/index_20484/fake/...tsdb: permission denied
remove /loki/tsdb-shipper-cache/...: permission denied
error initialising module: store
```

Loki запускається під користувачем **10001** (runAsUser: 10001). Файли/директорії в `/loki` (зокрема `tsdb-shipper-cache`) мають неправильного власника (наприклад root), тому контейнер не може їх читати або видаляти.

## Рішення

### Варіант 1: Job для виправлення прав (рекомендовано)

Одноразовий Job монтує той самий PVC, виконує `chown -R 10001:10001 /loki` під root, після чого потрібно перезапустити под Loki.

**Кроки (з будь-якої ноди з kubectl):**

```bash
# 1. Запустити Job (має заплануватися на master-node, де крутиться Loki)
kubectl apply -f manifests/monitoring/loki/job-fix-permissions.yaml

# 2. Дочекатися завершення Job (до 2 хв)
kubectl -n monitoring wait --for=condition=complete job/loki-fix-permissions --timeout=120s

# 3. Перезапустити Loki (щоб під підхопив оновлені права)
kubectl -n monitoring delete pod -l app=loki
```

Через 1–2 хв под Loki має перейти в **Running**. Перевірка:

```bash
kubectl -n monitoring get pods -l app=loki
kubectl -n monitoring logs -l app=loki --tail=30
```

Якщо Job не може заплануватися (наприклад PVC зайнятий або nodeSelector не підходить), спочатку зупиніть Loki, потім запустіть Job:

```bash
kubectl -n monitoring scale deployment loki --replicas=0
kubectl apply -f manifests/monitoring/loki/job-fix-permissions.yaml
kubectl -n monitoring wait --for=condition=complete job/loki-fix-permissions --timeout=120s
kubectl -n monitoring scale deployment loki --replicas=1
```

### Варіант 2: Виправлення на ноді (hostPath /sharedata1/loki)

Якщо volume Loki — це **hostPath** `/sharedata1/loki` на ноді **master-node**, можна виправити права безпосередньо на ноді:

**На master-node (SSH або консоль):**

```bash
sudo chown -R 10001:10001 /sharedata1/loki
sudo chmod -R 755 /sharedata1/loki
```

Потім перезапустити под Loki:

```bash
kubectl -n monitoring delete pod -l app=loki
```

### Варіант 3: InitContainer у Deployment

У `loki/deployment.yaml` вже є initContainer **fix-loki-permissions** (chown 10001:10001). Якщо він не спрацьовує (наприклад через Pod Security Policy або помилку при chown), використайте Варіант 1 або 2. Після успішного виправлення правами через Job або на ноді под має стабільно стартувати; initContainer далі підтримуватиме права при наступних перезапусках.

## Підсумок

| Крок | Дія |
|------|-----|
| 1 | `kubectl apply -f manifests/monitoring/loki/job-fix-permissions.yaml` |
| 2 | `kubectl -n monitoring wait --for=condition=complete job/loki-fix-permissions --timeout=120s` |
| 3 | `kubectl -n monitoring delete pod -l app=loki` |
| 4 | Перевірити: `kubectl -n monitoring get pods -l app=loki` — статус Running |

Після цього Loki має запускатися без "permission denied" у tsdb-shipper-cache.
