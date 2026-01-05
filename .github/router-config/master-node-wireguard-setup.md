# Налаштування доступу через Master Node та WireGuard

## Архітектура

```
GitHub Actions → Master Node (141.144.254.42) → WireGuard Tunnel → VRN625 (192.168.2.1) → macmini7 (192.168.2.19)
```

**Важливо:**
- WireGuard tunnel **термінується на роутері VRN625**, а не на macmini7
- macmini7 має локальну IP адресу **192.168.2.19**
- Шлюз за замовчуванням для macmini7: **192.168.2.1** (VRN625)

## Інформація про Master Node

- **Публічний IP**: `141.144.254.42`
- **Внутрішній IP**: `10.0.10.10`
- **Hostname**: master-node (Amper master)

## Вимоги

1. **SSH доступ** до master-node з GitHub Actions
2. **WireGuard tunnel** між master-node та macmini7 (вже налаштовано)
3. **SSH доступ** з master-node до macmini7 через WireGuard IP

## Крок 1: Перевірка WireGuard Tunnel

### На master-node:

```bash
# Перевірка статусу WireGuard
sudo wg show

# Перевірка маршрутів до мережі 192.168.2.0/24
ip route | grep 192.168.2
```

### На VRN625 (роутер):

```bash
# Перевірка статусу WireGuard
wg show

# Перевірка маршрутів
ip route show
```

### На macmini7:

```bash
# Перевірка локальної IP адреси
ip addr show | grep 192.168.2

# Перевірка шлюзу за замовчуванням
ip route | grep default
# Має показати: default via 192.168.2.1
```

**Важливо:** 
- WireGuard tunnel термінується на VRN625, а не на macmini7
- macmini7 має локальну IP адресу **192.168.2.19**
- Шлюз за замовчуванням: **192.168.2.1** (VRN625)

## Крок 2: Перевірка SSH доступу з master-node до macmini7

### На master-node:

```bash
# Тест підключення до macmini7 через локальну IP
ssh user@192.168.2.19

# Перевірка маршруту до macmini7
ip route get 192.168.2.19
# Має показати маршрут через WireGuard інтерфейс
```

Якщо підключення не працює, перевірте:
1. Чи працює SSH на macmini7: `sudo systemctl status ssh`
2. Чи дозволено SSH через firewall на macmini7
3. Чи правильно налаштована маршрутизація в WireGuard

## Крок 3: Створення SSH ключа для GitHub Actions

### На вашій машині або master-node:

```bash
# Створення SSH ключа для підключення до master-node
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_github_actions_master -C "github-actions-master-node"
```

### Додавання публічного ключа на master-node:

```bash
# Скопіюйте публічний ключ на master-node
ssh-copy-id -i ~/.ssh/id_ed25519_github_actions_master.pub ubuntu@141.144.254.42

# Або вручну:
cat ~/.ssh/id_ed25519_github_actions_master.pub | ssh ubuntu@141.144.254.42 "cat >> ~/.ssh/authorized_keys"
```

### Налаштування SSH ключів для доступу до macmini7:

**Важливо:** GitHub Actions підключається до macmini7 через master-node, тому потрібно налаштувати SSH ключі на master-node для доступу до macmini7.

```bash
# На master-node - створіть SSH ключ (якщо ще немає)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_macmini7 -C "master-node-to-macmini7"

# Скопіюйте публічний ключ на macmini7
ssh-copy-id -i ~/.ssh/id_ed25519_macmini7.pub malex@192.168.2.19

# Або вручну на macmini7:
# Додайте публічний ключ до ~/.ssh/authorized_keys
```

**Примітка:** Користувач на macmini7: `malex` (або інший, залежно від вашого налаштування)

**Важливо:** Для роботи GitHub Actions потрібен безпарольний доступ. 

### Налаштування SSH config на master-node:

Після створення ключа та додавання його на macmini7, налаштуйте SSH config на master-node:

