#!/bin/bash
# Видалити старі ядра, залишити 3 останні
# Запускати на master-node: sudo ./cleanup-old-kernels.sh

set -e

echo "=== Встановлені ядра ==="
dpkg -l | grep '^ii' | grep -E 'linux-image-[0-9]' | awk '{print $2}' | sort -V

TO_REMOVE=$(dpkg -l | grep '^ii' | grep -E 'linux-image-[0-9]' | awk '{print $2}' | sort -V | head -n -3)

if [ -z "$TO_REMOVE" ]; then
  echo "Немає зайвих ядер для видалення."
  exit 0
fi

echo ""
echo "=== Буде видалено ==="
echo "$TO_REMOVE"
echo ""
# Для неінтерактивного запуску: ./cleanup-old-kernels.sh -y
if [[ "$1" != "-y" && "$1" != "--yes" ]]; then
  read -p "Продовжити? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Скасовано."
    exit 0
  fi
fi

sudo apt purge -y $TO_REMOVE
sudo apt autoremove -y
sudo update-initramfs -u
sudo update-grub

echo ""
echo "Готово. Залишено 3 останні ядра."
