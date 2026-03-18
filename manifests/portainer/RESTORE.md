# Відновлення Portainer

Якщо Portainer перестав працювати (под видалено, namespace очищено, або після налаштування ingress для monitoring.lan сервіси перестали відповідати), відновити його можна так.

## Передумови

- **PVC** використовує `storageClassName: ocfs2-shared` та `volumeName: pv-sharedata2`. Переконайтеся, що PV існує і доступний на нодах (master-node/work-node).
- Для доступу через **Cilium Ingress** (http://portainer.lan/) Ingress має `ingressClassName: cilium` — у поточних манифестах k3s вже задано.

## Швидке відновлення (новий k8s, спочатку Portainer)

З кореня репо **k3s**:

```bash
cd /Users/omartyny/WORK/k3s
./manifests/scripts/restore-portainer.sh
```

Опції: `--no-agent` (не деплоїти agent), `--dry-run` (лише показати команди).

## Відновлення вручну (kustomize)

```bash
cd /Users/omartyny/WORK/k3s
kubectl apply -k manifests/portainer/
```

Це створить/оновить: namespace, ServiceAccount, ClusterRole, ClusterRoleBinding, PVC, Deployment, Service, Ingress (`ingressClassName: cilium`), CiliumNetworkPolicy.

## Ingress і Cilium

У манифестах k3s Portainer Ingress вже має `ingressClassName: cilium`. Після відновлення (`kubectl apply -k manifests/portainer/`) Cilium підхопить правило для portainer.lan. Якщо використовуєте манифести з репо **K8S**: `kubectl apply -f /Users/omartyny/WORK/K8S/manifests/ingress/portainer.yaml`

## Перевірка

```bash
kubectl get pods -n portainer
kubectl get svc -n portainer
kubectl get ingress -n portainer
```

Якщо под у стані `Pending` — перевірте PVC і PV (`kubectl get pvc -n portainer`, `kubectl describe pvc portainer-data -n portainer`).  
Доступ: **http://portainer.lan/** (якщо Cilium Ingress на порту 80) або **http://\<node-IP\>:30900** (NodePort).

**Якщо в браузері:** `upstream connect error or disconnect/reset before headers. reset reason: connection timeout` — Cilium Ingress не може досягти пода Portainer через default-deny. У `networkpolicy-portainer-to-agent.yaml` додано політику **allow-portainer-ingress-ui** (ingress на порти 9000, 9443 від host/world/cluster). Застосуйте: `kubectl apply -f manifests/portainer/networkpolicy-portainer-to-agent.yaml`.

---

## "Unable to login" — скидання пароля адміна

Якщо при вході з логіном **admin** з’являється **Unable to login**, пароль не підходить (наприклад, після відновлення з іншого кластера або зміни PVC). Скинути пароль офіційним helper-ом:

1. Зупинити Portainer (щоб PVC був вільний для монтування):
   ```bash
   kubectl scale deploy portainer --replicas=0 -n portainer
   ```

2. Запустити Job скидання пароля:
   ```bash
   kubectl apply -f /Users/omartyny/WORK/k3s/manifests/portainer/job-reset-admin-password.yaml
   ```

3. Дочекатися завершення і взяти новий пароль з логів:
   ```bash
   kubectl logs -f job/portainer-reset-admin -n portainer
   ```
   У виводі буде рядок на кшталт: `Use the following password to login: <новий_пароль>`.

4. Знову запустити Portainer:
   ```bash
   kubectl scale deploy portainer --replicas=1 -n portainer
   ```

5. (Опційно) Видалити Job:
   ```bash
   kubectl delete job portainer-reset-admin -n portainer
   ```

Увійдіть у UI з **admin** і паролем із кроку 3. Манифест Job: `manifests/portainer/job-reset-admin-password.yaml`.

**Якщо з новим паролем все одно "Unable to login":** згенерований пароль містить спецсимволи (`[ ] $ < >`), які можуть змінюватися при копіюванні або в полі вводу. У `job-reset-admin-password.yaml` додано `args: ["--password=PortainerAdmin1"]` — виконайте кроки 1–4 ще раз, потім увійдіть з паролем **PortainerAdmin1**. Після входу змініть пароль у UI (User settings → Password). Також спробуйте: вимкніть автозаповнення пароля у полі, відкрийте сторінку в режимі інкогніто або очистіть cookies для portainer.lan.

---

## Сторінка відкривається, але «local is unreachable» / немає доступу до кластера

Якщо UI Portainer завантажується, а середовище **local** у стані **Down** або **Failed loading environment — local is unreachable**, зробіть таке.

### 1. Переконатися, що RBAC застосовано

Portainer підключається до API кластера через ServiceAccount. Перевірте:

```bash
kubectl get clusterrolebinding portainer
kubectl get sa portainer -n portainer
kubectl get clusterrole portainer
```

Якщо чогось немає — застосуйте знову з репо k3s:

```bash
kubectl apply -f /Users/omartyny/WORK/k3s/manifests/portainer/serviceaccount.yaml
```

### 2. Перезапустити под Portainer

Іноді після відновлення под потрібен рестарт, щоб він підхопив поточний in-cluster endpoint:

```bash
kubectl rollout restart deployment/portainer -n portainer
kubectl rollout status deployment/portainer -n portainer
```

### 3. Перепідключити середовище «local» в UI

У /data на PVC могло зберегтися старе посилання на API (інший кластер або старий адрес). Тоді варто оновити або знову додати локальне середовище:

- У Portainer: **Environments** → клік по середовищу **local** → **Edit** (іконка олівця).
- Вказати тип **Kubernetes** і вибрати **Use the internal Kubernetes environment** (або **Local** / in-cluster), щоб використовувався поточний кластер, а не збережена URL.
- Зберегти. Або видалити середовище **local** і додати нове: **Add environment** → **Kubernetes** → **Local** (environment running Portainer).

### 4. Перевірити доступ поду до API з кластера

Якщо далі «unreachable» — перевірте, чи под бачить API:

```bash
kubectl exec -n portainer deploy/portainer -- wget -qO- --no-check-certificate --timeout=5 https://kubernetes.default.svc/healthz 2>&1 || true
```

Якщо помилка `no such host` — проблема з DNS у кластері. Якщо таймаут — мережева політика або маршрутизація до API server.

---

## Agent: "bad address" / DNS не резолвить portainer-agent

Якщо з подів у namespace `portainer` не резолвиться `portainer-agent.portainer.svc.cluster.local` (wget/nslookup: bad address), у UI можна вказати **ClusterIP** сервісу замість імені — він стабільний.

Отримати IP і вказати в Environment URL:
```bash
kubectl get svc -n portainer portainer-agent -o jsonpath='{.spec.clusterIP}'
```
У полі **Environment URL** введіть: `ОТРИМАНИЙ_IP:9001` (наприклад `10.108.133.105:9001`).

Перевірка доступності (образ Portainer не має wget — використовуйте curl або debug-под). З пода Portainer:
```bash
kubectl exec -n portainer deploy/portainer -- curl -k -s --connect-timeout 5 https://portainer-agent.portainer-agent.svc.cluster.local:9001/ping
```
Або тимчасовий busybox (агент у namespace `portainer-agent`):
```bash
AGENT_IP=$(kubectl get svc -n portainer-agent portainer-agent -o jsonpath='{.spec.clusterIP}')
kubectl run -n portainer debug-ip --rm -it --restart=Never --image=busybox -- wget -qO- --no-check-certificate --timeout=5 https://${AGENT_IP}:9001/ping 2>&1
```
Якщо у відповіді з’являється вміст (наприклад `pong`) — у UI можна сміливо вказувати `AGENT_IP:9001`.

---

## Agent у CrashLoopBackOff (Exit Code 1)

Под агента стартує, потім падає через ~30–50 с з **Exit Code: 1**. Перевірка:

**Типова причина:** у логах з’являється `lookup s-portainer-agent-headless on ...:53: no such host`. Агент очікує headless-сервіс з ім’ям **s-portainer-agent-headless** у тому ж namespace. Додайте й застосуйте манифест:
```bash
kubectl apply -f manifests/portainer-agent/service-headless.yaml
```
Після цього перезапустіть deployment агента. Деталі — у `manifests/portainer-agent/service-headless.yaml`.

### Агент у namespace **portainer** (деплой з `manifests/portainer/portainer-agent.yaml`)

Якщо под агента в **portainer** падає з помилкою `Lookup portainer-agent-headless.portainer.svc.cluster.local ... no such host` або `unable to retrieve a list of IP associated to the host`: агент очікує headless-сервіс **portainer-agent-headless** у тому ж namespace. Він уже в `portainer-agent.yaml`. Застосуйте манифест і переконайтеся, що DNS з portainer дозволено (Cilium):

```bash
kubectl apply -f manifests/portainer/portainer-agent.yaml
kubectl apply -f manifests/portainer/networkpolicy-allow-dns-from-portainer.yaml
kubectl rollout restart deployment/portainer-agent -n portainer
```

**Агент у portainer-agent падає з `lookup s-portainer-agent-headless on 10.96.0.10:53: i/o timeout`:** поду агента потрібен DNS до CoreDNS і прийом DNS-відповідей. Застосовано два підходи: (1) Політики DNS: у `networkpolicy-allow-from-portainer.yaml` — egress до `10.96.0.10/32:53`, ingress від CoreDNS і від `10.244.0.0/16`; у `networkpolicy-allow-dns-from-agent.yaml` — ingress до CoreDNS від portainer-agent і від `host`, egress з CoreDNS до portainer-agent, `10.244.0.0/16`, `host`, `10.0.10.0/24`. (2) **hostNetwork: true** у `deployment.yaml` — агент використовує мережу ноди, DNS через `dnsPolicy: ClusterFirstWithHostNet`; тоді CoreDNS має приймати від `host` і мати egress до `host`/`10.0.10.0/24`. Застосуйте й перезапустіть агента:
```bash
kubectl apply -f manifests/portainer-agent/networkpolicy-allow-from-portainer.yaml
kubectl apply -f manifests/portainer-agent/networkpolicy-allow-dns-from-agent.yaml
kubectl rollout restart deployment/portainer-agent -n portainer-agent
```
Після цього агент має стабільно працювати (без рестартів через DNS timeout).

**Швидке рішення (прибрати агента з portainer):** якщо агент у namespace **portainer** продовжує падати з `lookup portainer-agent-headless.portainer.svc.cluster.local`, видаліть його і підключайте середовище тільки до агента в **portainer-agent**:

```bash
kubectl delete deployment portainer-agent -n portainer
kubectl delete svc portainer-agent portainer-agent-headless -n portainer
```

Потім у Portainer UI: **Environments** → клік по **LOCAL** → **Edit** → **Environment URL** вкажіть `https://portainer-agent.portainer-agent.svc.cluster.local:9001` → **Update**. Після оновлення середовище має стати доступним (агент у portainer-agent вже Running).

1. **Логи останнього (впавшего) контейнера:**
   ```bash
   kubectl logs -n portainer-agent deploy/portainer-agent --previous
   ```
   Або поди з лейблом: `kubectl logs -n portainer-agent -l app=portainer-agent --previous --tail=100`

2. **AGENT_SECRET** — якщо на Portainer Server у налаштуваннях задано **Agent secret**, той самий секрет має бути в поді агента. Додайте в deployment агента (або створіть Secret і вкажіть valueFrom):
   ```yaml
   env:
   - name: AGENT_SECRET
     value: "той_самий_секрет_що_на_server"
   ```
   Після зміни: `kubectl apply -f manifests/portainer-agent/deployment.yaml` та перезапуск.

3. **Доступ агента до API кластера** — агент використовує ServiceAccount. Переконайтеся, що ClusterRole для `portainer-agent` застосовано і прив’язано до ServiceAccount у namespace `portainer-agent`.

4. Якщо в логах з’являється **nil pointer** або **getSwarmConfiguration** — це відома проблема деяких версій; спробуйте зафіксувати образ агента (наприклад `portainer/agent:2.19.4`) замість `latest`.

---

## DNS "Resolving timed out" з namespace portainer

Якщо под у `portainer` не може резолвити імена (наприклад `portainer-agent.portainer-agent.svc.cluster.local`) — у логах curl: **Resolving timed out after 5000 milliseconds**. При Cilium default-deny CoreDNS у kube-system не приймає трафік з порту 53 від подів з інших namespace, якщо немає явного ingress.

Застосуйте політику, що дозволяє ingress до CoreDNS з namespace portainer:
```bash
kubectl apply -f manifests/portainer/networkpolicy-allow-dns-from-portainer.yaml
```
Політика створює CiliumNetworkPolicy в namespace **kube-system** (ingress до подів з лейблом `k8s-app: kube-dns` з порту 53 від `portainer` / `app: portainer`). Якщо у вас CoreDNS з іншими лейблами (наприклад тільки `app.kubernetes.io/name=coredns`), перевірте: `kubectl get pods -n kube-system --show-labels | grep -i coredns` і змініть `endpointSelector` у манифесті.

Після застосування перевірте (агент слухає **HTTPS**, тому `-k` і `https://`):
```bash
kubectl run -n portainer debug-curl --restart=Never --image=curlimages/curl --labels="app=portainer" -- curl -k -s -m 10 https://portainer-agent.portainer-agent.svc.cluster.local:9001/ping
kubectl wait --for=condition=Ready pod/debug-curl -n portainer --timeout=60s
kubectl logs -n portainer debug-curl
kubectl delete pod -n portainer debug-curl
```
Якщо в логах успішний вивід (порожній або «pong») — DNS і доступ до агента працюють. Якщо «Resolving timed out» — перевірте політику: `kubectl get ciliumnetworkpolicy -n kube-system allow-dns-from-portainer`. Додано також **allow-portainer-ingress-from-coredns** у namespace portainer (ingress від CoreDNS) та toCIDR/toServices для kube-dns у egress. Якщо DNS усе одно не працює з подів у portainer, тимчасовий обхід: у Portainer UI вкажіть **Environment URL** як `https://<ClusterIP>:9001`, де ClusterIP сервісу агента: `kubectl get svc -n portainer-agent portainer-agent -o jsonpath='{.spec.clusterIP}'`. Якщо connection refused/timeout на 9001 — перевірте egress до agent: `kubectl apply -f manifests/portainer/networkpolicy-portainer-to-agent.yaml`.

---

## "dial tcp 10.96.0.1:443: i/o timeout" (Portainer не бачить API кластера)

Якщо в логах Portainer з’являється `unable to snapshot cluster version/nodes | dial tcp 10.96.0.1:443: i/o timeout` — под не може досягти Kubernetes API. При Cilium default-deny потрібен egress до API.

У `networkpolicy-portainer-to-agent.yaml` додано політику **allow-portainer-egress-kube-apiserver** (toEntities: kube-apiserver). Застосуйте:
```bash
kubectl apply -f manifests/portainer/networkpolicy-portainer-to-agent.yaml
kubectl rollout restart deployment/portainer -n portainer
```

---

## "Connection refused" до Agent (portainer-agent namespace)

Якщо з пода в namespace `portainer` до `portainer-agent.portainer-agent.svc.cluster.local:9001` або ClusterIP:9001 — **Connection refused**:

1. **Політики для agent у namespace portainer-agent**  
   CiliumNetworkPolicy має дозволяти: ingress до подів у **portainer-agent** від server у portainer, і egress з portainer до подів у **portainer-agent**. У репо політики виправлено: для **portainer** — egress до agent; для **portainer-agent** — окремий файл. Застосуйте обидва:
   ```bash
   kubectl apply -f manifests/portainer/networkpolicy-portainer-to-agent.yaml
   kubectl apply -f manifests/portainer-agent/networkpolicy-allow-from-portainer.yaml
   ```

2. **Порожні Endpoints (Service без подів)**  
   Якщо `kubectl get endpoints -n portainer-agent portainer-agent` показує порожні ENDPOINTS — сервіс не бачить подів (поди не Ready або їх немає). Перевірка:
   ```bash
   kubectl get pods -n portainer-agent -l app=portainer-agent -o wide
   kubectl describe pod -n portainer-agent -l app=portainer-agent
   ```
   Якщо подів немає або вони не Ready — перезапустіть deployment і перегляньте події:
   ```bash
   kubectl rollout restart deployment/portainer-agent -n portainer-agent
   kubectl rollout status deployment/portainer-agent -n portainer-agent
   kubectl get events -n portainer-agent --sort-by='.lastTimestamp'
   ```
   Після того як под стане Running/Ready, Endpoints з’являться і з’єднання до агента має запрацювати.

3. **Перевірка слухача в поді** (коли под Running; контейнер може називатися інакше):
   ```bash
   kubectl exec -n portainer-agent deploy/portainer-agent -c portainer-agent -- ss -tlnp
   ```
   Або знайдіть ім’я контейнера: `kubectl get pod -n portainer-agent -l app=portainer-agent -o jsonpath='{.items[0].spec.containers[*].name}'`

4. **Перевірка досяжності агента з namespace portainer (з лейблом app=portainer):**  
   Под з лейблом `app=portainer` має те саме дозволене egress до агента, що й Portainer Server. Запустіть под без `--rm`, потім перегляньте логи:
   ```bash
   kubectl run -n portainer debug-curl --restart=Never --image=curlimages/curl --labels="app=portainer" -- curl -s -m 5 -v http://portainer-agent.portainer-agent.svc.cluster.local:9001/ping
   kubectl logs -n portainer debug-curl
   kubectl delete pod -n portainer debug-curl
   ```
   У логах буде видно: успішний HTTP-відповідь або таймаут/refused.

5. **Спробувати HTTP замість HTTPS**  
   Агент на 9001 може приймати лише HTTP. Перевірка з debug-поду:
   ```bash
   AGENT_IP=$(kubectl get svc -n portainer-agent portainer-agent -o jsonpath='{.spec.clusterIP}')
   kubectl run -n portainer debug-agent --rm -it --restart=Never --image=busybox -- wget -qO- --timeout=5 http://${AGENT_IP}:9001/ping 2>&1
   ```
   У UI Portainer для Environment URL спробуйте `http://portainer-agent.portainer-agent.svc.cluster.local:9001` (без https).

---

## LOCAL Down — "no route to host" до агента

Якщо в сповіщеннях Portainer: `Get "https://10.104.196.55:9001/ping": dial tcp 10.104.196.55:9001: connect: no route to host` — трафік з пода Portainer (наприклад на **master-node**, OCI) не доходить до ноди з агентом (наприклад **beelinkeqr5**, локальна мережа). Це типова проблема cross-node pod connectivity (див. `manifests/POD_CONNECTIVITY_FIX_10_244.md`).

**Якщо агент на master-node падає (lookup s-portainer-agent-headless: i/o timeout):** поду в namespace portainer-agent потрібен DNS до CoreDNS. Застосуйте: `kubectl apply -f manifests/portainer-agent/networkpolicy-allow-dns-from-agent.yaml`, потім `kubectl rollout restart deployment/portainer-agent -n portainer-agent`.

**Швидкий обхід:** запустити агента на тій самій ноді, що й Portainer (master-node). У `manifests/portainer-agent/deployment.yaml` додано `nodeSelector: kubernetes.io/hostname: master-node` та toleration для control-plane. Застосуйте й перезапустіть агента:
```bash
kubectl apply -f /Users/omartyny/WORK/k3s/manifests/portainer-agent/deployment.yaml
kubectl rollout restart deployment/portainer-agent -n portainer-agent
kubectl rollout status deployment/portainer-agent -n portainer-agent
```
Після цього Portainer і агент будуть на одній ноді, маршрут не потрібен. У UI натисніть Refresh для середовища LOCAL.

**Довгостроково:** налаштувати cross-node connectivity (OCI Security List для 10.244.0.0/16 або VXLAN у Cilium), після чого можна прибрати nodeSelector з агента.

---

## LOCAL Down — SSL/TLS налаштування відсутні в UI

У Portainer CE для середовища типу **Kubernetes (Agent)** немає опції «Skip TLS verification» / «Skip certificate verification» у формі редагування. Якщо агент слухає **HTTPS** з self-signed сертифікатом, Portainer може відмовляти з’єднання через перевірку сертифіката, і задокументованої змінної середовища для пропуску перевірки немає.

**Рішення:** стандартний агент на порту 9001 слухає **HTTP**. Якщо Portainer підключається по HTTPS → **connection refused**.

1. **URL без протоколу** (рекомендовано в [документації](https://docs.portainer.io/admin/environments/add/kubernetes/agent)): у **Environment URL** вкажіть лише `10.104.196.55:9001` (без `http://` і без `https://`). Portainer сам обере протокол.
2. **Вимкнути «Force HTTPS only»** у Portainer: **Settings** → **General** (або подібний розділ). Якщо опція увімкнена, сервер намагається HTTPS до агента на 9001 і падає ([Issue #12791](https://github.com/portainer/portainer/issues/12791)). Після вимкнення — зберегти й оновити середовище (Refresh).
3. Якщо UI дозволяє вводити протокол — спробувати явно `http://10.104.196.55:9001`.

Збережіть середовище (Update environment) і натисніть Refresh.

---

## Сповіщення (Notifications): Failure — Get "https://10.104.196.55:9001/ping"

У панелі **Notifications** можуть з’являтися помилки:
- **dial tcp 10.104.196.55:9001: connect: operation not permitted** — Cilium блокує трафік (egress з Portainer або ingress до агента). Застосуйте політики: `networkpolicy-portainer-to-agent.yaml` і `portainer-agent/networkpolicy-allow-from-portainer.yaml`.
- **connect: connection refused** — агент не приймає з’єднання: под у стані Error/CrashLoopBackOff або ENDPOINTS порожні. Перевірте `kubectl get pods -n portainer-agent` і `kubectl get endpoints -n portainer-agent portainer-agent`. Якщо под Running, але раніше був рестарт — спробуйте **Connect** ще раз. Як варіант, вкажіть **Environment URL** як NodePort: `<IP-ноди-master-node>:30901` (наприклад `10.0.10.10:30901`), щоб підключатися напряму до ноди, коли агент на ній працює. Для стабілізації DNS агента застосуйте дозвольну політику: `kubectl apply -f manifests/portainer-agent/networkpolicy-allow-agent-dns-permissive.yaml`.

---

## "Operation not permitted" при підключенні до Agent (ClusterIP або pod IP)

Якщо wget/curl з поду до https://<agent-ip>:9001/ping або в UI з'являється **operation not permitted**, це зазвичай Cilium **default-deny**: трафік між подами блокується політиками.

Застосуйте CiliumNetworkPolicy, яка дозволяє трафік Portainer Server → Portainer Agent:9001:

```bash
kubectl apply -f /Users/omartyny/WORK/k3s/manifests/portainer/networkpolicy-portainer-to-agent.yaml
```

Після застосування перевірте з'єднання знову (Refresh у Portainer UI або повторний wget з debug-поду).
