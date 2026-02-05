# beelinkeqr5 не з’являється в Grafana (Nodename / Node Exporter)

**Симптоми:** у дашборді Grafana «Node Exporter Full» у випадаючому списку **Nodename** є тільки macmini7, master-node, work-node — **beelinkeqr5 відсутній**. При цьому под node-exporter на beelinkeqr5 у статусі Running і без помилок у логах.

**Причина:** список Nodename будується з метрик Prometheus (job `node-exporter`). Якщо Prometheus не може успішно скрейпити node-exporter на beelinkeqr5, метрик з цієї ноди немає — тому beelinkeqr5 не потрапляє в список.

---

## Чеклист

### 1. IP beelinkeqr5 збігається з конфігом Prometheus

Node-exporter працює з `hostNetwork: true`, тому Pod IP = InternalIP ноди. Перевірте поточну IP beelinkeqr5:

```bash
kubectl get nodes -o wide | grep beelinkeqr5
# або
kubectl get pods -n monitoring -l app=node-exporter -o wide | grep beelinkeqr5
```

У `manifests/monitoring/prometheus/configmap.yaml` у job’ах **node-exporter** і **kubernetes-nodes** для beelinkeqr5 має бути саме ця IP (порти 9100 та 10250). Зараз у репо вказано **192.168.1.19** — якщо у вас інша (наприклад 192.168.2.95), змініть у configmap і застосуйте (крок 2).

### 2. Застосувати ConfigMap і перезапустити Prometheus

Після будь-якої зміни IP beelinkeqr5 у configmap:

```bash
kubectl apply -f manifests/monitoring/prometheus/configmap.yaml
kubectl rollout restart deployment prometheus -n monitoring
```

Зачекайте 1–2 хвилини, поки под перезапуститься і підхопить новий конфіг.

### 3. Фаєрвол на beelinkeqr5: дозволити 9100 і 10250

Prometheus (под на master-node) підключається до beelinkeqr5 по портах **9100** (node-exporter) і **10250** (kubelet). Якщо на **beelinkeqr5** вхід на ці порти заблоковано, буде таймаут («context deadline exceeded») і метрик не буде.

На ноді **beelinkeqr5** виконайте (або запустіть `apply-fix-dns-api.sh` на beelinkeqr5 — там уже є блок для цих портів):

```bash
sudo iptables -I INPUT 1 -p tcp --dport 10250 -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 10250 -s 192.168.0.0/16 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 9100 -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 9100 -s 192.168.0.0/16 -j ACCEPT
sudo netfilter-persistent save
```

Детальніше: `manifests/portainer/FIX_PORTAINER_DNS_API_TIMEOUT.md`, розділ **5.1**.

### 4. Перевірка: чи Prometheus бачить target

Відкрийте Prometheus UI → **Status** → **Targets** (наприклад `http://prometheus.monitoring.lan/targets` або `http://<node-ip>:30001/targets`).

- У job **node-exporter** має бути target з IP beelinkeqr5 (наприклад `192.168.1.19:9100`) у стані **UP**.
- Якщо **DOWN** і помилка «context deadline exceeded» — фаєрвол або мережа (крок 3; перевірте також маршрути з ноди, де крутиться Prometheus, до IP beelinkeqr5).

### 5. Перевірка з пода Prometheus

З машини з доступом до кластера:

```bash
PROM_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n monitoring "$PROM_POD" -- wget -qO- --timeout=5 http://192.168.1.19:9100/metrics 2>&1 | head -5
```

Якщо тут таймаут — проблема мережа/фаєрвол між Prometheus і beelinkeqr5. Якщо бачите текст метрик — scrape має працювати; перезапустіть Prometheus і перевірте Targets ще раз.

---

## Підсумок

| Крок | Дія |
|------|-----|
| 1 | Переконатися, що в configmap для beelinkeqr5 вказана поточна IP (192.168.1.19 або актуальна з `kubectl get nodes -o wide`) |
| 2 | `kubectl apply -f .../prometheus/configmap.yaml` і `kubectl rollout restart deployment prometheus -n monitoring` |
| 3 | На beelinkeqr5: iptables дозволити вхід на 10250 і 9100 з 10.0.0.0/8 та 192.168.0.0/16 |
| 4 | У Prometheus → Targets перевірити, що node-exporter для beelinkeqr5 **UP** |
| 5 | У Grafana оновити дашборд / змінну Nodename — **beelinkeqr5** має з’явитися в списку |

Помилка node_exporter у логах `Failed to open directory ... /run/udev/data` (udev device properties) не блокує роботу; основний scrape метрик працює.
