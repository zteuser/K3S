# Виправлення адреси Environment в Portainer UI

## Проблема

Environment в Portainer UI показує статус "Down" або "Disconnected" з помилкою "The environment is unreachable".

## Причина

Environment налаштований на неправильну адресу або NodePort змінився після перестворення Service.

## Рішення

### Варіант 1: Оновлення адреси існуючого environment

1. **Відкрийте Portainer UI** (http://192.168.2.19:30900 або https://192.168.2.19:30943)

2. **Знайдіть environment** в списку (наприклад, "k3s-cluster-vrn625")

3. **Натисніть на іконку редагування** (олівець) або на назву environment

4. **Перейдіть до вкладки "Settings"** або "Connection"

5. **Оновіть Environment address** на правильну адресу:
   ```
   192.168.2.19:30778
   ```
   (замініть 30778 на поточний NodePort, якщо він інший)

6. **Увімкніть "TLS"** або "Skip TLS verification" (якщо є така опція), оскільки Agent працює на HTTPS з самопідписаним сертифікатом

7. **Натисніть "Update environment"** або "Save"

### Варіант 2: Видалення та створення нового environment

Якщо оновлення не допомагає:

1. **Видаліть старий environment:**
   - Знайдіть environment в списку
   - Натисніть на іконку налаштувань (шестерня)
   - Виберіть "Remove environment"

2. **Створіть новий environment:**
   - Натисніть "Add environment"
   - Виберіть "Kubernetes" → "Agent"
   - Введіть:
     - **Name**: `k3s-cluster` (або будь-яка назва)
     - **Environment address**: `192.168.2.19:30778`
   - **Увімкніть "TLS"** або "Skip TLS verification" (якщо є така опція)
   - Натисніть "Connect"

## Перевірка поточного NodePort

Якщо не впевнені в поточному NodePort, перевірте:

```bash
# На macmini7
sudo kubectl get svc portainer-agent -n portainer -o jsonpath='{.spec.ports[0].nodePort}'
```

Або подивіться повну інформацію про Service:

```bash
sudo kubectl get svc portainer-agent -n portainer
```

## Перевірка доступності Agent

**Важливо:** Agent працює на **HTTPS**, а не HTTP!

Перевірте, що Agent доступний з IP адреси, яку ви використовуєте:

```bash
# З macmini7 (використовуйте -k для пропуску перевірки сертифіката)
curl -k -v https://192.168.2.19:30778/ping

# Або з master-node
curl -k -v https://10.0.10.10:30778/ping

# Або з work-node
curl -k -v https://10.0.10.20:30778/ping
```

Очікувана відповідь: `{"status":"ok"}` або подібна.

**Примітка:** Використовуйте `-k` (або `--insecure`) для пропуску перевірки TLS сертифіката, оскільки Agent використовує самопідписаний сертифікат.

## Troubleshooting

### Environment все ще "Down"

1. **Перевірте статус Agent Pod:**
   ```bash
   sudo kubectl get pods -n portainer -l app=portainer-agent
   ```
   Pod має бути в статусі `Running`.

2. **Перевірте логи Agent:**
   ```bash
   sudo kubectl logs -n portainer -l app=portainer-agent --tail=50
   ```

3. **Перевірте Service:**
   ```bash
   sudo kubectl get svc portainer-agent -n portainer
   ```
   Service має мати тип `NodePort` і порт `9001:30778/TCP` (або інший NodePort).

4. **Перевірте firewall:**
   ```bash
   # На macmini7
   sudo ufw status
   ```
   Переконайтеся, що порт NodePort не заблокований.

### "Connection refused" або "Timeout"

1. **Перевірте, що Pod працює на правильній ноді:**
   ```bash
   sudo kubectl get pods -n portainer -l app=portainer-agent -o wide
   ```

2. **Перевірте доступність порту з іншої машини:**
   ```bash
   # З master-node
   telnet 192.168.2.19 30778
   ```

3. **Перевірте маршрутизацію:**
   - Якщо Portainer UI працює на macmini7, використовуйте `192.168.2.19:30778`
   - Якщо Portainer UI працює на master-node, використовуйте `10.0.10.10:30778`
   - Якщо Portainer UI працює на work-node, використовуйте `10.0.10.20:30778`
