# Знаходження kubeconfig для k3s

## Проблема

Файл `/etc/rancher/k3s/k3s.yaml` не знайдено. Потрібно знайти правильний шлях до kubeconfig.

## Варіанти пошуку

### Варіант 1: Використати k3s kubectl (найпростіше)

На master node спробуйте:

```bash
# Використайте k3s kubectl замість kubectl
k3s kubectl get nodes

# Якщо працює, використайте для перезапуску:
k3s kubectl delete pods -n monitoring -l app=prometheus
```

### Варіант 2: Знайти kubeconfig

```bash
# Перевірте стандартне місце
ls -la ~/.kube/config

# Пошук файлу k3s.yaml
find /etc -name "k3s.yaml" 2>/dev/null
find /var -name "k3s.yaml" 2>/dev/null

# Перевірте, чи є kubeconfig в інших місцях
ls -la /etc/rancher/k3s/
ls -la /var/lib/rancher/k3s/
```

### Варіант 3: Створити kubeconfig з k3s

```bash
# Якщо k3s kubectl працює, створіть kubeconfig:
mkdir -p ~/.kube
k3s kubectl config view --raw > ~/.kube/config
chmod 600 ~/.kube/config

# Тепер kubectl має працювати:
kubectl get nodes
```

### Варіант 4: Використати Portainer UI (рекомендовано)

Оскільки kubectl не налаштований, найпростіше використати Portainer UI:

1. Kubernetes → Applications → monitoring
2. Application containers → знайдіть prometheus pod
3. Натисніть на pod → Delete
4. Deployment автоматично створить новий pod

## Перевірка типу встановлення k3s

```bash
# Перевірте, чи k3s встановлений як сервіс
systemctl status k3s

# Або перевірте процес
ps aux | grep k3s

# Перевірте версію
k3s --version
```

## Рекомендація

**Найпростіше рішення:** Використайте Portainer UI для перезапуску Prometheus. Це не потребує налаштування kubectl.

Якщо потрібен kubectl для інших задач, спробуйте `k3s kubectl` або створіть kubeconfig як показано вище.
