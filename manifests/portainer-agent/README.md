# Portainer Agent для k3s Cluster

Ця директорія містить Kubernetes маніфести для розгортання Portainer Agent в кластері k3s.

## Що таке Portainer Agent?

Portainer Agent - це легкий компонент, який розгортається в Kubernetes кластері і дозволяє Portainer UI підключатися до кластера через Agent, а не напряму до Kubernetes API.

## Архітектура

- **Namespace**: `portainer-agent`
- **ServiceAccount**: `portainer-agent` з ClusterRole для доступу до Kubernetes API
- **Deployment**: 1 replica Portainer Agent
- **Service**: NodePort (порт 30901)

## Deployment

### Швидкий старт

```bash
cd /path/to/k3s/manifests/portainer-agent
./deploy-agent.sh
```

### Вручну

```bash
kubectl apply -f namespace.yaml
kubectl apply -f serviceaccount.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

### Використання офіційного маніфесту

Якщо власний deployment не працює, можна використати офіційний маніфест:

```bash
# Для NodePort
kubectl apply -f https://downloads.portainer.io/ce2-33/portainer-agent-k8s-nodeport.yaml

# Або для LoadBalancer
kubectl apply -f https://downloads.portainer.io/ce2-33/portainer-agent-k8s-lb.yaml
```

## Підключення в Portainer UI

1. Відкрийте Portainer UI
2. Перейдіть до "Add environment" → "Kubernetes" → "Agent"
3. Введіть:
   - **Name**: `k3s-cluster` (або будь-яка назва)
   - **Environment address**: `<node-ip>:30901`
     - Для master-node: `10.0.10.10:30901`
     - Для work-node: `10.0.10.20:30901`
     - Для macmini7: `192.168.2.19:30901`
4. Натисніть "Connect"

## Troubleshooting

### Pod в статусі CrashLoopBackOff

```bash
# Перевірка логів
kubectl logs -n portainer-agent -l app=portainer-agent

# Опис Pod
kubectl describe pod -n portainer-agent -l app=portainer-agent
```

### Connection refused

1. Перевірте що Pod працює:
   ```bash
   kubectl get pods -n portainer-agent
   ```

2. Перевірте що Service створено:
   ```bash
   kubectl get svc -n portainer-agent
   ```

3. Перевірте доступність порту:
   ```bash
   # З іншої машини
   telnet <node-ip> 30901
   ```

4. Перевірте firewall на нодах:
   ```bash
   sudo ufw status
   ```

### Використання офіційного маніфесту

Якщо власний deployment не працює, видаліть його і використайте офіційний:

```bash
# Видалення власного deployment
kubectl delete -f .

# Використання офіційного
kubectl apply -f https://downloads.portainer.io/ce2-33/portainer-agent-k8s-nodeport.yaml
```

## Видалення

```bash
kubectl delete -f .
# Або
kubectl delete namespace portainer-agent
```
