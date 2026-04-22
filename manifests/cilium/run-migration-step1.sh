#!/bin/bash
# Крок 1 міграції: додати flannel-backend:none + зупинити k3s
# Запускати з машини з SSH до нод (malex@)
#
# Використання: ./run-migration-step1.sh
# Опційно: SSH_USER=ubuntu для віддаленого користувача (не перезаписує $USER сесії)

set -euo pipefail
SSH_REMOTE_USER="${SSH_USER:-malex}"

echo "=== 1. Додаємо flannel-backend:none на server-нодах ==="
for node in macmini7:192.168.2.19 beelinkeqr5:192.168.1.19 master-node:10.0.10.10; do
  name="${node%%:*}"
  ip="${node##*:}"
  echo "  $name ($ip)..."
  # <<'REMOTE' — без локальної підстановки; віддалений bash виконує тіло heredoc.
  # Каталог k3s задаємо явно (не через $(dirname ...) — однозначно на ноді).
  # Віддалений bash — окремий процес від локального set рядка 8; код виходу SSH = код віддаленого bash (не «подвійний» set -e).
  if ! ssh -o ConnectTimeout=20 "${SSH_REMOTE_USER}@${ip}" "sudo bash -s" <<'REMOTE'
set -euo pipefail
cfg=/etc/rancher/k3s/config.yaml
sudo install -d /etc/rancher/k3s
pat='^[[:space:]]*flannel-backend:[[:space:]]*none([[:space:]]|$|#)'
if sudo test -f "$cfg" && sudo grep -qE "$pat" "$cfg" 2>/dev/null; then
  exit 0
fi
printf '\n# Cilium migration\nflannel-backend: none\ndisable-network-policy: true\n' | sudo tee -a "$cfg" >/dev/null
sudo grep -qE "$pat" "$cfg" || { echo "Перевірка: після запису не знайдено flannel-backend: none у $cfg" >&2; exit 1; }
REMOTE
  then
    echo "Помилка SSH або підготовки k3s config на $name ($ip)" >&2
    exit 1
  fi
done

echo ""
echo "=== 2. Зупиняємо k3s-agent на work-node ==="
ssh -o ConnectTimeout=20 "${SSH_REMOTE_USER}@10.0.10.20" "sudo systemctl stop k3s-agent" || { echo "Помилка work-node" >&2; exit 1; }

echo ""
echo "=== 3. Зупиняємо k3s на server-нодах ==="
for node in macmini7:192.168.2.19 beelinkeqr5:192.168.1.19 master-node:10.0.10.10; do
  name="${node%%:*}"
  ip="${node##*:}"
  echo "  $name ($ip)..."
  ssh -o ConnectTimeout=20 "${SSH_REMOTE_USER}@${ip}" "sudo systemctl stop k3s" || { echo "Помилка $name" >&2; exit 1; }
done

echo ""
echo "=== 4. Видаляємо flannel.1 (опційно) ==="
for node in macmini7:192.168.2.19 beelinkeqr5:192.168.1.19 master-node:10.0.10.10 work-node:10.0.10.20; do
  name="${node%%:*}"
  ip="${node##*:}"
  echo "  $name ($ip)..."
  # SSH-невдача → вихід; відсутній flannel.1 — не помилка (не маскувати через || true на ssh)
  if ! ssh -o ConnectTimeout=20 "${SSH_REMOTE_USER}@${ip}" \
    "if sudo ip link show flannel.1 &>/dev/null; then sudo ip link delete flannel.1; fi"; then
    echo "Помилка SSH (видалення flannel.1) на $name ($ip)" >&2
    exit 1
  fi
done

echo ""
echo "Готово. Далі: запустити k3s на server-нодах, встановити Cilium, запустити agent."
