# Fix: kubectl "x509: certificate signed by unknown authority"

Ця помилка виникає, коли `kubectl` не довіряє сертифікату API-сервера — зазвичай через старий або неправильний kubeconfig (наприклад, після переінсталяції k3s або копіювання з іншої машини).

## Рішення 1: Оновити kubeconfig з сервера (рекомендовано)

Якщо є SSH до **будь-якої** ноди з k3s (master або server):

```bash
# Скопіювати актуальний kubeconfig з сервера (замініть user@SERVER на ваш логін та IP/хост)
scp user@<MASTER_IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-config.yaml
```

Потім на вашій машині:

```bash
# Використати скопійований config
export KUBECONFIG=~/.kube/k3s-config.yaml
```

У файлі `~/.kube/k3s-config.yaml` за замовчуванням буде `server: https://127.0.0.1:6443`. Якщо ви підключаєтесь **віддалено**, замініть на IP вашого master (наприклад з WireGuard):

```yaml
# Змінити в ~/.kube/k3s-config.yaml:
server: https://192.168.100.5:6443   # або https://10.0.10.10:6443
```

Перевірка:

```bash
kubectl get nodes
```

Щоб зробити цей config стандартним для kubectl:

```bash
cp ~/.kube/k3s-config.yaml ~/.kube/config
# або в .zshrc / .bashrc:
# export KUBECONFIG=~/.kube/k3s-config.yaml
```

---

## Рішення 2: Якщо kubectl запускається на самій ноді k3s

На сервері, де працює k3s:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

---

## Рішення 3: Тимчасовий обхід (не для продакшену)

У вашому kubeconfig (наприклад `~/.kube/config`) у блоці **cluster** додайте:

```yaml
clusters:
- cluster:
    certificate-authority-data: ...   # можна залишити
    server: https://...
    insecure-skip-tls-verify: true    # додати цей рядок
  name: ...
```

Після цього kubectl не перевірятиме сертифікат. Використовуйте лише для тимчасового доступу.
