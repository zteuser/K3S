# CI/CD Workflow для Deploy на Control Node

## Опис

Цей workflow автоматично копіює файли проекту на control node (macmini7) при push до гілки `main`.

## Налаштування GitHub Secrets

Для роботи workflow потрібно налаштувати наступні secrets в GitHub репозиторії:

### Обов'язкові Secrets:

1. **SSH_PRIVATE_KEY** - Приватний SSH ключ для доступу до control node
   ```bash
   # Якщо потрібно створити новий ключ:
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_control_node -N ""
   
   # Скопіювати приватний ключ:
   cat ~/.ssh/id_ed25519_control_node
   ```

2. **ROUTER_PUBLIC_IP** - Публічна IP адреса роутера (UCG Ultra)
   ```
   Приклад: 203.0.113.42
   Примітка: Це IP адреса роутера, через який працює port forwarding
   ```

3. **CONTROL_NODE_USER** - Користувач для SSH підключення на macmini7
   ```
   Приклад: omartyny
   ```

4. **DEPLOY_PATH** - Шлях на control node, куди копіювати файли
   ```
   Приклад: /Users/omartyny/WORK/k3s або /home/omartyny/k3s
   ```

### Опціональні Secrets:

5. **CONTROL_NODE_PORT** - SSH порт через port forwarding (за замовчуванням 22222)
   ```
   Приклад: 22222
   Примітка: Це зовнішній порт на роутері, який forward'иться на порт 22 macmini7
   ```

## Налаштування SSH на Control Node

1. Додайте публічний SSH ключ до `~/.ssh/authorized_keys` на control node:
   ```bash
   # На control node (macmini7):
   cat ~/.ssh/id_ed25519_control_node.pub >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

2. Переконайтеся, що SSH сервіс запущений:
   ```bash
   # Ubuntu:
   sudo systemctl enable ssh
   sudo systemctl start ssh
   
   # Перевірка:
   sudo systemctl status ssh
   ssh localhost
   ```

## Якщо Control Node за NAT

Якщо control node знаходиться за NAT і недоступна напряму, використайте один з варіантів:

### ⚠️ ВАЖЛИВО: CGNAT (Carrier-Grade NAT)

**Якщо роутер UCG Ultra знаходиться за CGNAT**, прямий port forwarding **НЕ ПРАЦЮЄ**. 
Використайте **Reverse SSH Tunnel** (Варіант 3) або **Jump Host** (Варіант 2).

### Варіант 1: Прямий доступ через Port Forwarding

**Використовуйте ТІЛЬКИ якщо роутер має публічну IP адресу (не CGNAT)**

Якщо налаштовано port forwarding на роутері (UCG Ultra), використайте основний workflow (`deploy-to-control-node.yml`).

**Налаштування Port Forwarding:**
- Зовнішній порт (WAN): `22222`
- Внутрішній порт (LAN): `22` (SSH на macmini7)
- Протокол: `TCP`
- Внутрішня IP: IP адреса macmini7 (наприклад: `192.168.1.100`)

**Детальні інструкції:** Див. `.github/router-config/ucg-ultra-port-forwarding.md`

**GitHub Secrets для Port Forwarding:**
- `ROUTER_PUBLIC_IP` - Публічна IP адреса роутера
- `CONTROL_NODE_PORT` - `22222` (або залиште порожнім для використання за замовчуванням)
- `CONTROL_NODE_USER` - Користувач на macmini7
- `DEPLOY_PATH` - Шлях для deployment
- `SSH_PRIVATE_KEY` - Приватний SSH ключ

### Варіант 2: SSH Tunnel через Jump Host

Якщо є проміжний сервер (jump host), який має доступ до control node, використайте workflow `deploy-to-control-node-nat.yml`.

**Додаткові Secrets для NAT workflow:**

- **JUMP_HOST** - IP або hostname jump host сервера
- **JUMP_HOST_USER** - Користувач для jump host
- **JUMP_HOST_SSH_KEY** - Приватний SSH ключ для jump host (якщо відрізняється від основного)
- **JUMP_HOST_PORT** - SSH порт jump host (за замовчуванням 22)

### Варіант 3: Master Node + WireGuard Tunnel (Рекомендовано для CGNAT) ⭐

**Використовуйте якщо роутер за CGNAT та є master-node з WireGuard**

Використовуємо master-node (Amper master) як jump server та існуючий WireGuard tunnel.

**Workflow:** `deploy-to-control-node-cgnat.yml`

**Архітектура:**
```
GitHub Actions → Master Node (141.144.254.42) → WireGuard Tunnel → macmini7 (за CGNAT)
```

**Детальні інструкції:** Див. `.github/router-config/master-node-wireguard-setup.md`

**GitHub Secrets для Master Node + WireGuard:**
- `MASTER_NODE_PUBLIC_IP` - Публічна IP master-node (`141.144.254.42`)
- `MASTER_NODE_USER` - Користувач на master-node
- `MASTER_NODE_SSH_KEY` - Приватний SSH ключ для master-node
- `MASTER_NODE_PORT` - SSH порт master-node (за замовчуванням 22)
- `CONTROL_NODE_LOCAL_IP` - Локальна IP адреса macmini7 (`192.168.2.19`)
- `CONTROL_NODE_USER` - Користувач на macmini7
- `CONTROL_NODE_SSH_PORT` - SSH порт на macmini7 (за замовчуванням 22)
- `DEPLOY_PATH` - Шлях для deployment

**Альтернатива: Reverse SSH Tunnel**

Якщо потрібен reverse SSH tunnel замість прямого доступу через WireGuard, див. `.github/router-config/cgnat-reverse-ssh-tunnel.md`

## Тестування

Після налаштування secrets, зробіть commit і push до гілки `main`:

```bash
git add .github/workflows/
git commit -m "Add CI/CD workflow"
git push origin main
```

Перевірте виконання workflow в GitHub Actions: `https://github.com/zteuser/K3S/actions`

## Ручний запуск

Workflow можна запустити вручну через GitHub UI:
1. Перейдіть до вкладки "Actions"
2. Виберіть workflow "Deploy to Control Node"
3. Натисніть "Run workflow"

