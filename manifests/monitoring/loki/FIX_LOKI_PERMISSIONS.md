# Виправлення Loki: permission denied у tsdb-shipper-*

## Проблема

Под Loki в стані **CrashLoopBackOff**, у логах:

```
unlinkat /loki/tsdb-shipper-active/scratch/filesystem_2020-10-24: permission denied
removing tsdb scratch dir
error initialising module: store
```

або раніше:

```
open /loki/tsdb-shipper-cache/...: permission denied
remove /loki/tsdb-shipper-cache/...: permission denied
```

Loki запускається під користувачем **10001** (runAsUser: 10001). Директорії `tsdb-shipper-cache` та **tsdb-shipper-active/scratch** мають бути доступні для запису/видалення; якщо вони створені root або з неправильними правами, контейнер падає при старті.

## Рішення

### Варіант 1: Job для виправлення прав (рекомендовано)

Одноразовий Job монтує той самий PVC, виконує `chown -R 10001:10001 /loki` під root, після чого потрібно перезапустити под Loki.

**Кроки (з будь-якої ноди з kubectl):**

```bash
# 0. Якщо Job вже запускали раніше — видалити його (іменований Job не оновлюється)
kubectl -n monitoring delete job loki-fix-permissions --ignore-not-found

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

---

## Readiness 503 та "entry too far behind"

### Readiness probe 503

Под у статусі Running, але в Events — **Readiness/Liveness probe failed: HTTP 503**. Це тимчасово під час старту: Loki повертає 200 на `/ready` лише після WAL recovery і приєднання до ring. У deployment задано **startupProbe** (60s + 40×15s ≈ 10 хв): доки вона не пройде, liveness і readiness не виконуються, тому події 503 від них під час старту не з’являються. Після успішного startup под стає Ready і далі обслуговує трафік.

### "entry too far behind"

У логах: `entry too far behind, oldest acceptable timestamp is: ... for stream {job="journal", nodename="macmini7", ...}`. Це **не** керується `reject_old_samples` / `reject_old_samples_max_age`. Вікно прийому старих записів для стриму = **max_chunk_age/2** (out-of-order window). Якщо стрим уже має новіші записи, вхідні записи старіші за (найновіший_запис − max_chunk_age/2) відхиляються.

У `configmap.yaml` задано `ingester.max_chunk_age: 24h` (вікно 12h), щоб приймати backlog після простою Loki або Promtail.

**Застосування оновлень і перезапуск Loki:**

```bash
# Застосувати ConfigMap і Deployment
kubectl apply -f manifests/monitoring/loki/configmap.yaml
kubectl apply -f manifests/monitoring/loki/deployment.yaml

# Перезапустити под, щоб підхопити новий config
kubectl -n monitoring delete pod -l app=loki

# Перевірити логи (помилки "entry too far behind" мають зменшитися після збільшення max_chunk_age)
kubectl -n monitoring logs -l app=loki -f --tail=100
```
