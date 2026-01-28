# Автоматичне перемикання portainer.lan на робочу ноду (failover)

**Ціль:** Щоб посилання **portainer.lan** (і monitoring.lan тощо) продовжувало працювати при аварії ноди **10.0.10.10** (master-node), потрібно автоматичне перенаправлення на іншу ноду (наприклад **10.0.10.20** — work-node).

## Поточний стан

- **portainer.lan** у hosts вказує на **10.0.10.10** (master-node).
- **Traefik** (Ingress) запущений лише на **master-node** (`nodeSelector: master-node`).
- При падінні master-node Ingress перестає працювати, portainer.lan стає недоступним.

## Що потрібно для failover

1. **Один вхідний адрес** для portainer.lan — або віртуальний IP (VIP), який переходить на робочу ноду, або балансувальник (HAProxy/nginx), який перемикає на живу ноду.
2. **Traefik на другій ноді** — щоб при падінні master-node Ingress працював на work-node (10.0.10.20). Зараз Traefik на work-node не запускали через проблеми pod-network; перед failover варто перевірити, чи Traefik там працює.

---

## Варіант 1: Keepalived — віртуальний IP (VIP)

Одна адреса (наприклад **10.0.10.100**) надається то master-node, то work-node. Коли master-node падає, VIP переходить на work-node; клієнти (portainer.lan → 10.0.10.100) автоматично йдуть на робочу ноду.

### Крок 1: Запуск Traefik на обох нодах

Щоб при переході VIP на work-node там був Ingress, Traefik має працювати на **обох** нодах (master-node і work-node). У `manifests/traefik/helmchartconfig.yaml` можна тимчасово змінити конфіг (окрема копія для failover):

- Збільшити **replicas** до **2**.
- Розширити **nodeSelector** або використати **nodeAffinity**, щоб поди потрапляли на master-node та work-node.

Приклад (перевірте, чи work-node має доступ до API та Service IP):

```yaml
# У valuesContent додати або змінити:
replicas: 2
nodeSelector: {}  # або вказати обидві ноди через nodeAffinity
# nodeAffinity приклад (замість nodeSelector):
# affinity:
#   nodeAffinity:
#     requiredDuringSchedulingIgnoredDuringExecution:
#       nodeSelectorTerms:
#       - matchExpressions:
#         - key: kubernetes.io/hostname
#           operator: In
#           values: [master-node, work-node]
```

Після apply і перезапуску Traefik перевірте, що обидва поди Running і що Ingress на work-node відповідає (наприклад `curl -H Host: portainer.lan http://10.0.10.20/`).

### Крок 2: Встановити keepalived на master-node та work-node

На **обох** нодах (Ubuntu/Debian):

```bash
sudo apt-get update && sudo apt-get install -y keepalived
```

### Крок 3: Конфіг keepalived на master-node (пріоритет вищий)

Файл `/etc/keepalived/keepalived.conf` на **master-node**:

```bash
vrrp_script chk_traefik {
  script "curl -s -o /dev/null -w %{http_code} http://127.0.0.1:80 -H Host:portainer.lan | grep -q 200"
  interval 2
  fall 2
  rise 1
}

vrrp_instance VI_LAN {
  state MASTER
  interface eth0
  virtual_router_id 51
  priority 101
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass your_secret_password
  }
  virtual_ipaddress {
    10.0.10.100/24
  }
  track_script {
    chk_traefik
  }
}
```

`interface` замініть на інтерфейс з мережею 10.0.10.0/24 (наприклад `eth0` або як у вас). Якщо перевірка через curl незручна, можна спростити `script` до перевірки порту: `script "nc -z 127.0.0.1 80"`.

### Крок 4: Конфіг keepalived на work-node (пріоритет нижчий)

Той самий файл на **work-node**, але `state BACKUP` і `priority 100`:

```bash
vrrp_script chk_traefik {
  script "curl -s -o /dev/null -w %{http_code} http://127.0.0.1:80 -H Host:portainer.lan | grep -q 200"
  interval 2
  fall 2
  rise 1
}

vrrp_instance VI_LAN {
  state BACKUP
  interface eth0
  virtual_router_id 51
  priority 100
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass your_secret_password
  }
  virtual_ipaddress {
    10.0.10.100/24
  }
  track_script {
    chk_traefik
  }
}
```

`auth_pass` має збігатися на обох нодах; `interface` — ваш інтерфейс.

### Крок 5: Запуск keepalived

На обох нодах:

```bash
sudo systemctl enable keepalived
sudo systemctl start keepalived
sudo systemctl status keepalived
```

### Крок 6: Вказати portainer.lan на VIP

У **hosts** на ПК (або в DNS) замість 10.0.10.10 вказати VIP:

```
10.0.10.100  portainer.lan
10.0.10.100  monitoring.lan
```

При роботі master-node VIP буде на ньому; при його падінні VIP перейде на work-node, і portainer.lan продовжить відкриватися через 10.0.10.100.

---

## Варіант 2: HAProxy на стабільному хості (наприклад macmini7)

Якщо є окрема машина, яка завжди доступна (наприклад **macmini7**, 192.168.2.19), на ній можна поставити HAProxy: він перевіряє доступність 10.0.10.10 та 10.0.10.20 і віддає трафік на ту ноду, що жива.

### Умови

- Traefik має працювати на work-node (як у варіанті 1), щоб при падінні master-node було куди перенаправляти.
- На macmini7 встановлено HAProxy (наприклад `apt install haproxy`).

### Приклад конфігу HAProxy

Файл `/etc/haproxy/haproxy.cfg` (фрагмент для HTTP/HTTPS до портів 80/443 на нодах):

```ini
frontend portainer_http
  bind *:80
  mode http
  default_backend traefik_http

frontend portainer_https
  bind *:443
  mode tcp
  default_backend traefik_https

backend traefik_http
  mode http
  balance roundrobin
  option httpchk GET / HTTP/1.0\r\nHost:\ portainer.lan
  server master 10.0.10.10:80 check inter 2s fall 2 rise 1
  server work   10.0.10.20:80 check inter 2s fall 2 rise 1 backup

backend traefik_https
  mode tcp
  balance roundrobin
  option tcp-check
  server master 10.0.10.10:443 check inter 2s fall 2 rise 1
  server work   10.0.10.20:443 check inter 2s fall 2 rise 1 backup
```

Тут при падінні master backup-сервер work стане активним. Для HTTPS можна використати SSL termination на HAProxy (тоді backend буде http до нод) — за потреби.

### Доступ

У hosts на ПК вказати IP macmini7 для portainer.lan і monitoring.lan:

```
192.168.2.19  portainer.lan
192.168.2.19  monitoring.lan
```

---

## Підсумок

| Варіант      | Вхідний адрес | Що потрібно |
|-------------|----------------|-------------|
| Keepalived  | 10.0.10.100 (VIP) | Traefik на обох нодах, keepalived на master-node та work-node, у hosts — 10.0.10.100 |
| HAProxy     | 192.168.2.19 (macmini7) | Traefik на обох нодах, HAProxy на macmini7, у hosts — 192.168.2.19 |

**Важливо:** На work-node раніше була проблема «no route to host» до API; через це Traefik там не запускали. Перед тим як покладатися на failover, варто перевірити, чи Traefik успішно працює на work-node (доступ до API та до Service IP). Якщо після виправлення мережі Traefik на work-node працює — можна впроваджувати варіант 1 або 2.