```bash
# На master-node
cat >> ~/.ssh/config << EOF
Host 192.168.2.19 macmini7
  HostName 192.168.2.19
  User malex
  IdentityFile ~/.ssh/id_ed25519_macmini7
  StrictHostKeyChecking no
  ServerAliveInterval 60
  ServerAliveCountMax 3
EOF

chmod 600 ~/.ssh/config
```

### Перевірка безпарольного доступу:

```bash
# На master-node - тест безпарольного підключення
ssh 192.168.2.19
# або
ssh macmini7
# Має підключитися без запиту пароля
```

### Якщо все ще запитує пароль:

1. **Перевірте права доступу на macmini7:**
   ```bash
   # На macmini7
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ls -la ~/.ssh/
   # Має показати:
   # drwx------  .ssh
   # -rw-------  authorized_keys
   ```

2. **Перевірте, чи правильно додано ключ:**
   ```bash
   # На macmini7
   cat ~/.ssh/authorized_keys
   # Має містити публічний ключ з master-node
   # Порівняйте з:
   # На master-node
   cat ~/.ssh/id_ed25519_macmini7.pub
   ```

3. **Перевірте SSH конфігурацію на macmini7:**
   ```bash
   # На macmini7
   sudo grep -E "PubkeyAuthentication|AuthorizedKeysFile" /etc/ssh/sshd_config
   # Має бути:
   # PubkeyAuthentication yes
   # AuthorizedKeysFile .ssh/authorized_keys
   ```

4. **Перевірка з verbose режимом:**
   ```bash
   # На master-node
   ssh -v 192.168.2.19
   # Подивіться на вивід, чи використовується ключ
   # Шукайте рядки типу: "Offering public key" або "Authentications that can continue: publickey"
   ```

## Крок 4: Налаштування GitHub Secrets

**✅ Всі перевірки завершені успішно!**
- ✅ Ping працює: `192.168.2.19` доступний з master-node
- ✅ Маршрутизація працює: трафік йде через `wg1` (WireGuard)
- ✅ SSH підключення працює: можна підключитися до macmini7
- ✅ Безпарольний доступ налаштовано: SSH config працює

Додайте до GitHub Secrets:

| Secret Name | Опис | Приклад |
|------------|------|---------|
| `MASTER_NODE_PUBLIC_IP` | Публічна IP master-node | `141.144.254.42` |
| `MASTER_NODE_USER` | Користувач на master-node | `ubuntu` |
| `MASTER_NODE_SSH_KEY` | Приватний SSH ключ для master-node | Згенерований вище |
| `MASTER_NODE_PORT` | SSH порт master-node (опціонально) | `22` |
| `CONTROL_NODE_LOCAL_IP` | Локальна IP адреса macmini7 | `192.168.2.19` |
| `CONTROL_NODE_USER` | Користувач на macmini7 | `malex` (або інший користувач) |
| `CONTROL_NODE_SSH_PORT` | SSH порт на macmini7 (опціонально) | `22` |
| `DEPLOY_PATH` | Шлях для deployment на macmini7 | `/home/malex/WORK/k3s` (або інший шлях) |

## Крок 5: Перевірка маршрутизації

### На master-node перевірте, чи маршрутизується трафік до macmini7:

```bash
# Перевірка маршруту до локальної IP macmini7
ip route get 192.168.2.19

# Перевірка ping
ping -c 3 192.168.2.19

# Перевірка маршруту до всієї мережі 192.168.2.0/24
ip route | grep 192.168.2
```

### Якщо маршрутизація не працює:

1. Перевірте WireGuard конфігурацію на master-node:
   ```bash
   sudo cat /etc/wireguard/wg*.conf
   ```
   **Важливо:** AllowedIPs має включати мережу `192.168.2.0/24` або принаймні `192.168.2.19/32`

2. Перевірте WireGuard конфігурацію на VRN625:
   ```bash
   # На VRN625
   wg showconf wgclt1
   ```
   Переконайтеся, що VRN625 має маршрути до мережі 192.168.2.0/24

3. Перевірте iptables правила на master-node:
   ```bash
   sudo iptables -L FORWARD -n -v
   ```

