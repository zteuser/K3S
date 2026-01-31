# Оновлення всіх нод k3s до v1.34

Порядок оновлення: **спочатку server-ноди по одній, потім agent-ноди** (рекомендація k3s).

Цільова версія: **v1.34.3+k3s1** (як на beelinkeqr5).

Поточний стан:
- **beelinkeqr5** — вже v1.34.3+k3s1 (пропускаємо)
- **macmini7** — server, v1.33.4 → оновити
- **master-node**, **work-node** — agent, v1.33.4 → оновити

---

## Важливо: збереження конфігурації

При повторному запуску install-скрипта потрібно передати **ті самі** аргументи/змінні, що й при першому встановленні, інакше вони будуть перезаписані в systemd.

Краще спочатку переглянути поточну конфігурацію на кожній ноді:

```bash
# На server-ноді (macmini7, beelinkeqr5)
cat /etc/rancher/k3s/config.yaml
systemctl cat k3s

# На agent-ноді (master-node, work-node)
cat /etc/rancher/k3s/config.yaml
systemctl cat k3s-agent
```

Якщо є `/etc/rancher/k3s/config.yaml` з потрібними параметрами — install-скрипт його не змінює; достатньо передати лише `server` або `agent` і версію.

---

## 1. Оновлення server-ноди (macmini7)

Підключіться до **macmini7** (192.168.2.19).

Використайте **ті самі** аргументи, що й при першому встановленні. Типовий варіант для першого (і єдиного на той момент) server з etcd:

```bash
# На macmini7 (підставте ваш токен з /var/lib/rancher/k3s/server/node-token, якщо скрипт очікує --token)
export INSTALL_K3S_VERSION=v1.34.3+k3s1
curl -sfL https://get.k3s.io | sh -s - server --cluster-init --token <ВАШ_ТОКЕН>
```

Якщо при першому встановленні ви не передавали `--cluster-init` або використовували лише `server` — повторіть саме той варіант. Приклад без зміни аргументів (якщо все в config.yaml):

```bash
export INSTALL_K3S_VERSION=v1.34.3+k3s1
curl -sfL https://get.k3s.io | sh -s - server
```

Після оновлення перевірте:

```bash
kubectl get nodes
# macmini7 має показувати v1.34.3+k3s1
```

Дочекайтеся статусу **Ready** для macmini7, потім переходьте до agent-нод.

---

## 2. Оновлення agent-нод (master-node, work-node)

На кожній **worker**-ноді (master-node, work-node) виконайте оновлення **з тими самими** параметрами join, що й при встановленні.

Типова команда (підставте IP будь-якого server, наприклад 192.168.2.19 або 192.168.2.155, та токен):

```bash
# На master-node та work-node (по черзі або паралельно)
export INSTALL_K3S_VERSION=v1.34.3+k3s1
curl -sfL https://get.k3s.io | sh -s - agent \
  --server https://192.168.2.19:6443 \
  --token <K3S_TOKEN>
```

Якщо на agent використовується config-файл, достатньо:

```bash
export INSTALL_K3S_VERSION=v1.34.3+k3s1
curl -sfL https://get.k3s.io | sh -s - agent
```

Після оновлення на обох worker перевірте:

```bash
kubectl get nodes
```

Усі чотири ноди мають бути **Ready** і з версією **v1.34.3+k3s1**.

---

## 3. Перевірка після оновлення

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide | head -30
```

Якщо якась нода в NotReady — перегляньте логи:

- На server: `journalctl -u k3s -f`
- На agent: `journalctl -u k3s-agent -f`

---

## Коротко: порядок дій

| Крок | Нода       | Роль   | Дія |
|------|------------|--------|-----|
| —    | beelinkeqr5| server | Пропустити (вже 1.34) |
| 1    | macmini7   | server | `INSTALL_K3S_VERSION=v1.34.3+k3s1` + ті самі server-аргументи |
| 2    | master-node| agent  | `INSTALL_K3S_VERSION=v1.34.3+k3s1` + agent з `--server` та `--token` |
| 3    | work-node  | agent  | Те саме, що для master-node |

---

## Якщо потрібно лише завантажити бінарник без перезапуску

```bash
INSTALL_K3S_VERSION=v1.34.3+k3s1 INSTALL_K3S_SKIP_START=true curl -sfL https://get.k3s.io | sh -s - ...
```

Потім перезапуск вручну: `sudo systemctl restart k3s` або `sudo systemctl restart k3s-agent`.
