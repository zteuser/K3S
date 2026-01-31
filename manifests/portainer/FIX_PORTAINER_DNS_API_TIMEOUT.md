# Виправлення помилок DNS/API у Portainer

**Симптоми в логах Portainer:**
- `lookup kubernetes.default.svc on 10.43.0.10:53: read udp ... i/o timeout`
- `Get "https://10.43.0.1:443/version": dial tcp 10.43.0.1:443: i/o timeout`

**Причина:** под Portainer не може досягти CoreDNS (10.43.0.10) і Kubernetes API (10.43.0.1). Зазвичай це firewall (iptables) на нодах: трафік под↔ClusterIP блокується правилами INPUT/FORWARD (REJECT або KUBE-ROUTER перед ACCEPT для 10.42/10.43).

Повна документація: `manifests/FIX_CLUSTERIP_ACCESS_FROM_ALL_NODES.md`. Нижче — мінімальні кроки.

**Швидке застосування:** скопіюйте `apply-fix-dns-api.sh` на кожну ноду і виконайте `sudo ./apply-fix-dns-api.sh`, потім збережіть правила (п. 1.4) і перезапустіть под Portainer (розділ 4).

---

## 1. На **кожній** ноді кластера (master-node, macmini7, beelinkeqr5, work-node)

Виконати по SSH на відповідній ноді.

### 1.1 INPUT — дозволити трафік з/до pod і service мереж

```bash
sudo iptables -I INPUT 1 -s 10.43.0.0/16 -j ACCEPT
sudo iptables -I INPUT 1 -d 10.43.0.0/16 -j ACCEPT
sudo iptables -I INPUT 1 -s 10.42.0.0/16 -j ACCEPT
sudo iptables -I INPUT 1 -d 10.42.0.0/16 -j ACCEPT
```

### 1.2 FORWARD — дозволити forwarded трафік подів

```bash
sudo iptables -I FORWARD 1 -s 10.42.0.0/16 -j ACCEPT
sudo iptables -I FORWARD 1 -d 10.42.0.0/16 -j ACCEPT
sudo iptables -I FORWARD 1 -s 10.43.0.0/16 -j ACCEPT
sudo iptables -I FORWARD 1 -d 10.43.0.0/16 -j ACCEPT
```

### 1.3 Перевірка порядку

```bash
sudo iptables -L FORWARD -n -v --line-numbers | head -15
```

На початку FORWARD мають бути 4 правила ACCEPT для 10.42/10.43. Якщо першим стоїть `KUBE-ROUTER-FORWARD` — виконати ще раз тільки 4 команди з п. 1.2 (вони вставляють правила в позицію 1).

### 1.4 Зберегти правила (щоб пережили перезавантаження)

```bash
# Debian/Ubuntu з iptables-persistent
sudo netfilter-persistent save
# або
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

---

## 2. Тільки на **work-node** (якщо Portainer або інші поди на work-node)

Дозволити зворотний OTV/overlay-трафік з control-plane (macmini7 — 192.168.200.6) на work-node (10.0.10.20). Інакше відповіді DNS/API не повертаються до подів на work-node.

```bash
sudo iptables -I INPUT 1 -s 192.168.200.0/30 -j ACCEPT
```

Потім зберегти правила (п. 1.4).

---

## 3. На **control-plane** нодах: вхід на API (6443)

Якщо є політика DROP/REJECT за замовчуванням у INPUT:

```bash
sudo iptables -I INPUT 1 -p tcp --dport 6443 -j ACCEPT
```

Зберегти правила.

---

## 4. Перезапустити под Portainer

Після застосування правил на всіх нодах:

```bash
kubectl delete pod -n portainer -l app=portainer
```

Перевірити логи (таймаутів бути не повинно):

```bash
kubectl logs -n portainer -l app=portainer -f --tail=20
```

Перевірка з поду (на будь-якій ноді):

```bash
kubectl run dns-test --rm -it --restart=Never --image=busybox:1.36 -- nslookup kubernetes.default.svc.cluster.local 10.43.0.10
```

---

## 5. Якщо під Portainer на work-node і таймаут лишається

1. **Переконайтеся, що скрипт виконано на всіх нодах:** work-node, master-node, macmini7, beelinkeqr5.
2. **На work-node і на ноді, де крутиться API (macmini7/beelinkeqr5):**
   ```bash
   sudo iptables -L FORWARD -n -v --line-numbers | head -15
   ```
   На початку мають бути 4× ACCEPT для 10.42/10.43. Якщо першим стоїть `KUBE-ROUTER-FORWARD` — ще раз виконати на цій ноді `sudo ./apply-fix-dns-api.sh` (або команди з п. 1.2).
3. **На work-node** має бути правило INPUT для 192.168.200.0/30 (п. 2).
4. **Тимчасово:** щоб Portainer UI працював (без Bad Gateway), зафіксуйте под на master-node: у `deployment.yaml` має бути `nodeSelector: kubernetes.io/hostname: master-node`. Потім:
   ```bash
   kubectl apply -f manifests/portainer/deployment.yaml
   kubectl delete pod -n portainer -l app=portainer
   ```
   Після цього под має заплануватися на master-node; Traefik і Portainer будуть на одній ноді, API-доступ має працювати.

## 6. Якщо kube-router знову витісняє правила (FORWARD)

kube-router періодично вставляє `KUBE-ROUTER-FORWARD` на початок FORWARD, тоді ручні ACCEPT зсуваються вниз і перестають спрацьовувати. Рішення — cron-скрипт на **кожній** ноді, див. `manifests/FIX_CLUSTERIP_ACCESS_FROM_ALL_NODES.md`, розділ «Якщо kube-router знову ставить своє правило першим». Поки це не налаштовано, після перезапуску k3s або кількох хвилин правила можуть знову зміститися — тоді або повторно запускати скрипт, або тримати Portainer на master-node (nodeSelector).
