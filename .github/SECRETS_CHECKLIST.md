# GitHub Secrets Checklist

## Обов'язкові Secrets для `deploy-to-control-node-cgnat.yml`

Переконайтеся, що всі наступні secrets налаштовані в GitHub:

### ✅ Перевірка Secrets

1. **MASTER_NODE_PUBLIC_IP**
   - Значення: `141.144.254.42`
   - Перевірка: Не повинно бути порожнім

2. **MASTER_NODE_USER**
   - Значення: `ubuntu`
   - Перевірка: Не повинно бути порожнім

3. **MASTER_NODE_SSH_KEY**
   - Значення: Приватний SSH ключ для підключення до master-node
   - Як отримати:
     ```bash
     cat ~/.ssh/id_ed25519_github_actions_master
     ```
   - Перевірка: Має містити повний приватний ключ (включаючи `-----BEGIN` та `-----END`)

4. **CONTROL_NODE_LOCAL_IP**
   - Значення: `192.168.2.19`
   - Перевірка: Не повинно бути порожнім

5. **CONTROL_NODE_USER**
   - Значення: `malex`
   - Перевірка: Не повинно бути порожнім

6. **DEPLOY_PATH**
   - Значення: `/home/malex/WORK/k3s` (або інший шлях)
   - Перевірка: Не повинно бути порожнім

### Опціональні Secrets

7. **MASTER_NODE_PORT**
   - Значення: `22` (за замовчуванням)
   - Якщо не встановлено, використовується 22

8. **CONTROL_NODE_SSH_PORT**
   - Значення: `22` (за замовчуванням)
   - Якщо не встановлено, використовується 22

## Як додати Secrets в GitHub

1. Перейдіть до: `https://github.com/zteuser/K3S/settings/secrets/actions`
2. Натисніть "New repository secret"
3. Введіть Name та Value
4. Натисніть "Add secret"

## Перевірка після додавання

Після додавання всіх secrets, workflow автоматично перевірить їх наявність і виведе помилку, якщо щось відсутнє.

## Типові помилки

### "Could not resolve hostname : Name or service not known"
- **Причина:** Один з secrets порожній або не встановлений
- **Рішення:** Перевірте всі secrets вище

### "Permission denied (publickey)"
- **Причина:** SSH ключ неправильний або не додано на master-node
- **Рішення:** 
  1. Перевірте `MASTER_NODE_SSH_KEY` та додайте публічний ключ на master-node
  2. **КРИТИЧНО ВАЖЛИВО:** На master-node має бути налаштовано SSH config для підключення до macmini7:
     ```bash
     # На master-node перевірте:
     cat ~/.ssh/config | grep -A 5 "192.168.2.19"
     
     # Має бути:
     Host 192.168.2.19 macmini7
       HostName 192.168.2.19
       User malex
       IdentityFile ~/.ssh/id_ed25519_macmini7
       StrictHostKeyChecking no
       ServerAliveInterval 60
       ServerAliveCountMax 3
     ```
  3. Якщо SSH config відсутній, додайте його:
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
  4. Перевірте, що публічний ключ додано на macmini7:
     ```bash
     # На macmini7
     cat ~/.ssh/authorized_keys | grep "master-node-to-macmini7"
     ```
  5. Перевірте безпарольне підключення з master-node:
     ```bash
     # На master-node
     ssh 192.168.2.19
     # Має підключитися без запиту пароля
     ```

### "Connection refused"
- **Причина:** Неправильний порт або SSH не запущений
- **Рішення:** Перевірте `MASTER_NODE_PORT` та статус SSH на master-node

