# Тест відмовостійкості кластера при втраті однієї з трьох master-нод

Перевірка, що при виході з ладу однієї з трьох control-plane нод (master-node, macmini7, beelinkeqr5) кластер продовжує працювати: API доступний, workloads працюють, нові поди плануються.

## Передумови

- Кластер k3s з **трьома** control-plane нодами: **master-node**, **macmini7**, **beelinkeqr5** (embedded etcd, HA).
- Одна або більше worker-нод (наприклад work-node).
- `kubectl` налаштований і працює з хоста однієї з control-plane нод або з окремого клієнта з доступом до API (наприклад через load balancer або один з server IP:6443).

**Важливо:** під час тесту використовуйте `kubectl` з хоста **іншої** control-plane ноди (не тієї, яку ви «збиваєте»). Якщо kubeconfig вказує на один IP:6443 і ви зупиняєте саме цю ноду — перемкніть KUBECONFIG на інший server (наприклад на macmini7 або beelinkeqr5), щоб запити йшли на живу ноду.

---

## 1. Базовий стан (до тесту)

На **одній** з control-plane нод (наприклад macmini7) виконайте:

```bash
# Усі ноди Ready
kubectl get nodes -o wide

# Список подів по namespace
kubectl get pods -A -o wide | head -50

# API доступний
kubectl cluster-info
curl -k https://127.0.0.1:6443/healthz
```

Зафіксуйте: скільки нод Ready, які поди де запущені. Пізніше порівняєте після «відновлення» ноди.

---

## 2. Вибір ноди для «втрати» та спосіб вимкнення

**Варіанти:**

| Спосіб | Опис | Плюси / мінуси |
|--------|------|------------------|
| **A. Зупинити k3s** | На обраній master-ноді: `sudo systemctl stop k3s` | Безпечно, швидке відновлення: `systemctl start k3s`. |
| **B. Вимкнути мережу** | Відключити кабель / Wi‑Fi або блокувати трафік (iptables) на обраній ноді | Реалістичніше «відсічення» ноди, потім відновлення мережі. |
| **C. Вимкнути хост** | `sudo poweroff` на обраній ноді | Найжорсткіший тест; потрібен фізичний/консольний доступ для включення. |

Рекомендація для першого проходу: **варіант A** (зупинити k3s).

---

## 3. Тест: «втрата» першої master-ноди (наприклад beelinkeqr5)

### 3.1 Зупинити k3s на обраній ноді

На ноді **beelinkeqr5** (SSH або консоль):

```bash
sudo systemctl stop k3s
```

Переконайтеся, що процес зупинився: `pgrep -a k3s` — нічого не має бути.

### 3.2 Перемкнути kubectl на інший server (якщо потрібно)

Якщо ваш kubeconfig вказує на beelinkeqr5 (наприклад 192.168.2.155:6443), тимчасово змініть server на один з інших master:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
# Якщо в k3s.yaml server: https://192.168.2.155:6443 — замініть на:
# server: https://192.168.2.19:6443   (macmini7)
# або     https://10.0.10.10:6443     (master-node, якщо доступний)
```

Або виконуйте `kubectl` безпосередньо з **macmini7** або **master-node** (там kubeconfig зазвичай вказує на localhost:6443, який працює локально).

### 3.3 Перевірки під час «втрати» ноди

Виконуйте з **macmini7** або **master-node** (не з beelinkeqr5):

```bash
# Ноди: beelinkeqr5 має показати NotReady або статус зміниться через 40–60 с
kubectl get nodes -o wide
watch -n 5 'kubectl get nodes'

# API має відповідати (запит йде на macmini7 або master-node)
kubectl get nodes
kubectl get pods -A | head -30

# Робочі навантаження: поди на інших нодах мають лишатися Running
kubectl get pods -A -o wide

# Створити тестовий под — має заплануватися на одну з живих нод
kubectl run test-failover --rm -it --restart=Never --image=busybox:1.36 -- echo "OK"

# Доступ до сервісів: Portainer / Ingress (якщо працюють на master-node або macmini7)
curl -k -s -o /dev/null -w "%{http_code}\n" https://portainer.lan/
```

**Очікування:**

- Дві control-plane ноди лишаються Ready; beelinkeqr5 переходить у NotReady (через ~40–60 с).
- API відповідає, `kubectl get pods` працює.
- Поди на master-node, macmini7, work-node лишаються Running.
- Новий под (test-failover) планується на одну з живих нод.
- Якщо Portainer/Traefik на master-node або macmini7 — https://portainer.lan/ відповідає (наприклад 200 або 302).

### 3.4 Відновити ноду

На **beelinkeqr5**:

```bash
sudo systemctl start k3s
sudo systemctl status k3s
```

Через 1–2 хвилини з іншої ноди:

```bash
kubectl get nodes -o wide
```

beelinkeqr5 має знову стати **Ready**.

---

## 4. Тест для другої та третьої master-нод

Повторіть кроки з розділу 3 для **master-node** і **macmini7**:

1. Зупинити k3s на обраній ноді (`systemctl stop k3s`).
2. Виконувати `kubectl` з іншої control-plane ноди (або змінити server у kubeconfig).
3. Перевірити: `kubectl get nodes`, `kubectl get pods -A`, створення тестового пода, доступ до Portainer/Ingress.
4. Відновити k3s на ноді (`systemctl start k3s`), перевірити `kubectl get nodes`.

Таким чином перевіряється, що кластер витримує втрату **кожної** з трьох master-нод по черзі.

---

## 5. Чеклист підсумку

| Перевірка | Під час втрати 1 master |
|-----------|-------------------------|
| Інші control-plane ноди Ready | так |
| API доступний (kubectl get nodes) | так |
| Поди на живих нодах Running | так |
| Новий под планується | так |
| Portainer / Ingress відповідають | так (якщо на живих нодах) |
| Після start k3s нода знову Ready | так |

---

## 6. Додаткові зауваження

- **etcd:** при трьох server-нодах etcd має кворум (2 з 3). Втрата однієї ноди не призводить до втрати кворуму.
- **Робочі навантаження:** поди, що були на «втраченій» ноді, перейдуть у стан Terminating/Unknown до таймауту (NodeNotReady). Після повернення ноди вони можуть бути перезапущені контролерами (наприклад Deployment) на інших нодах, якщо політика перезапуску це передбачає. Для тесту краще спочатку переконатися, що критичні поди (Portainer, Traefik тощо) не прив’язані лише до однієї ноди (наприклад мають replicas або працюють на інших нодах).
- **Load balancer:** у продакшені перед трьома API server зазвичай ставлять load balancer (HAProxy, keepalived, cloud LB). Клієнти підключаються до LB, який направляє трафік на живу ноду. Тут тест виконується з прямою зміною server у kubeconfig.
