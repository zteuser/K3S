# План збору логів k3s кластера

План централізованого збору логів від **процесів k3s** (control-plane, ноди) та від **активних контейнерів** (pods).

---

## 1. Джерела логів

### 1.1 Процеси k3s (системні сервіси)

| Джерело | Опис | Де знаходиться |
|--------|------|----------------|
| **k3s server** | API server, scheduler, controller-manager, etcd | `journalctl -u k3s` або service log |
| **k3s agent** | kubelet, kube-proxy, containerd | `journalctl -u k3s-agent` (на worker нодах) |
| **containerd** | CRI, логи контейнерів на рівні runtime | Часто разом з k3s або окремий unit |
| **Traefik** | Ingress (якщо вбудований) | Pod у `kube-system`, логи через `kubectl logs` |

На нодах з systemd логи k3s зазвичай пишуться в **journald**. Щоб їх збирати з кластера, потрібен агент на кожному вузлі, який читає журнал (наприклад, з `/var/log/journal` або через сокет journal).

### 1.2 Логи активних контейнерів (pods)

| Джерело | Опис |
|--------|------|
| **stdout/stderr подів** | Все, що контейнери пишуть у stdout/stderr, kubelet зберігає у файли на ноді |
| **Шлях на ноді** | `/var/log/pods/<namespace>_<pod>_<uid>/<container>/` — симлінки на контейнерні лог-файли (залежить від CRI; у k3s — containerd) |

Ці файли автоматично ротуються kubelet (наприклад, за розміром/кількістю файлів). Агент збору логів повинен читати саме ці файли з хоста (hostPath), щоб бачити всі контейнери на ноді.

---

## 2. Архітектура рішення (рекомендована)

Використання **Loki + Promtail** узгоджується з уже розгорнутим стеком **Grafana + Prometheus** у вашому кластері.

```
┌─────────────────────────────────────────────────────────────────┐
│  Ноди k3s                                                        │
│  ┌─────────────────────┐  ┌─────────────────────┐              │
│  │ Promtail (DaemonSet) │  │ Promtail             │   ...        │
│  │ - journald (k3s)     │  │ - journald           │              │
│  │ - /var/log/pods/*    │  │ - /var/log/pods/*    │              │
│  └──────────┬──────────┘  └──────────┬──────────┘              │
└─────────────┼─────────────────────────┼─────────────────────────┘
              │ push logs               │
              ▼                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Namespace: monitoring (або logging)                             │
│  ┌─────────────────────┐  ┌─────────────────────┐                │
│  │ Loki                │  │ Grafana (вже є)     │                │
│  │ зберігання + query  │  │ datasource: Loki    │                │
│  └─────────────────────┘  └─────────────────────┘                │
└─────────────────────────────────────────────────────────────────┘
```

- **Promtail** — DaemonSet на кожній ноді: читає з хоста journald і `/var/log/pods`, додає мітки (namespace, pod, container, node), відправляє в Loki.
- **Loki** — один Deployment + Storage: приймає логи, індексує по мітках, віддає по запитах.
- **Grafana** — вже є; додати datasource Loki для пошуку та перегляду логів.

Переваги:

- Один інтерфейс (Grafana) для метрик і логів.
- Мінімальні зміни в існуючих манифестах (лише нові об’єкти + datasource Loki).
- Promtail легкий, підходить для малих кластерів.

---

## 3. Що саме збирати

### 3.1 Обов’язково

- **Логи контейнерів:** усі namespaces (або виключити лише системні за потреби) — через збір з `/var/log/pods` на кожній ноді.
- **Логи k3s (journald):** unit `k3s` (server) та на agent-нодах `k3s-agent` (якщо є окремий unit), щоб мати логи control-plane та kubelet/containerd.

### 3.2 Опціонально

- **Traefik:** логи вже є в подах у `kube-system` — покриваються збором з `/var/log/pods`.
- **Інші systemd-сервіси** на нодах (наприклад, мережеві або дискові) — додати в конфіг Promtail при потребі.

---

## 4. Поетапний план впровадження

### Фаза 1: Підготовка

1. **Namespace для Loki:** `monitoring` (Loki деплоїться поруч з Prometheus/Grafana).
2. **Зберігання для Loki:** окремий PVC `loki-data`, **10 ГіБ**, StorageClass **ocfs2-shared** (файл `storageclass-ocfs2.yaml`). Манифести: `manifests/monitoring/loki/pvc.yaml`, `configmap.yaml`, `deployment.yaml`, `service.yaml`; додано в `manifests/monitoring/kustomization.yaml`. Якщо використовується no-provisioner (OCFS2), перед apply потрібно створити PV на 10 ГіБ або мати dynamic provisioning для цього storage class.

