# Налаштування доступу через Master Node та WireGuard

## Проблема CGNAT

Якщо роутер UCG Ultra знаходиться за CGNAT (Carrier-Grade NAT), прямий port forwarding недоступний, оскільки провайдер не може перенаправити порти на ваш роутер.

## Рішення: Master Node + WireGuard Tunnel

Використовуємо master-node (Amper master) як jump server з публічним IP, та існуючий WireGuard tunnel для доступу до macmini7.

## Архітектура

```
GitHub Actions → Master Node (141.144.254.42) → WireGuard Tunnel → macmini7 (за CGNAT)
```

**Примітка:** Якщо потрібен reverse SSH tunnel замість прямого доступу через WireGuard, див. альтернативні рішення в кінці документа.

## Вимоги

1. **Jump Server** з публічною IP адресою (VPS, cloud instance)
   - Може бути будь-який сервер з публічною IP
   - Приклади: AWS EC2, DigitalOcean Droplet, Hetzner Cloud, тощо

2. **SSH доступ** до jump server з macmini7
3. **SSH доступ** до jump server з GitHub Actions

## Крок 1: Налаштування Jump Server

### 1.1 Створення користувача (опціонально)

```bash
# На jump server
sudo useradd -m -s /bin/bash github-actions
sudo mkdir -p /home/github-actions/.ssh
sudo chmod 700 /home/github-actions/.ssh
```

### 1.2 Налаштування SSH для reverse tunnel

Додайте до `/etc/ssh/sshd_config` на jump server:

```bash
# Дозволити reverse port forwarding
GatewayPorts yes
# Або для конкретного користувача:
Match User github-actions
    GatewayPorts yes
    AllowTcpForwarding yes
```

Перезапустіть SSH:
```bash
sudo systemctl restart sshd
```

## Крок 2: Налаштування на macmini7

### 2.1 Створення SSH ключа для jump server

```bash
# На macmini7
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_jump_server -C "macmini7-to-jump"
```

### 2.2 Додавання публічного ключа на jump server

```bash
# Скопіюйте публічний ключ на jump server
ssh-copy-id -i ~/.ssh/id_ed25519_jump_server.pub user@jump-server-ip
```

### 2.3 Встановлення autossh (для автоматичного перепідключення)

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y autossh

# CentOS/RHEL
sudo yum install -y autossh
```

### 2.4 Створення systemd service для Ubuntu (автозапуск)

Створіть файл `/etc/systemd/system/reverse-ssh-tunnel.service`:

```ini
[Unit]
Description=Reverse SSH Tunnel to Jump Server
After=network.target

[Service]
Type=simple
User=omartyny
Restart=always
RestartSec=10
ExecStart=/usr/bin/autossh -M 0 -N -R 22222:localhost:22 \
  -o ServerAliveInterval=60 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -i /home/omartyny/.ssh/id_ed25519_jump_server \
  user@jump-server-ip
ExecStop=/bin/kill -TERM $MAINPID

[Install]
WantedBy=multi-user.target
```

**Важливо:** Замініть:
- `User=omartyny` на вашого користувача
- `user@jump-server-ip` на ваші дані
- `22222` на порт, який буде слухати jump server (якщо потрібно інший)
- Шлях до SSH ключа (`/home/omartyny/.ssh/id_ed25519_jump_server`)

### 2.5 Активація та запуск systemd service

```bash
# Перезавантаження systemd
sudo systemctl daemon-reload

# Вмикання автозапуску
sudo systemctl enable reverse-ssh-tunnel.service

# Запуск сервісу
sudo systemctl start reverse-ssh-tunnel.service
```

### 2.6 Перевірка роботи tunnel

```bash
# Перевірка статусу
sudo systemctl status reverse-ssh-tunnel.service

# Перегляд логів
sudo journalctl -u reverse-ssh-tunnel -f

# Перевірка процесу
ps aux | grep autossh

# Тест підключення з jump server
ssh -p 22222 user@localhost  # на jump server
```

## Крок 3: Альтернатива - Ручне встановлення tunnel

Якщо не хочете використовувати systemd service, можна встановити tunnel вручну:

```bash
# На macmini7 (Ubuntu)
autossh -M 0 -N -R 22222:localhost:22 \
  -o ServerAliveInterval=60 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -i ~/.ssh/id_ed25519_jump_server \
  user@jump-server-ip
```

**Примітка:** Для постійної роботи рекомендовано використовувати systemd service або скрипт `setup-reverse-tunnel.sh`.

## Крок 4: Налаштування GitHub Secrets

Додайте до GitHub Secrets:

| Secret | Опис | Приклад |
|--------|------|---------|
| `JUMP_SERVER_HOST` | IP або hostname jump server | `203.0.113.42` |
| `JUMP_SERVER_USER` | Користувач на jump server | `github-actions` |
| `JUMP_SERVER_SSH_KEY` | Приватний SSH ключ для jump server | Згенеруйте окремий ключ |
| `JUMP_SERVER_PORT` | SSH порт jump server (опціонально) | `22` |
| `REVERSE_TUNNEL_PORT` | Порт reverse tunnel (опціонально) | `22222` |
| `CONTROL_NODE_USER` | Користувач на macmini7 | `omartyny` |
| `DEPLOY_PATH` | Шлях для deployment | `/Users/omartyny/WORK/k3s` |

## Крок 5: Створення SSH ключа для GitHub Actions

```bash
# На вашій машині або jump server
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_github_actions_jump -C "github-actions-jump"

# Додайте публічний ключ до jump server
cat ~/.ssh/id_ed25519_github_actions_jump.pub >> ~/.ssh/authorized_keys

# Скопіюйте приватний ключ для GitHub Secrets
cat ~/.ssh/id_ed25519_github_actions_jump
```

## Перевірка

### З jump server:
```bash
# Перевірка, чи слухає порт
netstat -tlnp | grep 22222
# або
ss -tlnp | grep 22222

# Тест підключення
ssh -p 22222 user@localhost
```

### З GitHub Actions:
Після налаштування всіх secrets, зробіть push до репозиторію і перевірте workflow.

## Troubleshooting

### Tunnel не встановлюється

1. Перевірте SSH ключі:
   ```bash
   ssh -v -i ~/.ssh/id_ed25519_jump_server user@jump-server-ip
   ```

2. Перевірте GatewayPorts на jump server:
   ```bash
   grep GatewayPorts /etc/ssh/sshd_config
   ```

3. Перевірте firewall на jump server:
   ```bash
   sudo ufw status
   sudo iptables -L -n
   ```

### Tunnel встановлюється, але GitHub Actions не може підключитися

1. Перевірте, чи слухає jump server порт:
   ```bash
   netstat -tlnp | grep 22222
   ```

2. Перевірте SSH config на jump server для GatewayPorts

3. Перевірте firewall rules на jump server

### Tunnel часто розривається

1. Збільште ServerAliveInterval:
   ```bash
   -o ServerAliveInterval=30
   ```

2. Перевірте мережеве з'єднання macmini7

3. Використовуйте autossh замість звичайного ssh

## Альтернативні рішення

### 1. Cloudflare Tunnel
Якщо не хочете використовувати jump server, можна використати Cloudflare Tunnel:
- Безкоштовний
- Не потрібен публічний сервер
- Простіше налаштування

### 2. WireGuard VPN
Налаштуйте WireGuard VPN між macmini7 та сервером з публічною IP.

### 3. Tailscale / ZeroTier
Використовуйте mesh VPN для доступу до macmini7.

