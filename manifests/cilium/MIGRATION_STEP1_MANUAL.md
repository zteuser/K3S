# Крок 1 міграції — виконати вручну

macmini7 та beelinkeqr5 могли бути оновлені скриптом. **master-node** та **work-node** потребують ручного виконання (SSH до OCI).

---

## 1. Додати flannel-backend:none на server-нодах

На **кожній** server-ноді (macmini7, beelinkeqr5, master-node):

```bash
# Перевірити, чи вже додано
grep flannel-backend /etc/rancher/k3s/config.yaml

# Якщо немає — додати (sudo):
echo -e "\n# Cilium migration\nflannel-backend: none\ndisable-network-policy: true" | sudo tee -a /etc/rancher/k3s/config.yaml
```

---

## 2. Зупинити k3s

**Порядок:** спочатку agent, потім servers.

```bash
# work-node (10.0.10.20)
ssh malex@10.0.10.20
sudo systemctl stop k3s-agent
exit

# macmini7 (192.168.2.19)
ssh malex@192.168.2.19
sudo systemctl stop k3s
exit

# beelinkeqr5 (192.168.1.19)
ssh malex@192.168.1.19
sudo systemctl stop k3s
exit

# master-node (10.0.10.10)
ssh malex@10.0.10.10
sudo systemctl stop k3s
exit
```

---

## 3. Видалити flannel.1 (опційно, на кожній ноді)

```bash
sudo ip link delete flannel.1 2>/dev/null || true
```

---

## 4. Перевірка

```bash
# На кожній ноді — k3s має бути stopped
systemctl status k3s
# або
systemctl status k3s-agent
```

Після виконання — переходити до **Кроку 4** плану: запустити k3s на server-нодах.
