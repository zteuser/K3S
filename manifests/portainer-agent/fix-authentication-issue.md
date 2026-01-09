# Виправлення помилки автентифікації "Invalid request signature"

## Проблема

Portainer UI показує environment як "Down" і "Disconnected", а в логах Agent видно:
```
HTTP error | error=Unauthorized msg="Invalid request signature" status_code=403
```

## Причина

Portainer UI і Agent не синхронізовані з точки зору автентифікації. Це відбувається, коли:
- Environment був створений до того, як Agent був правильно налаштований
- Agent був перестворений, але Portainer UI все ще використовує старий секрет
- Environment був створений з неправильними налаштуваннями

## Рішення

### Крок 1: Видалити старий environment

1. Відкрийте Portainer UI
2. Знайдіть environment "k3s-cluster-vrn625"
3. Натисніть на іконку налаштувань (шестерня) біля environment
4. Виберіть "Remove environment"
5. Підтвердіть видалення

### Крок 2: Перезапустити Portainer Pod (опціонально, але рекомендується)

Це допоможе очистити кеш і перезавантажити конфігурацію:

```bash
# На macmini7
sudo kubectl rollout restart deployment/portainer -n portainer

# Дочекайтеся, поки Pod перезапуститься
sudo kubectl get pods -n portainer -l app=portainer -w
```

### Крок 3: Створити новий environment

1. Відкрийте Portainer UI
2. Натисніть "Add environment"
3. Виберіть "Kubernetes" → "Agent"
4. Виберіть вкладку **"Kubernetes via node port"** (не "via load balancer")
5. Введіть:
   - **Name**: `k3s-cluster-vrn625` (або будь-яка назва)
   - **Environment address**: `portainer-agent.portainer.svc.cluster.local:9001`
     - Або використайте IP ноди, де працює Portainer UI:
       - Якщо Portainer на `work-node`: `10.0.10.20:30778`
       - Якщо Portainer на `master-node`: `10.0.10.10:30778`
6. Натисніть "Connect"

**Важливо:** При створенні нового environment Portainer автоматично згенерує новий секрет для автентифікації з Agent.

## Перевірка

Після створення нового environment:

1. Перевірте статус в Portainer UI - має бути "Up" замість "Down"
2. Перевірте логи Agent - не повинно бути помилок "Invalid request signature":
   ```bash
   sudo kubectl logs -n portainer -l app=portainer-agent --tail=20
   ```
3. Перевірте ресурси кластера - мають відображатися CPU, RAM, nodes

## Troubleshooting

### Якщо все ще "Invalid request signature"

1. Перевірте, що ви використовуєте правильну адресу Agent:
   ```bash
   # Отримати NodePort
   sudo kubectl get svc portainer-agent -n portainer -o jsonpath='{.spec.ports[0].nodePort}'
   
   # Отримати IP ноди, де працює Portainer
   sudo kubectl get pods -n portainer -l app=portainer -o wide
   ```

2. Перевірте, що Agent працює:
   ```bash
   sudo kubectl get pods -n portainer -l app=portainer-agent
   ```

3. Спробуйте використати IP адресу замість Service DNS:
   - Визначте ноду, де працює Portainer UI
   - Використайте IP цієї ноди з NodePort

### Якщо все ще "client sent an HTTP request to an HTTPS server"

Це означає, що Portainer UI намагається підключитися через HTTP. Переконайтеся, що:
- Ви використовуєте правильну адресу (Service DNS або IP з NodePort)
- Ви не вказуєте протокол явно (Portainer автоматично визначає HTTPS для Agent)
