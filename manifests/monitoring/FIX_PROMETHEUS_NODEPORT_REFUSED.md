# ERR_CONNECTION_REFUSED на http://10.0.10.10:30001 (Prometheus UI)

**Симптоми:** у браузері відкриваєте **http://10.0.10.10:30001** (NodePort Prometheus) і бачите **«This site can't be reached»** / **ERR_CONNECTION_REFUSED**.

**Причини:** з вашого ПК адреса **10.0.10.10** недоступна, або на ноді з IP 10.0.10.10 фаєрвол блокує вхід на порт 30001.

---

## Варіант 1: Використати IP ноди з вашої мережі (швидко)

NodePort **30001** слухається на **кожній** ноді кластера. Відкрийте Prometheus по IP тієї ноди, до якої у вас є доступ з браузера:

- Якщо ви в мережі **192.168.2.x** (наприклад LAN Syhiv):
  - **http://192.168.2.19:30001** (macmini7)
  - **http://192.168.2.95:30001** (beelinkeqr5)
- Якщо є доступ до **work-node** (10.0.10.20): **http://10.0.10.20:30001**
- Якщо є доступ до **master-node** по WireGuard (192.168.100.5): **http://192.168.100.5:30001**

Перевірка з терміналу (з машини, де є доступ до кластера):

```bash
curl -s -o /dev/null -w "%{http_code}" http://192.168.2.19:30001/-/healthy
# Очікується 200
```

**Якщо і 192.168.2.19:30001, і 192.168.1.19:30001 дають «Connection refused»** (наприклад `nc -zv 192.168.2.19 30001` падає з refused) — на цих нодах **фаєрвол блокує вхід на порт 30001** з вашого ПК. Потрібно на **кожній ноді**, з якої хочете відкривати Prometheus (macmini7, beelinkeqr5), дозволити вхід на 30001 з вашої мережі — див. **Варіант 3** нижче (те саме, але для 192.168.2.19/192.168.1.19), або перейти на **Варіант 2** (Ingress).

---

## Варіант 2: Доступ через Ingress (без NodePort)

Якщо застосовано Ingress для Prometheus, можна відкривати UI по домену:

1. Застосувати Ingress:
   ```bash
   kubectl apply -f manifests/monitoring/prometheus/ingress.yaml
   ```
2. Додати в DNS або **/etc/hosts** (на ПК, з якого заходите в браузері) запис:
   ```
   <IP Traefik / того ж хоста, що monitoring.lan>  prometheus.monitoring.lan
   ```
   Якщо **monitoring.lan** вже вказує на ноду з Traefik, використовуйте той самий IP для **prometheus.monitoring.lan**.
3. Відкрити в браузері: **http://prometheus.monitoring.lan**

Targets: **http://prometheus.monitoring.lan/targets**

---

## Варіант 3: Відкрити порт 30001 на нодах (фаєрвол)

Якщо **будь-яка** нода (10.0.10.10, 192.168.2.19, 192.168.1.19) повертає **Connection refused** на порт 30001 з вашого ПК — на цій ноді фаєрвол блокує вхід. Потрібно дозволити вхід на TCP 30001.

На **кожній ноді**, до якої підключаєтесь (наприклад macmini7 — 192.168.2.19, beelinkeqr5 — 192.168.1.19):

```bash
# iptables — дозволити вхід на NodePort Prometheus з локальних мереж
sudo iptables -I INPUT 1 -p tcp --dport 30001 -s 192.168.0.0/16 -j ACCEPT
# опційно з 10.x (якщо підключаєтесь з VPN)
sudo iptables -I INPUT 1 -p tcp --dport 30001 -s 10.0.0.0/8 -j ACCEPT

# зберегти правила
sudo netfilter-persistent save
# або: sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

Якщо використовується **ufw**:

```bash
sudo ufw allow 30001/tcp
sudo ufw status
```

Після цього з вашого ПК мають відкриватися **http://192.168.2.19:30001** та **http://192.168.1.19:30001**.

---

## Підсумок

| Спосіб | URL |
|--------|-----|
| NodePort на ноді з вашої мережі | http://192.168.2.19:30001 або http://192.168.2.95:30001 |
| Ingress (після apply + hosts) | http://prometheus.monitoring.lan |
| NodePort на 10.0.10.10 | http://10.0.10.10:30001 (після відкриття порта на ноді) |
