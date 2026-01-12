# Виправлення помилки прав доступу для Grafana

## Проблема

Grafana pod не може запуститися через помилку:
```
GF_PATHS_DATA='/var/lib/grafana' is not writable.
mkdir: can't create directory '/var/lib/grafana/plugins': Permission denied
```

## Причина

Grafana не може створити файли в директорії `/var/lib/grafana` через відсутність прав доступу на OCFS2 volume.

## Рішення

### Варіант 1: Використати deployment з initContainer (якщо Pod Security Policy дозволяє)

Оновлений `grafana/deployment.yaml` вже містить:
- `securityContext` з правильними UID/GID (472 - grafana)
- `initContainer` для встановлення прав на директорію

Просто оновіть deployment через Portainer:
1. Відкрийте **Kubernetes** → **Applications** → **monitoring**
2. Знайдіть deployment **grafana**
3. Натисніть **Editor**
4. Скопіюйте оновлений вміст `grafana/deployment.yaml`
5. Натисніть **Update**

### Варіант 2: Використати deployment без initContainer (якщо Pod Security Policy блокує root)

Якщо initContainer не може запуститися через Pod Security Policy, використайте `deployment-fix-permissions.yaml`:

1. В Portainer відкрийте deployment **grafana**
2. Замініть вміст на `grafana/deployment-fix-permissions.yaml`
3. Оновіть deployment

Цей варіант покладається тільки на `fsGroup` для автоматичного встановлення прав.

### Варіант 3: Встановити права вручну (якщо маєте доступ до ноди)

```bash
# Знайдіть pod
kubectl get pods -n monitoring -l app=grafana

# Виконайте команду в pod (якщо pod запущений)
kubectl exec -n monitoring -it <pod-name> -- chown -R 472:472 /var/lib/grafana
kubectl exec -n monitoring -it <pod-name> -- chmod -R 755 /var/lib/grafana

# Перезапустіть pod
kubectl delete pod -n monitoring -l app=grafana
```

### Варіант 4: Встановити права на ноді (якщо маєте доступ)

Якщо маєте доступ до ноди, де знаходиться volume:

```bash
# На ноді (master-node або work-node)
sudo chown -R 472:472 /sharedata2/grafana  # або відповідний шлях
sudo chmod -R 755 /sharedata2/grafana
```

## Перевірка

Після оновлення deployment:

```bash
# Перевірка статусу pod
kubectl get pods -n monitoring -l app=grafana

# Перевірка логів
kubectl logs -n monitoring -l app=grafana --tail=20

# Перевірка прав в pod
kubectl exec -n monitoring -it <pod-name> -- ls -la /var/lib/grafana
```

## Якщо проблема залишається

Якщо `fsGroup` не працює з OCFS2, можна використати root права для всього pod (менш безпечно):

1. Відкрийте deployment в Portainer
2. Змініть `runAsUser: 0` та `runAsNonRoot: false` в securityContext
3. Оновіть deployment

**Увага:** Це менш безпечно, але може бути необхідно для OCFS2.
