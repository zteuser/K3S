# Control-plane / master ноди як worker: розміщення подів

**Так** — control-plane (master) ноди можуть додатково виконувати роль worker і приймати поди. За замовчуванням k3s ставить на них **taint**, через який звичайні поди туди **не плануються**. Щоб дозволити планування подів на control-plane, є два підходи.

---

## Як це працює за замовчуванням

На control-plane нодах k3s додає taint:

- `node-role.kubernetes.io/control-plane:NoSchedule`
- або (старіша мітка) `node-role.kubernetes.io/master:NoSchedule`

Через це scheduler **не ставить** звичайні поди на ці ноди. Частина подів (наприклад node-exporter, promtail) уже має **tolerations** для цих taint — тому вони можуть працювати на master.

---

## Варіант A: Зняти taint на control-plane нодах

Якщо потрібно, щоб **будь-які** поди могли плануватися на control-plane (як на звичайні worker-ноди):

```bash
# Для кожної control-plane ноди (підставте імена: macmini7, beelinkeqr5 тощо)
kubectl taint nodes macmini7 node-role.kubernetes.io/control-plane:NoSchedule-
kubectl taint nodes beelinkeqr5 node-role.kubernetes.io/control-plane:NoSchedule-
```

Якщо є старий taint `master`:

```bash
kubectl taint nodes macmini7 node-role.kubernetes.io/master:NoSchedule-
kubectl taint nodes beelinkeqr5 node-role.kubernetes.io/master:NoSchedule-
```

Після цього scheduler зможе розміщувати звичайні поди на цих нодах. Перевірка:

```bash
kubectl describe node macmini7 | grep -A5 Taints
# Після зняття taint — Taints: <none> або порожньо
```

**Мінус:** поди будуть споживати CPU/пам’ять на control-plane; при великому навантаженні це може впливати на стабільність API/etcd. У невеликих кластерах це часто прийнятно.

---

## Варіант B: Додати tolerations лише потрібним workload’ам

Якщо потрібно, щоб на control-plane планувалися **лише окремі** поди (наприклад один Deployment), taint не знімайте — додайте в манифест пода/Deployment **tolerations**:

```yaml
spec:
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Equal
      value: "true"
      effect: NoSchedule
    # якщо є старий taint master:
    - key: node-role.kubernetes.io/master
      operator: Equal
      value: "true"
      effect: NoSchedule
```

Тоді цей workload зможе плануватися на control-plane, решта — ні. Так зроблено, наприклад, у `manifests/monitoring/node-exporter/daemonset.yaml` та `manifests/monitoring/promtail/daemonset.yaml`.

---

## Підсумок

| Мета | Дія |
|------|-----|
| Усі поди можуть йти на control-plane | Зняти taint: `kubectl taint nodes <NAME> node-role.kubernetes.io/control-plane:NoSchedule-` |
| Лише окремі поди на control-plane | Залишити taint, додати `tolerations` у манифест потрібного workload’у |

Після зняття taint (варіант A) control-plane ноди поводяться як worker щодо планування подів; роль control-plane (API, etcd, scheduler) при цьому не змінюється.
