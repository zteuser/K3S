# Налаштування kubectl для k3s

## Проблема

При виконанні `kubectl` команд виникає помилка:
```
The connection to the server localhost:8080 was refused
```

Це означає, що `kubectl` не знає, як підключитися до k3s API server.

## Рішення

### Варіант 1: Встановити KUBECONFIG (рекомендовано)

На master node виконайте:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

Для постійного налаштування додайте в `~/.bashrc` або `~/.zshrc`:

```bash
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
source ~/.bashrc
```

### Варіант 2: Скопіювати kubeconfig в стандартне місце

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
```

### Варіант 3: Використати Portainer UI (найпростіше)

Якщо kubectl не налаштований, використовуйте Portainer UI для перезапуску Prometheus.

## Перевірка

Після налаштування перевірте:

```bash
kubectl get nodes
kubectl get pods -n monitoring
```

Має працювати без помилок.
