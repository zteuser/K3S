# Швидкий старт: Налаштування CI/CD

## ⚠️ ВАЖЛИВО: Вибір методу доступу

**Якщо роутер UCG Ultra за CGNAT** (Carrier-Grade NAT) - використайте **Reverse SSH Tunnel** (див. нижче)

**Якщо роутер має публічну IP** - використайте **Port Forwarding** (див. нижче)

---

## Варіант A: Port Forwarding (тільки якщо НЕ CGNAT)

### Крок 1: Налаштування Port Forwarding на UCG Ultra

1. Відкрийте UniFi Controller
2. Перейдіть до **Devices** → ваш UCG Ultra → **Settings** → **Port Forwarding**
3. Додайте правило:
   - **Name**: `SSH-macmini7-GitHub-Actions`
   - **Interface**: `WAN`
   - **Protocol**: `TCP`
   - **Port Range**: `22222`
   - **Forward IP**: `[IP адреса macmini7, наприклад: 192.168.1.100]`
   - **Forward Port**: `22`

Детальні інструкції: `.github/router-config/ucg-ultra-port-forwarding.md`

## Крок 2: Створення SSH ключа

```bash
cd /Users/omartyny/WORK/k3s
./.github/scripts/setup-ssh-key.sh
```

Або вручну:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_github_actions -C "github-actions"
```

## Крок 3: Додавання публічного ключа на macmini7

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_github_actions.pub user@macmini7
```

Або вручну:
```bash
# На macmini7:
cat ~/.ssh/id_ed25519_github_actions.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

## Крок 4: Налаштування GitHub Secrets

Перейдіть до: `https://github.com/zteuser/K3S/settings/secrets/actions`

Додайте наступні secrets:

| Secret Name | Значення | Приклад |
|------------|----------|---------|
| `SSH_PRIVATE_KEY` | Приватний SSH ключ | `cat ~/.ssh/id_ed25519_github_actions` |
| `ROUTER_PUBLIC_IP` | Публічна IP роутера | `203.0.113.42` |
| `CONTROL_NODE_USER` | Користувач на macmini7 | `omartyny` |
| `DEPLOY_PATH` | Шлях для deployment | `/Users/omartyny/WORK/k3s` |
| `CONTROL_NODE_PORT` | Порт forwarding (опціонально) | `22222` |

## Крок 5: Перевірка підключення

```bash
# З вашої машини (тест port forwarding)
ssh -p 22222 user@<public-ip-роутера>
```

Якщо підключення працює, можна робити commit і push.

## Крок 6: Commit і Push

```bash
git add .github/
git commit -m "Configure CI/CD with port forwarding"
git push origin main
```

## Перевірка Workflow

Після push перевірте виконання workflow:
- `https://github.com/zteuser/K3S/actions`

## Troubleshooting

### Підключення не працює

1. Перевірте port forwarding на роутері
2. Перевірте, чи працює SSH на macmini7: `sudo systemctl status ssh`
3. Перевірте firewall на macmini7: `sudo ufw status`
4. Перевірте публічну IP адресу роутера

### Workflow падає з помилкою

1. Перевірте всі secrets в GitHub
2. Перевірте логи workflow в GitHub Actions
3. Перевірте SSH ключі та authorized_keys на macmini7

---

## Варіант B: Master Node + WireGuard Tunnel (для CGNAT) ⭐

### Крок 1: Перевірка WireGuard Tunnel

Переконайтеся, що WireGuard tunnel між master-node та VRN625 працює:

```bash
# На master-node
sudo wg show
ip route | grep 192.168.2

# На VRN625 (роутер)
wg show

# На macmini7 - перевірка локальної IP
ip addr show | grep 192.168.2
# Має показати: 192.168.2.19
```

**Важливо:** 
- WireGuard tunnel термінується на VRN625, а не на macmini7
- macmini7 має локальну IP: **192.168.2.19**
- Шлюз: **192.168.2.1** (VRN625)

### Крок 2: Перевірка SSH доступу

```bash
# З master-node тест підключення до macmini7
ssh user@192.168.2.19
```

### Крок 3: Створення SSH ключа для master-node

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_github_actions_master -C "github-actions-master"
ssh-copy-id -i ~/.ssh/id_ed25519_github_actions_master.pub user@141.144.254.42
```

### Крок 4: Налаштування GitHub Secrets

| Secret Name | Значення | Приклад |
|------------|----------|---------|
| `MASTER_NODE_PUBLIC_IP` | Публічна IP master-node | `141.144.254.42` |
| `MASTER_NODE_USER` | Користувач на master-node | `omartyny` |
| `MASTER_NODE_SSH_KEY` | Приватний SSH ключ для master-node | Згенерований вище |
| `CONTROL_NODE_LOCAL_IP` | Локальна IP macmini7 | `192.168.2.19` |
| `CONTROL_NODE_USER` | Користувач на macmini7 | `omartyny` |
| `DEPLOY_PATH` | Шлях для deployment | `/home/omartyny/WORK/k3s` |

### Крок 5: Використання workflow

Workflow `deploy-to-control-node-cgnat.yml` вже налаштований для використання master-node + WireGuard.

### Крок 6: Commit і Push

```bash
git add .github/
git commit -m "Configure CI/CD with reverse SSH tunnel for CGNAT"
git push origin main
```

---

## Детальна документація

- Повна інструкція: `.github/workflows/README.md`
- Port Forwarding: `.github/router-config/ucg-ultra-port-forwarding.md`
- Reverse SSH Tunnel (CGNAT): `.github/router-config/cgnat-reverse-ssh-tunnel.md`

