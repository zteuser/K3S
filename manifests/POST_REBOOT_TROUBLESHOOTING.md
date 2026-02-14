# Траблшутінг після не запланованого рестарту (наприклад Macmini7)

Після рестарту хоста можуть з’явитися помилки в логах k3s та rsyslog. Нижче — типові симптоми та дії.

---

## 1. APIService v1beta1.metrics.k8s.io — 503 Service Unavailable

**Симптоми в логах k3s:**
```
Error updating APIService "v1beta1.metrics.k8s.io" with err: failed to download v1beta1.metrics.k8s.io: failed to retrieve openAPI spec, http error: ResponseCode: 503, Body: service unavailable
```
і попередження: `no RequestInfo found in the context`.

**Причина:** Після рестарту **metrics-server** (вбудований у k3s) ще не готовий. API server періодично перевіряє APIService і отримує 503, поки metrics-server не відповість.

**Важливо:** У k3s metrics-server часто працює **всередині процесу k3s** (не окремий под). Тому `kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server` може повертати "No resources found" — це нормально. Орієнтуйтеся на **APIService**: якщо `kubectl get apiservice v1beta1.metrics.k8s.io` показує **AVAILABLE: True**, метрики працюють, помилки 503 у логах були тимчасовими.

**Що робити:**

1. Перевірити APIService (головний індикатор):

   ```bash
   kubectl get apiservice v1beta1.metrics.k8s.io -o wide
   # AVAILABLE = True → усе ок, 503 були після рестарту тимчасово.
   ```

2. Якщо є окремий Deployment metrics-server (не вбудований у k3s):

   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server
   kubectl get deployment -n kube-system metrics-server 2>/dev/null || true
   ```
   Якщо под є, але не Ready — `kubectl describe pod ...` та `kubectl logs ...` для діагностики. Перезапуск: `kubectl rollout restart deployment/metrics-server -n kube-system`.

3. Якщо через 5–10 хвилин після старту k3s `AVAILABLE` так і залишається `False`, перевірте мережу, DNS і доступність kubelet на нодах (metrics-server ходить на kubelet :10250 за метриками).

---

## 2. rsyslog: action 'action-2-builtin:omfile' suspended

**Симптом:**
```
rsyslogd: action 'action-2-builtin:omfile' suspended (module 'builtin:omfile'), retry 0. ...
action 'action-2-builtin:omfile' resumed (module 'builtin:omfile')
```
Цикл suspend → resume повторюється кожні ~30 с.

**Причина:** rsyslog не може вчасно записати в файл: диск заповнений, немає прав, ФС ще read-only, **або** тимчасово повільний I/O / мережева ФС. Якщо він одразу "resumed", це часто **інтермітентна** помилка (навантаження на диск після рестарту, NFS/remote log тощо).

**Що робити:**

1. Перевірити місце та права (якщо диск заповнений або немає прав — виправити):

   ```bash
   df -h
   ls -la /var/log
   ```

2. Дізнатися, **куди** пише action-2. Номер action (1, 2, …) rsyslog присвоює за порядком правил у конфігу; перегляньте усі файлові правила:

   ```bash
   grep -r "omfile\|\.File\|action" /etc/rsyslog.conf /etc/rsyslog.d/ 2>/dev/null
   cat /etc/rsyslog.conf
   cat /etc/rsyslog.d/45-frr.conf   # якщо є — FRR (routing) логи, часто action-2
   ```
   Якщо є `45-frr.conf` з `:omfile:$frr_log` — це логи FRR; перевірте, куди вказує `$frr_log`, чи існує каталог і чи є права на запис. Після рестарту FRR може давати багато повідомлень одразу, тоді suspend/resume тимчасові.

3. Якщо логи пишуться на **мережевий** том (NFS, syslog-сервер) — після рестарту він може бути тимчасово недоступний або повільний; suspend/resume тоді нормальний поки мережа стабілізується.

4. Увімкнути детальніший лог rsyslog (якщо потрібна точна причина):

   ```bash
   # в /etc/rsyslog.conf або в файлі в /etc/rsyslog.d/ додати (або тимчасово):
   # global(debug="on")
   # Потім: sudo systemctl restart rsyslog і переглянути journalctl -u rsyslog -f
   ```

5. Якщо цикл suspend/resume не заважає роботі (логи в основному пишуться), можна лишити як є або після стабілізації системи перезапустити rsyslog:

   ```bash
   sudo systemctl restart rsyslog
   ```

---

## 3. Швидкий чеклист після рестарту ноди

| Перевірка | Команда |
| --------- | -------- |
| Ноди | `kubectl get nodes -o wide` |
| Системні пода на Macmini7 | `kubectl get pods -n kube-system -o wide` |
| Metrics-server | `kubectl get apiservice v1beta1.metrics.k8s.io` |
| Логи k3s | `journalctl -u k3s -b -n 100 --no-pager` |
| Rsyslog | `journalctl -u rsyslog -b -n 50 --no-pager` |

Помилки 503 для `v1beta1.metrics.k8s.io` та `no RequestInfo found in the context` зазвичай зникають самі через кілька хвилин після того, як metrics-server стане Ready.
