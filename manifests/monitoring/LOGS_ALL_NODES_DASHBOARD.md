# Логи з усіх нод у один дашборд (Loki + Promtail)

Щоб мати: **(1)** логи з усіх нод кластера, **(2)** логи від усіх подів, **(3)** один дашборд з фільтрами по ноді/поду/namespace — потрібно виконати два етапи.

---

## Етап 1: Promtail на всіх нодах

За замовчуванням Promtail запущений **лише на master-node** (через проблеми мережі на worker-нодах). Щоб збирати логи з усіх нод:

1. **Налаштуйте мережу** так, щоб поди на **кожній** ноді могли досягати:
   - Kubernetes API (10.43.0.1:443)
   - DNS/CoreDNS (10.43.0.10:53)
   - сервіс Loki (наприклад `loki.monitoring.svc.cluster.local:3100`)
   
   Детальні кроки: **`manifests/FIX_CLUSTERIP_ACCESS_FROM_ALL_NODES.md`** (firewall, маршрути, WireGuard allowed_ips тощо).

2. **Перевірте доступність** з worker-ноди (наприклад з пода в default):
   ```bash
   kubectl run test-curl --rm -it --restart=Never --image=curlimages/curl -- curl -s -o /dev/null -w "%{http_code}" http://loki.monitoring.svc.cluster.local:3100/ready
   ```
   Очікується код 200.

3. **Приберіть обмеження ноди** у Promtail DaemonSet, щоб він планувався на всіх нодах:
   - У файлі `manifests/monitoring/promtail/daemonset.yaml` закоментуйте або видаліть блок `nodeSelector`:
     ```yaml
     # nodeSelector:
     #   kubernetes.io/hostname: master-node
     ```
   - Застосуйте й перезапустіть поди:
     ```bash
     kubectl apply -f manifests/monitoring/promtail/daemonset.yaml
     kubectl -n monitoring delete pod -l app=promtail
     ```

4. Переконайтеся, що на кожній ноді є один под Promtail і без помилок у логах:
   ```bash
   kubectl -n monitoring get pods -l app=promtail -o wide
   kubectl -n monitoring logs -l app=promtail --tail=20
   ```

Після цього Loki отримуватиме логи з усіх нод (поди з `/var/log/pods` + systemd journal з кожної ноди).

---

## Етап 2: Дашборд «Cluster Logs» у Grafana

У репозиторії додано дашборд **Cluster Logs (Loki)** з фільтрами за **namespace**, **node**, **pod**.

- **Де знаходиться:** provisioned з ConfigMap (папка **SNMP**), назва **Cluster Logs (Loki)**.
- **Як відкрити:** Grafana → Dashboards → знайдіть «Cluster Logs» або «Loki».
- **Відображається:** вміст логових повідомлень (текст/JSON), без графіка загальної кількості.
- **Змінні (фільтри):**
  - **Severity** — рівень логу (All / debug / info / warn / error). Працює для рядків у форматі JSON з полем `level` (наприклад etcd, k3s).
  - **Namespace** — namespace подів (для journal — «journal»).
  - **Node** — нода (hostname).
  - **Pod** — ім’я пода.
- За замовчуванням усі фільтри — «All». Змініть їх, щоб звузити вибір за severity, нодою або подом.

Якщо дашборд не з’явився після деплою:

1. Перезапустіть Grafana, щоб він перечитав provisioning:
   ```bash
   kubectl -n monitoring rollout restart deployment/grafana
   ```
2. Або імпортуйте вручну: Dashboards → Import → Upload JSON file → виберіть `manifests/monitoring/grafana/dashboards/cluster-logs-loki.json`.

**Якщо панель «Logs (content)» показує «No data»:** перевірте, що у фільтрі **Datasource** обрано **Loki** (датасорс з `uid: loki` у provisioning). Переконайтеся, що Loki і Promtail поди в стані Running і що в **Explore → Loki** запит `{job=~"kubernetes-pods|journal"}` за останню годину повертає логи. Якщо датасорс був створений без `uid`, перезапустіть Grafana після оновлення `configmap-datasources.yaml` (Loki з `uid: loki`).

**Якщо в Inspect панелі помилка «Status: 500 … parse error … unexpected IDENTIFIER»:** це викликав складний pipeline у змінній Severity (regexp з backticks). У дашборді з нього прибрано підстановку `${severity_pipeline}` у запит — тепер використовується лише селектор за лейблами. Фільтр Severity в UI залишено; фільтрацію по level можна робити через пошук у панелі логів.

---

## Підсумок

| Що потрібно | Що зробити |
|-------------|------------|
| Логи з усіх нод | Етап 1: мережа + прибрати nodeSelector у Promtail |
| Логи від усіх подів | Promtail уже збирає всі поди з кожної ноди (job `kubernetes-pods`) + journal |
| Один дашборд з фільтрами | Етап 2: дашборд «Cluster Logs (Loki)» з змінними namespace / node / pod |

Мітки в Loki: `job` (kubernetes-pods | journal), `namespace`, `node`, `pod`, `container`; для journal також `unit`, `nodename`.
