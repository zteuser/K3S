#!/bin/bash
# Скрипт для генерації SSH ключа для CI/CD workflow
# Використання: ./setup-ssh-key.sh [key-name]

KEY_NAME=${1:-id_ed25519_github_actions}
KEY_PATH="$HOME/.ssh/$KEY_NAME"

echo "Генерація SSH ключа для GitHub Actions..."
echo "Ім'я ключа: $KEY_NAME"
echo ""

# Генерація ключа
ssh-keygen -t ed25519 -f "$KEY_PATH" -C "github-actions-control-node" -N ""

echo ""
echo "✅ SSH ключ створено!"
echo ""
echo "📋 Публічний ключ (додайте його до ~/.ssh/authorized_keys на control node):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "${KEY_PATH}.pub"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔐 Приватний ключ (додайте його до GitHub Secrets як SSH_PRIVATE_KEY):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "$KEY_PATH"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 Інструкції:"
echo "1. Скопіюйте публічний ключ вище і додайте його на control node (macmini7):"
echo "   ssh-copy-id -i ${KEY_PATH}.pub user@macmini7"
echo ""
echo "2. Скопіюйте приватний ключ вище і додайте його до GitHub Secrets:"
echo "   Settings → Secrets and variables → Actions → New repository secret"
echo "   Name: SSH_PRIVATE_KEY"
echo "   Value: [вставте приватний ключ]"
echo ""
echo "3. Додайте інші необхідні secrets (див. .github/workflows/README.md)"

