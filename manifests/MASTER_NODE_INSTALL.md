# Встановлення k3s + Cilium на master-node (OCI)

Сценарій для **однієї ноди** master-node (10.0.10.10, enp0s6). Виконувати на самій ноді або через SSH.

---

## Передумови

- Ubuntu на OCI instance
- Інтерфейс: `enp0s6`, IP: `10.0.10.10`
- Доступ: SSH або OCI Console Connection

---

## 1. Видалення старого k3s (якщо є)

```bash
/usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s /var/lib/kubelet
sudo rm -f /etc/cni/net.d/*
```

Якщо мережа не відновлюється — `sudo reboot`.

---

## 2. Встановлення k3s

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --cluster-init --flannel-backend=none --disable-network-policy --disable-kube-proxy --node-ip 10.0.10.10" sh -
```

**Важливо:** `--disable-kube-proxy` обов'язковий при Cilium з `kubeProxyReplacement: true`. Без нього — конфлікт iptables і втрата мережі.

---

## 3. TLS SAN (для доступу з інших мереж)

```bash
# Відредагувати /etc/rancher/k3s/config.yaml, додати:
# tls-san: [192.168.100.5, 192.168.100.1, 192.168.100.6, 192.168.200.6]
sudo nano /etc/rancher/k3s/config.yaml
sudo systemctl restart k3s
```

---

## 4. Зберегти token

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

---

## 5. Встановлення Cilium

### Варіант A: з values-файлом (рекомендовано)

Скопіюйте `values-k3s.yaml` та `values-k3s-no-l7proxy.yaml` на master-node.

**Якщо раніше була втрата мережі** — додати override `l7Proxy: false` ([#25015](https://github.com/cilium/cilium/issues/25015)):

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm install cilium cilium/cilium \
  --version 1.19.0 --namespace kube-system \
  -f values-k3s.yaml -f values-k3s-no-l7proxy.yaml
```

**Стандартний варіант** (без override):

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm install cilium cilium/cilium \
  --version 1.19.0 --namespace kube-system -f values-k3s.yaml
```

### Варіант B: без values (мінімальний набір)

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium --version 1.19.0 -n kube-system \
  --set k8sServiceHost=10.0.10.10 \
  --set k8sServicePort=6443 \
  --set kubeProxyReplacement=true \
  --set ipv4.enabled=true \
  --set ipv6.enabled=false \
  --set tunnelProtocol="" \
  --set ipv4NativeRoutingCIDR=10.42.0.0/16 \
  --set devices=enp0s6 \
  --set directRoutingDevice=enp0s6
```

---

## 6. Перевірка

```bash
kubectl get nodes
kubectl get pods -n kube-system -l k8s-app=cilium
cilium status --wait
```

---

## 7. CiliumNodeConfig (опційно)

```bash
kubectl apply -f /path/to/cilium-node-configs.yaml
```

Для master-node в `cilium-node-configs.yaml` має бути `devices: "enp0s6"`.

