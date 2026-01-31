# Виправлення помилок DNS/API у Portainer

**Симптоми в логах Portainer:**
- `lookup kubernetes.default.svc on 10.43.0.10:53: read udp ... i/o timeout`
- `Get "https://10.43.0.1:443/version": dial tcp 10.43.0.1:443: i/o timeout`

**Причина:** под Portainer не може досягти CoreDNS (10.43.0.10) і Kubernetes API (10.43.0.1). Зазвичай це firewall (iptables) на нодах: трафік под↔ClusterIP блокується правилами INPUT/FORWARD (REJECT або KUBE-ROUTER перед ACCEPT для 10.42/10.43).

Повна документація: `manifests/FIX_CLUSTERIP_ACCESS_FROM_ALL_NODES.md`. Нижче — мінімальні кроки.

**Швидке застосування:** скопіюйте `apply-fix-dns-api.sh` на кожну ноду і виконайте `sudo ./apply-fix-dns-api.sh`, потім збережіть правила (п. 1.4) і перезапустіть под Portainer (розділ 4).

---

## 0. Перевірка конективності безпосередньо з контейнера Portainer

Виконувати з хоста (macmini7 або master-node), де є `kubectl`. Це допомагає зрозуміти, чи под Portainer досягає API, DNS і kubelet на work-node.

### Варіант A: з пода Portainer (якщо в образі є curl/wget)

```bash
# Ім'я пода (один з)
PORTAINER_POD=$(kubectl get pods -n portainer -l app=portainer -o jsonpath='{.items[0].metadata.name}')

# API (10.43.0.1:443) — має повернути JSON або "ok"
kubectl exec -n portainer "$PORTAINER_POD" -- wget -qO- --no-check-certificate --timeout=5 https://10.43.0.1:443/version 2>&1 | head -5
# або якщо є curl:
# kubectl exec -n portainer "$PORTAINER_POD" -- curl -ks -m 5 https://10.43.0.1:443/version

# DNS (10.43.0.10:53)
kubectl exec -n portainer "$PORTAINER_POD" -- nslookup kubernetes.default.svc.cluster.local 10.43.0.10 2>&1

# Kubelet на work-node (10.0.10.20:10250) — прямий доступ з пода (для порівняння з proxy через API)
kubectl exec -n portainer "$PORTAINER_POD" -- wget -qO- --no-check-certificate --timeout=5 https://10.0.10.20:10250/metrics 2>&1 | head -3
```

Якщо в образі Portainer немає `wget`/`curl`/`nslookup`, використовуйте варіант B.

### Варіант B: debug-под на тій самій ноді, що й Portainer

Под запускається на **master-node** (як і Portainer), тому мережева поведінка буде така сама:

```bash
# Запустити под на тій самій ноді, що й Portainer (master-node)
kubectl run conn-test --rm -it --restart=Never \
  --image=curlimages/curl \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"master-node"}}}' \
  -- sh -c '
    echo "=== API 10.43.0.1:443 ==="
    curl -ks -m 5 https://10.43.0.1:443/version | head -3
    echo ""
    echo "=== DNS 10.43.0.10 ==="
    nslookup kubernetes.default.svc.cluster.local 10.43.0.10
    echo ""
    echo "=== Kubelet 10.0.10.20:10250 ==="
    curl -ks -m 5 https://10.0.10.20:10250/metrics 2>&1 | head -3
  '
```

**Інтерпретація:**
- **API таймаут** — под не досягає 10.43.0.1 (firewall/FORWARD на нодах).
- **DNS таймаут** — под не досягає CoreDNS або відповідь не повертається (INPUT/FORWARD, зокрема на work-node — 192.168.200.0/30).
- **10.0.10.20:10250** — якщо з пода працює, а в логах Portainer все одно 502 при proxy через API, то 502 йде від **хоста** control-plane (API server підключається до 10.0.10.20:10250 з ноди, а не з пода); перевіряйте доступ з хоста: `nc -zv 10.0.10.20 10250` на macmini7/master-node і firewall на work-node для порту 10250.

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

## 5. Portainer: «failed to snapshot performance metrics for node work-node» (502 Bad Gateway на 10.0.10.20:10250)

**Симптом у логах:**  
`failed to snapshot performance metrics for node work-node | error="... proxy error from 127.0.0.1:6443 while dialing 10.0.10.20:10250, code 502: 502 Bad Gateway"`

