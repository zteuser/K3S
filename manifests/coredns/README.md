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
