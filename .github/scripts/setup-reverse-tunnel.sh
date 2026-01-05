#!/bin/bash
# Скрипт для налаштування reverse SSH tunnel на Ubuntu (macmini7)
# Використання: ./setup-reverse-tunnel.sh <jump-server-user> <jump-server-ip> [tunnel-port]

set -e

JUMP_USER=${1:-"user"}
JUMP_HOST=${2:-""}
TUNNEL_PORT=${3:-22222}

if [ -z "$JUMP_HOST" ]; then
    echo "Помилка: Потрібно вказати IP адресу jump server"
    echo "Використання: $0 <jump-user> <jump-server-ip> [tunnel-port]"
    echo "Приклад: $0 github-actions 203.0.113.42 22222"
    exit 1
fi

echo "=== Налаштування Reverse SSH Tunnel ==="
echo "Jump Server: $JUMP_USER@$JUMP_HOST"
echo "Tunnel Port: $TUNNEL_PORT"
echo ""

# Перевірка autossh
if ! command -v autossh &> /dev/null; then
    echo "Встановлення autossh..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y autossh
    elif command -v yum &> /dev/null; then
        sudo yum install -y autossh
    else
        echo "Помилка: autossh не знайдено. Встановіть вручну:"
        echo "  Ubuntu/Debian: sudo apt-get install autossh"
        echo "  CentOS/RHEL: sudo yum install autossh"
        exit 1
    fi
fi

# Створення SSH ключа
SSH_KEY="$HOME/.ssh/id_ed25519_jump_server"
if [ ! -f "$SSH_KEY" ]; then
    echo "Створення SSH ключа..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -C "macmini7-to-jump" -N ""
    echo "✅ SSH ключ створено: $SSH_KEY"
else
    echo "ℹ️  SSH ключ вже існує: $SSH_KEY"
fi

# Копіювання публічного ключа
echo ""
echo "📋 Публічний ключ (додайте його до ~/.ssh/authorized_keys на jump server):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "${SSH_KEY}.pub"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
read -p "Натисніть Enter після додавання ключа на jump server..."

# Тест підключення
echo ""
echo "Тестування підключення до jump server..."
if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$JUMP_USER@$JUMP_HOST" "echo 'Connection successful'" 2>/dev/null; then
    echo "✅ Підключення до jump server успішне!"
else
    echo "⚠️  Не вдалося підключитися. Перевірте ключі та мережеве з'єднання."
    exit 1
fi

# Створення systemd service для Ubuntu/Linux
SERVICE_FILE="/etc/systemd/system/reverse-ssh-tunnel.service"
SERVICE_USER=$(whoami)

echo ""
echo "Створення systemd service для автозапуску..."

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Reverse SSH Tunnel to Jump Server
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
Restart=always
RestartSec=10
ExecStart=/usr/bin/autossh -M 0 -N -R ${TUNNEL_PORT}:localhost:22 \\
  -o ServerAliveInterval=60 \\
  -o ServerAliveCountMax=3 \\
  -o ExitOnForwardFailure=yes \\
  -i ${SSH_KEY} \\
  ${JUMP_USER}@${JUMP_HOST}
ExecStop=/bin/kill -TERM \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

# Перезавантаження systemd та вмикання сервісу
echo "Активація та запуск сервісу..."
sudo systemctl daemon-reload
sudo systemctl enable reverse-ssh-tunnel.service
sudo systemctl start reverse-ssh-tunnel.service

echo "✅ Systemd service створено та запущено!"
echo ""
echo "Перевірка статусу:"
sudo systemctl status reverse-ssh-tunnel.service --no-pager -l || true

echo ""
echo "Корисні команди:"
echo "  Перевірка статусу: sudo systemctl status reverse-ssh-tunnel"
echo "  Перегляд логів: sudo journalctl -u reverse-ssh-tunnel -f"
echo "  Перезапуск: sudo systemctl restart reverse-ssh-tunnel"
echo "  Зупинка: sudo systemctl stop reverse-ssh-tunnel"

echo ""
echo "=== Налаштування завершено! ==="
echo ""
echo "Наступні кроки:"
echo "1. Переконайтеся, що на jump server налаштовано GatewayPorts yes в /etc/ssh/sshd_config"
echo "2. Перезапустіть SSH на jump server: sudo systemctl restart sshd"
echo "3. Перевірте tunnel: ssh -p ${TUNNEL_PORT} user@localhost (на jump server)"
echo "4. Налаштуйте GitHub Secrets (див. .github/router-config/cgnat-reverse-ssh-tunnel.md)"