**Причина:** Kubernetes API server (на control-plane) проксує запити Portainer до kubelet на work-node за адресою **10.0.10.20:10250**. Якщо на **work-node** firewall блокує вхід на порт **10250** з control-plane, з’єднання не встановлюється і API повертає 502.

**Виправлення на work-node:** дозволити вхід на порт kubelet (10250) з IP control-plane (або з усіх внутрішніх мереж):

```bash
# Дозволити вхід на kubelet (10250) з control-plane / внутрішніх мереж
sudo iptables -I INPUT 1 -p tcp --dport 10250 -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 10250 -s 192.168.0.0/16 -j ACCEPT
```

Після перевірки — зберегти правила (п. 1.4).

**Важливо:** запит на метрики ноди проксує **API server** — він крутиться на одній із control-plane нод (master-node, macmini7, beelinkeqr5). З’єднання до 10.0.10.20:10250 відкриває саме **хост** цієї ноди, а не под. Тому перевірку потрібно робити з **кожної** control-plane ноди:

```bash
# На кожному control-plane (master-node, macmini7, beelinkeqr5) виконати:
nc -zv 10.0.10.20 10250
```

Якщо з пода на master-node `curl https://10.0.10.20:10250/metrics` дає "Unauthorized" (з’єднання є), а з хоста beelinkeqr5 `nc -zv 10.0.10.20 10250` — таймаут, то 502 у Portainer саме через те, що запит обробив API server на beelinkeqr5 і з beelinkeqr5 до work-node:10250 немає доступу. Тоді: маршрут з beelinkeqr5 до 10.0.10.20 і firewall на work-node для порту 10250 з IP beelinkeqr5.

---

## 5.1 Prometheus: targets beelinkeqr5 (192.168.2.95) DOWN — context deadline exceeded

**Симптоми:** у Prometheus → **Targets** для **kubernetes-nodes** і **node-exporter** target `192.168.2.95` (beelinkeqr5) у стані **DOWN**, помилка: `Get "https://192.168.2.95:10250/metrics": context deadline exceeded` та `Get "http://192.168.2.95:9100/metrics": context deadline exceeded`.

**Причина:** Prometheus (под на master-node) скрейпить kubelet (10250) і node-exporter (9100) на beelinkeqr5. Якщо на **beelinkeqr5** firewall блокує вхід на порти **10250** і **9100** з мережі кластера (pod CIDR, інші ноди), з’єднання таймаутять.

**Виправлення на beelinkeqr5:** дозволити вхід на порти kubelet (10250) і node-exporter (9100) з мереж кластера:

```bash
# На ноді beelinkeqr5 (SSH або консоль):
sudo iptables -I INPUT 1 -p tcp --dport 10250 -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 10250 -s 192.168.0.0/16 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 9100 -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 9100 -s 192.168.0.0/16 -j ACCEPT
```

Після перевірки — зберегти правила (п. 1.4). Альтернатива: виконати на beelinkeqr5 скрипт `apply-fix-dns-api.sh` (п. 1.2); у нього додано блок для beelinkeqr5, який вставляє ці ж правила.

Перевірка з ноди, де крутиться Prometheus (master-node):

```bash
# З master-node (або з пода prometheus):
curl -ks -m 5 https://192.168.2.95:10250/metrics 2>&1 | head -3
curl -s -m 5 http://192.168.2.95:9100/metrics 2>&1 | head -3
```

Через 1–2 хвилини targets **192.168.2.95** у Prometheus мають стати **UP**.

---

## 6. Якщо під Portainer на work-node і таймаут лишається

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

## 7. Якщо kube-router знову витісняє правила (FORWARD)

kube-router періодично вставляє `KUBE-ROUTER-FORWARD` на початок FORWARD, тоді ручні ACCEPT зсуваються вниз і перестають спрацьовувати. Рішення — cron-скрипт на **кожній** ноді, див. `manifests/FIX_CLUSTERIP_ACCESS_FROM_ALL_NODES.md`, розділ «Якщо kube-router знову ставить своє правило першим». Поки це не налаштовано, після перезапуску k3s або кількох хвилин правила можуть знову зміститися — тоді або повторно запускати скрипт, або тримати Portainer на master-node (nodeSelector). Див. також розділ 5 вище для помилки «failed to snapshot performance metrics for node work-node».