4. Перевірте маршрутизацію на VRN625:
   ```bash
   # На VRN625
   ip route show
   # Має бути маршрут до 192.168.2.0/24 через локальний інтерфейс
   ```

## Крок 6: Тестування підключення

### З вашої машини (симуляція GitHub Actions):

```bash
# Підключення до master-node
ssh -i ~/.ssh/id_ed25519_github_actions_master ubuntu@141.144.254.42

# З master-node підключення до macmini7
ssh malex@192.168.2.19
```

**Примітка:** Після першого підключення SSH запитає підтвердження host key. Для GitHub Actions це обробляється автоматично через `StrictHostKeyChecking no`.

### Приклад успішної перевірки:

```bash
# На master-node
ubuntu@master-node:~$ ping 192.168.2.19
PING 192.168.2.19 (192.168.2.19) 56(84) bytes of data.
64 bytes from 192.168.2.19: icmp_seq=1 ttl=63 time=21.7 ms
^C
--- 192.168.2.19 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss

ubuntu@master-node:~$ ip route get 192.168.2.19
192.168.2.19 dev wg1 src 192.168.100.5 uid 1001 
    cache 
```

**Результат:** 
- ✅ Ping працює (0% packet loss)
- ✅ Маршрут йде через `wg1` (WireGuard інтерфейс)
- ✅ Source IP: `192.168.100.5` (WireGuard IP master-node)
- ✅ TTL=63 вказує на правильну маршрутизацію через tunnel

### Використання SSH config (як в workflow):

Створіть `~/.ssh/config` для тестування:

```ssh-config
Host master-node
  HostName 141.144.254.42
  User ubuntu
  IdentityFile ~/.ssh/id_ed25519_github_actions_master
  StrictHostKeyChecking no

Host control-node
  HostName 192.168.2.19
  User malex
  ProxyJump master-node
  StrictHostKeyChecking no
```

Тест:
```bash
ssh control-node
```

## Troubleshooting

### Проблема: Не можу підключитися до master-node

1. Перевірте публічну IP: `ping 141.144.254.42`
2. Перевірте SSH порт: `telnet 141.144.254.42 22`
3. Перевірте firewall на master-node
4. Перевірте SSH ключі та authorized_keys

### Проблема: Не можу підключитися до macmini7 з master-node

1. Перевірте WireGuard tunnel:
   ```bash
   # На master-node
   sudo wg show
   ping 192.168.2.19
   ```

2. Перевірте маршрутизацію:
   ```bash
   # На master-node
   ip route get 192.168.2.19
   # Має показати маршрут через WireGuard інтерфейс
   ```

3. Перевірте маршрутизацію на VRN625:
   ```bash
   # На VRN625
   ip route show | grep 192.168.2
   ping 192.168.2.19
   ```

3. Перевірте SSH на macmini7:
   ```bash
   # На macmini7
   sudo systemctl status ssh
   ```

4. Перевірте firewall на macmini7:
   ```bash
   # На macmini7
   sudo ufw status
   ```

### Проблема: Workflow не може підключитися

1. Перевірте всі GitHub Secrets, особливо `CONTROL_NODE_LOCAL_IP` = `192.168.2.19`
2. Перевірте логи workflow в GitHub Actions
3. Перевірте SSH config в workflow
4. Перевірте, чи правильно вказано локальну IP macmini7 (`192.168.2.19`)
5. Перевірте маршрутизацію з master-node до 192.168.2.19

## Примітка про архітектуру

WireGuard tunnel термінується на роутері VRN625, тому:
- macmini7 не має прямого WireGuard IP
- Використовується локальна IP адреса macmini7: **192.168.2.19**
- VRN625 (192.168.2.1) виконує маршрутизацію між WireGuard tunnel та локальною мережею 192.168.2.0/24

## Безпека

1. **Використовуйте SSH ключі** замість паролів
2. **Обмежте SSH доступ** на master-node по IP (якщо можливо)
3. **Вимкніть password authentication** на обох серверах
4. **Регулярно оновлюйте** системи та SSH

