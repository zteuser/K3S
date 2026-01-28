# Відновлення доступу до графічної панелі Grafana

## 404 page not found на http://monitoring.lan

**Симптоми:** `ping monitoring.lan` і порти 80/443 відкриті, але в браузері **http://monitoring.lan** показує **404 page not found**.

**Причина:** У k3s Traefik за замовчуванням обробляє **стандартний Ingress**, а не IngressRoute (CRD). Якщо в кластер застосовано лише `ingressroute.yaml`, маршрут для `monitoring.lan` у Traefik не з’являється.

**Що зробити:**

1. Застосувати **стандартний Ingress** для Grafana (файл `grafana/ingress.yaml` вже додано в `kustomization.yaml`):

   ```bash
   # З каталогу manifests/monitoring
   kubectl apply -k .
   ```

   або тільки Ingress:

   ```bash
   kubectl apply -f grafana/ingress.yaml
   ```

2. Перевірити, що Ingress створився:

   ```bash
   kubectl get ingress -n monitoring
   ```

3. Відкрити в браузері **http://monitoring.lan** (при потребі оновіть сторінку з пропуском кешу: Ctrl+F5).

Якщо після цього з’явиться **502 Bad Gateway**, **503** або **no available server** — Traefik не може доступитися до Service `grafana:3000` (порожні endpoints або проблеми pod-network); тоді використовуйте доступ по NodePort (відкрийте порт 30000 на ноді, див. нижче).

---

## «No available server» на http://monitoring.lan

**Симптоми:** Ingress створено (`kubectl get ingress -n monitoring` показує grafana з HOSTS monitoring.lan), але в браузері **http://monitoring.lan** показує **no available server**.

**Причина:** Traefik отримує запит, але не може знайти «живий» бекенд: або у Service `grafana` немає endpoints (selector не збігається з подами), або Traefik не може доступитися до pod/Service (проблеми pod-network).

**Що зробити:**

1. Перевірити endpoints:
   ```bash
   kubectl get endpoints -n monitoring grafana
   ```
   Якщо порожні — переконайтеся, що под Grafana має мітку `app: grafana` і що Service має `selector: app: grafana`.

2. Якщо endpoints є, але «no available server» залишається — Traefik (на ноді з hostNetwork) не може доступитися до Service IP (відома проблема pod-network у вашому кластері). **Обхід:** використовуйте доступ по **NodePort**:
   - На ноді 10.0.10.10 відкрийте порт **30000/tcp** у фаєрволі.
   - У браузері відкрийте **http://10.0.10.10:30000** (див. розділ «ERR_CONNECTION_REFUSED на 10.0.10.10:30000» нижче).

---

## ERR_CONNECTION_REFUSED на http://10.0.10.10:30000

**Симптоми:**

- Под Grafana в статусі **Running**, логи без помилок (`HTTP Server Listen` на порту 3000).
- У браузері при відкритті **http://10.0.10.10:30000** — **«This site can't be reached»** / **ERR_CONNECTION_REFUSED**.

Це означає: Grafana всередині пода працює, а з’єднання до **NodePort 30000** на ноді (10.0.10.10) не проходить — проблема на рівні мережі/фаєрволу або Service/Endpoints.

---

## Крок 1: Перевірити Service та Endpoints

На машині з `kubectl` (доступ до кластера):

```bash
# Service і NodePort
kubectl get svc -n monitoring grafana -o wide

# Мають бути endpoints (IP пода)
kubectl get endpoints -n monitoring grafana
```

Якщо **Endpoints** порожні — под не підходить під selector `app: grafana`. Перевірте:

```bash
kubectl get pods -n monitoring -l app=grafana -o wide
kubectl get svc -n monitoring grafana -o yaml
```

Selector у Service має збігатися з labels пода.

---

## Крок 2: Перевірка зсередини кластера

Переконайтеся, що до Grafana можна доступитися по Service:

```bash
kubectl run curl --rm -it --image=curlimages/curl --restart=Never -n monitoring -- \
  curl -s -o /dev/null -w "%{http_code}" http://grafana.monitoring.svc.cluster.local:3000/api/health
```

Очікується **200**. Якщо так — Grafana і Service працюють, проблема саме в NodePort/мережі ззовні.

---

## Крок 3: Перевірка NodePort на ноді (10.0.10.10)

Виконайте **на master-node** (де IP 10.0.10.10):

```bash
# Чи слухає щось на 30000
ss -tlnp | grep 30000
# або
netstat -tlnp | grep 30000
```

Потім локально на тій же ноді:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:30000/api/health
```

- Якщо **порт не слухається** — проблема в k3s/kube-proxy (NodePort не відкритий).
- Якщо **localhost:30000** відповідає 200, а з вашого ПК 10.0.10.10:30000 — **refused**, далі перевіряємо фаєрвол.

---

## Крок 4: Фаєрвол на master-node

Якщо з ноди `curl http://127.0.0.1:30000` працює, а з браузера на 10.0.10.10:30000 — ні, відкрийте порт **30000/tcp** на ноді.

**firewalld:**

```bash
sudo firewall-cmd --permanent --add-port=30000/tcp
sudo firewall-cmd --reload
```

**iptables:**

```bash
sudo iptables -I INPUT -p tcp --dport 30000 -j ACCEPT
# Якщо потрібно зберегти правило після перезавантаження — збережіть правила вашої ОС.
```

**ufw:**

```bash
sudo ufw allow 30000/tcp
sudo ufw reload
```

Після цього спробуйте знову **http://10.0.10.10:30000**.

---

## Крок 5: Доступ через Ingress (альтернатива NodePort)

У вас налаштований **Traefik** і **IngressRoute** для Grafana: хост **monitoring.lan**, порти 80/443.

1. На ПК, з якого відкриваєте браузер, додайте в hosts:
   ```text
   10.0.10.10  monitoring.lan
   ```
2. Відкрийте в браузері:
   - **http://monitoring.lan** або **https://monitoring.lan**

Якщо Traefik на master-node (10.0.10.10) і порти 80/443 відкриті — панель Grafana має відкриватися без використання порту 30000.

---

## Крок 6: Перезапуск компонентів (якщо NodePort не з’являється)

На ноді з k3s:

```bash
# Перезапуск пода Grafana (не змінює NodePort, але оновить endpoints)
kubectl delete pod -n monitoring -l app=grafana

# Перевірка, що Service існує і nodePort 30000
kubectl get svc -n monitoring grafana
```

Якщо після всіх кроків порт 30000 так і не слухається на ноді — перезавантажте k3s або ноду (за потреби після узгодження).

---

## Швидкий чеклист

| Перевірка | Команда / дія |
|-----------|----------------|
| Endpoints не порожні | `kubectl get endpoints -n monitoring grafana` |
| З кластера є доступ | `kubectl run curl ... -- curl -s -o /dev/null -w "%{http_code}" http://grafana.monitoring.svc.cluster.local:3000/api/health` |
| На ноді слухає 30000 | На 10.0.10.10: `ss -tlnp \| grep 30000` |
| Локально на ноді | На 10.0.10.10: `curl -s -w "%{http_code}" http://127.0.0.1:30000/api/health` |
| Фаєрвол | Відкрити 30000/tcp на master-node |
| Через Ingress | Додати `10.0.10.10 monitoring.lan` у hosts, відкрити http://monitoring.lan |

Після виконання кроків 1–4 (або використання Ingress з кроку 5) графічна панель Grafana має відкриватися.
