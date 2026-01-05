# Конфігурація Port Forwarding для UCG Ultra

## Параметри Port Forwarding

- **Зовнішній порт (WAN)**: `22222`
- **Внутрішній порт (LAN)**: `22` (стандартний SSH порт)
- **Протокол**: `TCP`
- **Внутрішня IP адреса**: IP адреса macmini7 (наприклад: `192.168.1.100`)
- **Зовнішня IP адреса**: Публічна IP адреса роутера (або `0.0.0.0` для всіх інтерфейсів)

## Налаштування через UniFi Controller (Web UI)

### Крок 1: Відкрити налаштування роутера
1. Увійдіть в UniFi Controller
2. Перейдіть до **Devices** → виберіть ваш UCG Ultra
3. Натисніть **Settings** → **Port Forwarding**

### Крок 2: Створити Port Forwarding Rule

**Параметри для додавання:**

```
Name: SSH-macmini7-GitHub-Actions
Enabled: ✓ (увімкнено)
Interface: WAN (або All, якщо потрібно)
Protocol: TCP
Port Range: 22222 (або 22222-22222)
Forward IP: [IP адреса macmini7, наприклад: 192.168.1.100]
Forward Port: 22
```

### Крок 3: Застосувати зміни
1. Натисніть **Apply Changes**
2. Дочекайтеся застосування конфігурації

## Налаштування через SSH (CLI)

Якщо потрібно налаштувати через командний рядок:

```bash
# Підключитися до UCG Ultra через SSH
ssh admin@<ucg-ultra-ip>

# Перейти в режим налаштування
configure

# Створити port forwarding правило
set port-forward rule SSH-macmini7-GitHub-Actions interface WAN
set port-forward rule SSH-macmini7-GitHub-Actions forward-interface LAN
set port-forward rule SSH-macmini7-GitHub-Actions protocol tcp
set port-forward rule SSH-macmini7-GitHub-Actions original-port 22222
set port-forward rule SSH-macmini7-GitHub-Actions forward-port 22
set port-forward rule SSH-macmini7-GitHub-Actions forward-ip 192.168.1.100

# Зберегти та застосувати
commit
save
```

## Альтернативна конфігурація через JSON (UniFi API)

Якщо використовується UniFi API або конфігурація через JSON:

```json
{
  "name": "SSH-macmini7-GitHub-Actions",
  "enabled": true,
  "interface": "wan",
  "protocol": "tcp",
  "dst_port": "22222",
  "fwd": "192.168.1.100",
  "fwd_port": "22"
}
```

## Перевірка конфігурації

### Перевірка зовнішнього доступу:
```bash
# З зовнішньої мережі (наприклад, з GitHub Actions runner)
ssh -p 22222 user@<public-ip-роутера>

# Або з тестового сервера
telnet <public-ip-роутера> 22222
```

### Перевірка з внутрішньої мережі:
```bash
# Пряме підключення до macmini7
ssh user@192.168.1.100
```

## Безпека

### Рекомендації:

1. **Змініть стандартний SSH порт на macmini7** (опціонально, але рекомендовано):
   ```bash
   # На macmini7: /etc/ssh/sshd_config
   Port 2222  # замість 22
   ```

2. **Обмежте доступ по IP** (якщо підтримується):
   - Дозвольте доступ тільки з IP адрес GitHub Actions runners
   - GitHub Actions IP ranges: https://api.github.com/meta

3. **Використовуйте SSH ключі** замість паролів:
   - Вимкніть password authentication на macmini7
   - Використовуйте тільки key-based authentication

4. **Налаштуйте firewall на macmini7**:
   ```bash
   # Ubuntu firewall (ufw)
   sudo ufw allow ssh
   sudo ufw enable
   
   # Або для iptables
   sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
   ```

## Troubleshooting

### Проблема: Підключення не працює

1. **Перевірте, чи працює SSH на macmini7**:
   ```bash
   sudo systemctl status ssh  # Ubuntu
   # Має показати: Active: active (running)
   ```

2. **Перевірте firewall на роутері**:
   - Переконайтеся, що порт 22222 відкритий на WAN інтерфейсі
   - Перевірте, чи немає блокування в firewall rules

3. **Перевірте NAT таблицю**:
   ```bash
   # На роутері (якщо доступний)
   iptables -t nat -L -n | grep 22222
   ```

4. **Перевірте логи**:
   ```bash
   # На macmini7
   tail -f /var/log/system.log | grep sshd
   ```

### Проблема: Підключення працює, але повільно

- Перевірте MTU налаштування
- Перевірте, чи немає обмежень bandwidth
- Розгляньте використання SSH compression: `ssh -C`

## Додаткові налаштування для GitHub Actions

Після налаштування port forwarding, додайте до GitHub Secrets:

- `ROUTER_PUBLIC_IP` - Публічна IP адреса роутера
- `CONTROL_NODE_PORT` - `22222` (або залиште порожнім для використання за замовчуванням)
- `CONTROL_NODE_USER` - Користувач на macmini7
- `DEPLOY_PATH` - Шлях для deployment
- `SSH_PRIVATE_KEY` - Приватний SSH ключ

