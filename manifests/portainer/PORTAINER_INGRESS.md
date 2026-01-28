# Доступ до Portainer через https://portainer.lan

Portainer можна відкривати за адресою **https://portainer.lan** замість **https://10.0.10.10:30943/** завдяки Ingress (Traefik) і TLS.

## Що зроблено в манифестах

- **ingress.yaml** — Ingress з хостом `portainer.lan`, backend Portainer Service порт 9000 (HTTP), TLS з secret `portainer-lan-tls`.
- Ingress додано в `kustomization.yaml`.

## Крок 1: Додати portainer.lan у hosts

На ПК, з якого заходите в браузер, додайте в `/etc/hosts` (Linux/macOS) або `C:\Windows\System32\drivers\etc\hosts` (Windows):

```
10.0.10.10  portainer.lan
```

(Якщо Traefik на іншій ноді — підставте її IP.)

## Крок 2: Створити TLS secret для portainer.lan

Ingress очікує secret **portainer-lan-tls** у namespace **portainer**. Без нього HTTPS не працюватиме.

### Варіант A: Self-signed сертифікат (швидко, буде попередження браузера)

```bash
# Згенерувати сертифікат для portainer.lan
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=portainer.lan" \
  -addext "subjectAltName=DNS:portainer.lan"

# Створити secret у кластері
kubectl create secret tls portainer-lan-tls --cert=tls.crt --key=tls.key -n portainer

# Видалити локальні файли
rm tls.crt tls.key
```

У браузері буде попередження про самопідписаний сертифікат — можна прийняти виняток і продовжити.

### Варіант B: Let's Encrypt (cert-manager)

Якщо в кластері встановлено cert-manager, можна створити Certificate для `portainer.lan` і вказати в Ingress secret, який cert-manager створить автоматично.

## Крок 3: Застосувати Ingress

Якщо Portainer уже розгорнуто через kustomize:

```bash
cd /path/to/k3s/manifests/portainer
kubectl apply -k .
```

Або тільки Ingress:

```bash
kubectl apply -f ingress.yaml
```

## Крок 4: Перевірити

1. Перевірити Ingress:
   ```bash
   kubectl get ingress -n portainer
   ```

2. Відкрити в браузері **https://portainer.lan** (після додавання hosts і створення TLS secret).

HTTP також працює: **http://portainer.lan** (порт 80).

## Якщо HTTPS не відкривається

- Переконайтеся, що secret `portainer-lan-tls` існує: `kubectl get secret portainer-lan-tls -n portainer`.
- Перевірте, що в hosts вказано правильний IP (нода, де працює Traefik, зазвичай 10.0.10.10).
- Перевірте логи Traefik: `kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=50`.