3. Перевірити на нодах:
   - чи є journald і де зберігається журнал: `ls -la /var/log/journal` або `journalctl -u k3s --no-pager -n 5`;
   - чи є лог-файли подів: `ls /var/log/pods` (або аналогічний шлях на вашому k3s).

### Фаза 2: Loki

1. Додати манифести:
   - Deployment Loki (одна репліка для простоти).
   - Service (ClusterIP).
   - PVC для Loki: `loki-data`, 10 ГіБ, `ocfs2-shared` (див. `manifests/monitoring/loki/pvc.yaml`).
2. Конфіг Loki: режим `single binary`, retention (скільки днів зберігати логи), обмеження по розміру/швидкості прийому при потребі.

### Фаза 3: Promtail (DaemonSet)

1. Створити конфіг Promtail у двох частинах:
   - **journald:** позиція з `/var/log/journal` або через сокет; фільтр по `_SYSTEMD_UNIT=k3s.service` (та `k3s-agent.service` на worker нодах).
   - **positions:** файл на hostPath, щоб після рестарту подів не дублювати логи.
2. **Контейнери:** зчитування з `/var/log/pods` на хосту (hostPath), парсинг шляху для міток namespace/pod/container.
3. RBAC: ServiceAccount, ClusterRole (доступ до pod/node метаданих для обогачення логів — опціонально), ClusterRoleBinding.
4. DaemonSet: монтування hostPath для `/var/log`, `/var/log/pods`, journal (або сокет), конфіг з ConfigMap, URL Loki (наприклад, `http://loki:3100`).

### Фаза 4: Інтеграція з Grafana

1. Додати в Grafana datasource **Loki** (URL внутрішнього сервісу Loki, наприклад `http://loki.monitoring.svc.cluster.local:3100` або в тому ж namespace — `http://loki:3100`).
2. Оновити манифест `configmap-datasources.yaml` (або provision datasource іншим способом), щоб після деплою Grafana вже бачила Loki.
3. У Grafana: Explore → вибрати Loki, перевірити логи по namespace/pod/container та по unit k3s.

### Фаза 5: Перевірка та retention

1. Переконатися, що логи з подів з’являються в Loki (фільтр по namespace/app).
2. Переконатися, що логи k3s з journald з’являються (фільтр по `job=journal` або відповідній мітці unit).
3. Налаштувати retention у Loki під доступний диск та політику зберігання.

---

## 5. Альтернативи

| Рішення | Плюси | Мінуси |
|--------|-------|--------|
| **Loki + Promtail** | Готові Helm-чарти, інтеграція з Grafana, легкий Loki | Потрібно монтувати hostPath та (часто) journal |
| **Fluent Bit → Loki** | Менший за Promtail, підходить для edge | Більше налаштувань під Loki |
| **Vector → Loki** | Гнучкість, одна бінарка | Менше готових прикладів під k3s |
| **Fluentd** | Дуже гнучкий | Важкий, більше ресурсів |

Рекомендація для вашого стеку: **Loki + Promtail** і далі при потребі замінити Promtail на Fluent Bit або Vector.

---

## 6. Важливі моменти для k3s

- **Шлях до логів подів:** у k3s з containerd це зазвичай `/var/log/pods`. Можна перевірити на ноді:  
  `ls /var/log/pods` або в описі поду — поле `status.containerStatuses[].containerID`.
- **Journal:** якщо k3s встановлений як service, логи за замовчуванням у journald. Для читання з пода потрібно монтувати `/var/log/journal` (або `Directory=/var/log/journal` відповідно до вашої структури) в read-only.
- **Безпека:** Promtail з hostPath та доступом до journal — виконувати з мінімально необхідними правами; можливо обмежити через SecurityContext (readOnlyRootFilesystem де можливо, drop capabilities).
- **Ресурси:** Loki — орієнтовно 256–512 Mi RAM; Promtail — 50–100 Mi на ноду.

---

## 7. Наступні кроки

1. Підтвердити namespace та storage для Loki.
2. Додати в репозиторій манифести: Loki (Deployment, Service, PVC), Promtail (ConfigMap, DaemonSet, RBAC).
3. Оновити Grafana datasources (ConfigMap або Helm values), задеплоїти.
4. Після деплою — перевірити логи контейнерів і k3s у Grafana (Explore → Loki) та при потребі допрацювати retention і фільтри в Promtail.

Якщо потрібно, можу підготувати конкретні YAML-манифести для Loki та Promtail під ваш `manifests/` та існуючий namespace/storage.
