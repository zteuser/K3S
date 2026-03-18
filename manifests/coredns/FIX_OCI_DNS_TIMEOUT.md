# Виправлення DNS i/o timeout на OCI (169.254.169.254)

## Проблема

У логах CoreDNS та інших подів з’являються помилки:

```
[ERROR] plugin/errors: 2 ... read udp ... i/o timeout
```

Запити йдуть до `169.254.169.254:53` — це OCI VCN resolver / metadata. Поди отримують search domain `vcn09070439.oraclevcn.com` з ноди, і при резолві імен (наприклад `snmp-exporter.monitoring.svc.cluster.local` або `secure.gravatar.com`) додається суфікс `.vcn09070439.oraclevcn.com`. CoreDNS пересилає такі запити на upstream з `/etc/resolv.conf` (169.254.169.254), який не відповідає або недоступний з pod network → timeout.

## Рішення

Замінити upstream DNS у CoreDNS на публічні резолвери (8.8.8.8, 1.1.1.1), щоб зовнішні запити не йшли на 169.254.169.254.

### Варіант 1: Патч ConfigMap (рекомендовано)

```bash
kubectl get configmap coredns -n kube-system -o yaml | \
  sed 's|forward \. /etc/resolv.conf|forward . 8.8.8.8 1.1.1.1|' | \
  kubectl apply -f -
```

Потім перезапустіть CoreDNS:

```bash
kubectl rollout restart deployment coredns -n kube-system
```

### Варіант 2: k3s --resolv-conf (при установці)

Якщо встановлюєте k3s з нуля на OCI, створіть файл `/etc/rancher/k3s/resolv.conf`:

```
nameserver 8.8.8.8
nameserver 1.1.1.1
```

І запустіть k3s з `--resolv-conf=/etc/rancher/k3s/resolv.conf`. Це вплине на resolv.conf у подах і на те, що використовує CoreDNS (якщо k3s передає цей шлях).

### Варіант 3: Скрипт apply

```bash
./manifests/coredns/apply-coredns-oci-dns-fix.sh
```

## Перевірка

Після застосування:

```bash
kubectl get configmap coredns -n kube-system -o yaml | grep forward
# Має бути: forward . 8.8.8.8 1.1.1.1

kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
# Помилки i/o timeout на 169.254.169.254 мають зникнути
```

## Примітка

- Після оновлення k3s вбудований манифест CoreDNS може перезаписати ConfigMap — патч зникне. Застосуйте його знову.
- Якщо подам потрібно резолвити внутрішні OCI hostnames в зоні `oraclevcn.com`, 8.8.8.8 їх не знайде (NXDOMAIN). Для типового Kubernetes workload це прийнятно.
