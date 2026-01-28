# Виправлення логів CoreDNS (No files matching import glob pattern)

## Проблема

У логах CoreDNS постійно з’являються попередження:

```
maxprocs: Leaving GOMAXPROCS=4: CPU quota undefined
[WARNING] No files matching import glob pattern: /etc/coredns/custom/*.override
[WARNING] No files matching import glob pattern: /etc/coredns/custom/*.server
```

**Причина:** У k3s Corefile CoreDNS є директиви `import /etc/coredns/custom/*.override` та `import /etc/coredns/custom/*.server`. Ці файли монтуються з ConfigMap **coredns-custom** у namespace **kube-system**. Якщо ConfigMap відсутній або не містить ключів `*.override` та `*.server`, збігів немає і CoreDNS логирує WARNING при кожному reload.

**Поведінка:** Це не ламає DNS, але засмічує логи.

---

## Рішення

Створити (або оновити) ConfigMap **coredns-custom** у **kube-system** з мінімальними ключами **\*.override** та **\*..server**, щоб імпорт знаходив файли і попередження зникли.

### Крок 1: Застосувати ConfigMap

```bash
kubectl apply -f manifests/coredns/coredns-custom-configmap.yaml
```

Якщо ConfigMap **coredns-custom** уже існує і ви його редагували вручну — перевірте, чи є в ньому ключі з суфіксами **.override** та **.server**. Якщо є, попередження не повинні з’являтися; якщо немає — додайте їх за прикладом з `coredns-custom-configmap.yaml` або застосуйте наш манифест (він перезапише існуючий ConfigMap).

### Крок 2: Перезапустити CoreDNS (за потреби)

k3s зазвичай підхоплює зміни ConfigMap і перезавантажує конфіг CoreDNS. Якщо попередження лишаються — перезапустіть поди:

```bash
kubectl rollout restart deployment coredns -n kube-system
```

### Крок 3: Перевірити логи

```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
```

Попередження `No files matching import glob pattern` мають зникнути.

---

## Про повідомлення "CPU quota undefined"

Рядок **maxprocs: Leaving GOMAXPROCS=4: CPU quota undefined** означає, що контейнер CoreDNS не має CPU limit у pod spec; плагін maxprocs не може визначити квоту і залишає GOMAXPROCS за замовчуванням. Це **інформаційне** повідомлення, не помилка. Щоб прибрати його, можна задати CPU limit у Deployment CoreDNS (наприклад у HelmChartConfig для coredns), але це не обов’язково для роботи DNS.

---

## "No route to host" та Readiness probe failed 503

**Симптоми:** Под CoreDNS на **work-node** не може доступитися до Kubernetes API (10.43.0.1:443), у логах — `dial tcp 10.43.0.1:443: connect: no route to host`, плагін `kubernetes` не готовий, **Readiness probe failed: HTTP probe failed with statuscode: 503**.

**Причина:** На ноді work-node (або на її pod-network) немає маршруту до Service IP 10.43.0.1 (kubernetes.default). Це відома проблема pod-network у вашому кластері; Traefik через це теж запускали лише на master-node.

**Рішення (обхід):** Планувати CoreDNS **лише на нодах, де є доступ до API** (master-node, macmini7), а не на work-node.

### Крок 1: Застосувати патч nodeAffinity

З каталогу `manifests/coredns` (якщо kubeconfig k3s доступний лише root — з `sudo`):

```bash
sudo ./apply-coredns-node-affinity.sh
```

або вручну:

```bash
sudo kubectl patch deployment coredns -n kube-system --patch-file=manifests/coredns/coredns-node-affinity-patch.yaml
```

У патчі вказано ноди **master-node** та **macmini7**. Якщо у вас інші імена нод з доступом до API — відредагуйте `coredns-node-affinity-patch.yaml` (поле `values`).

### Крок 2: Перевірити

Под CoreDNS має перезапуститися і заплануватися на master-node або macmini7:

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
```

У логах не повинно бути "no route to host"; readiness probe має стати успішною.

### Важливо

- Після оновлення k3s вбудований манифест CoreDNS може перезаписати Deployment — патч зникне. Застосуйте його знову після оновлення.
- Щоб виправити мережу на work-node (доступ подів до 10.43.0.1), потрібна окрема діагностика (kube-proxy, firewall, маршрути, CNI).
