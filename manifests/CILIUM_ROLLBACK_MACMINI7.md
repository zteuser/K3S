# Відкат macmini7 з Cilium на Flannel

**Причина:** Втрачена мережева зв'язність на macmini7 після міграції на Cilium.

> **Реальний результат:** відкат (iptables, CNI, config, reboot) **не відновив мережу**. Допомогла лише **повна переінсталяція Ubuntu** на ноді.

**Передумова:** Потрібен **фізичний або консольний доступ** до macmini7 (монітор + клавіатура, VNC, Serial console), оскільки SSH недоступний.

**Обмеження:** З інших нод немає доступу (kubectl не працює, helm відсутній). Усі дії — тільки локально на macmini7.

---

## Дії на macmini7 (локально, через консоль)

### Крок 1.1. Зупинити k3s

```bash
sudo systemctl stop k3s
```

### Крок 1.2. Видалити CNI-конфіг Cilium (щоб Flannel міг працювати)

```bash
# Cilium залишає конфіг у /etc/cni/net.d/ — його треба прибрати
sudo rm -f /etc/cni/net.d/*cilium* 2>/dev/null || true
```

### Крок 1.2a. Очистити правила iptables (якщо мережа не відновлюється)

Cilium додає ланцюжки `CILIUM_INPUT`, `CILIUM_FORWARD`, `CILIUM_OUTPUT` тощо. Їх треба видалити:

```bash
# Спробувати iptables (залежить від системи: legacy або nft)
for table in filter nat mangle raw; do
  sudo iptables -t $table -F 2>/dev/null || true
  sudo iptables -t $table -X 2>/dev/null || true
done

# Якщо є iptables-legacy (часто на Debian/Ubuntu)
for table in filter nat mangle raw; do
  sudo iptables-legacy -t $table -F 2>/dev/null || true
  sudo iptables-legacy -t $table -X 2>/dev/null || true
done

# Якщо система використовує nftables (Ubuntu 22.04+, Fedora)
sudo nft flush ruleset 2>/dev/null || true
```

**Важливо:** виконувати після `systemctl stop k3s`, перед `systemctl start k3s`.

### Крок 1.3. Повернути Flannel у конфігурації k3s

Відредагувати `/etc/rancher/k3s/config.yaml`:

**Видалити:**

```yaml
flannel-backend: none
disable-network-policy: true
```

**Оригінальний config (з бекапу backup-pre-cilium/node-macmini7.txt):**

```yaml
tls-san: 
  - 192.168.100.6
  - 192.168.200.6
```

Тобто config має містити лише `tls-san`, без `flannel-backend: none`, без `disable-network-policy: true`. Flannel за замовчуванням k3s буде активний.

### Крок 1.4. Запустити k3s

```bash
sudo systemctl start k3s
```

### Крок 1.5. Перевірити мережу

```bash
ip addr
ping -c 2 192.168.2.1
ping -c 2 8.8.8.8
```

Якщо ping працює — мережа відновлена.

---

## Після відновлення мережі: видалити Cilium через kubectl (на macmini7)

Після того як macmini7 знову в мережі, виконати **локально на macmini7** (kubectl входить у k3s):

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Видалити DaemonSet Cilium (зупинить поді Cilium)
kubectl delete daemonset cilium -n kube-system --ignore-not-found

# Видалити CiliumNodeConfig (якщо застосовували)
kubectl delete ciliumnodeconfig -n kube-system --all --ignore-not-found 2>/dev/null || true

# Інші ресурси Cilium (опційно, для повного очищення)
kubectl delete deployment -n kube-system -l k8s-app=cilium --ignore-not-found
kubectl delete configmap cilium-config -n kube-system --ignore-not-found
```

---

## Відкат інших нод (коли зʼявиться доступ)

На **beelinkeqr5**, **master-node**, **work-node** потрібно буде:

1. Зупинити k3s / k3s-agent
2. Видалити з `/etc/rancher/k3s/config.yaml`: `flannel-backend: none`, `disable-network-policy: true`
3. Видалити CNI Cilium: `sudo rm -f /etc/cni/net.d/*cilium* 2>/dev/null`
4. Запустити k3s / k3s-agent

---

## Якщо мережа не відновлюється після перезапуску k3s

eBPF зникає після reboot, але **iptables-правила Cilium можуть залишатись**. На практиці (master-node в OCI) мережа відновилась **лише після reboot** — очищення iptables без reboot не допомогло.

```bash
sudo systemctl stop k3s

# 1. Відредагувати config.yaml (прибрати flannel-backend: none)
# 2. Видалити CNI Cilium
sudo rm -f /etc/cni/net.d/*cilium* 2>/dev/null || true

# 3. Очистити iptables (критично, якщо зв'язок не відновлюється)
for table in filter nat mangle raw; do
  sudo iptables -t $table -F 2>/dev/null || true
  sudo iptables -t $table -X 2>/dev/null || true
  sudo iptables-legacy -t $table -F 2>/dev/null || true
  sudo iptables-legacy -t $table -X 2>/dev/null || true
done
sudo nft flush ruleset 2>/dev/null || true

# 4. Запустити k3s (без reboot)
sudo systemctl start k3s
```

Якщо після цього мережа все ще не працює — перезавантажити:

```bash
sudo reboot
```

Після reboot k3s запуститься з Flannel.

---

## Якщо нічого не допомагає: повна переінсталяція Ubuntu

На практиці відкат (config, CNI, iptables, reboot) **не відновив мережу**. Єдиний робочий варіант — **повна переінсталяція Ubuntu** на ноді.

Після переінсталяції:
1. Встановити k3s з нуля (з Flannel або з Cilium — див. `K3S_FRESH_INSTALL_CILIUM_RESTORE.md`)
2. Приєднати ноду до кластера
3. Відновити workload з бекапу

---

## Перевірка після відкату

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
# Має бути coredns, traefik, flannel (flannel pods)
```
