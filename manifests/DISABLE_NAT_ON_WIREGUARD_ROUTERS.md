# Як вимкнути NAT на тунелях WireGuard (VRN625, Syhiv17)

На обох роутерах Ubiquiti UCG Ultra трафік у інтерфейси **wgclt+** проходить через **MASQUERADE** у POSTROUTING, тому приймач бачить source IP тунелю (192.168.100.6, 192.168.100.2 тощо), а не LAN-адреси хостів (192.168.2.19, 192.168.1.19). Якщо вимкнути NAT саме для трафіку до мереж кластера, etcd буде бачити справжні LAN IP — тоді в **tls-san** можна обмежитися лише цими адресами (і не додавати тунельні).

---

## 1. Чи є опція в Unifi UI

У стандартному інтерфейсі Unifi Network **немає** опції вимкнення NAT (masquerade) для WireGuard-клієнта на UCG Ultra. Правила NAT керуються системою автоматично. На форумі Ubiquiti є обговорення з запитом такої можливості: [Disable NAT on Wireguard Client](https://community.ui.com/questions/Disable-NAT-on-Wireguard-Client/22c2f704-a0f1-4965-b5e9-b56d200d1acc) — поки що офіційної опції немає. Тому варіанти: або залишити NAT і використовувати **tls-san** з тунельними IP (як у PLAN), або обійти MASQUERADE правилами iptables вручну (див. нижче).

---

## 2. Обхід MASQUERADE через iptables (вставка RETURN)

Ідея: вставити в ланцюг **UBIOS_POSTROUTING_USER_HOOK** правило **перед** MASQUERADE, яке відповідає трафіку «LAN → wgclt+ → мережі кластера» і робить **RETURN**. Тоді цей трафік не потрапляє на MASQUERADE, source IP зберігається.

**Мережі кластера:** 10.0.10.0/24 (Amper), 192.168.1.0/24 (Syhiv17/LAN), 192.168.2.0/24 (VRN625/LAN).

---

### 2.0 Як реалізувати (покроково)

1. **Доступ:** SSH на роутер (`ssh ubnt@192.168.2.1` для VRN625 або `ssh ubnt@192.168.1.1` для Syhiv17). Потрібні права root (на Unifi OS зазвичай вже root або `sudo`).
2. **Таблиця:** правила NAT — у таблиці **nat**, ланцюг **POSTROUTING** → підланцюг **UBIOS_POSTROUTING_USER_HOOK**. Команди з `-t nat`.
3. **Вставка:** `-I UBIOS_POSTROUTING_USER_HOOK 1` — вставити правило на **позицію 1** (на початок). Кожна нова вставка зміщує попередні правила вниз, тому другу команду виконуємо **після** першої — тоді в ланцюгу буде: спочатку перевірка на 10.0.10.0/24, потім на 192.168.1.0/24 (або 192.168.2.0/24), далі решта правил (в т.ч. MASQUERADE).
4. **Умови:** `-s` — джерело (ваш LAN), `-o wgclt+` — вихідний інтерфейс (будь-який WireGuard-клієнт), `-d` — призначення (мережі кластера). При збігу — **RETURN** (вихід з ланцюга без MASQUERADE).

---

### 2.1 На VRN625 (Vernadskogo25)

LAN — 192.168.2.0/24. Трафік з цієї мережі в wgclt+ до 10.0.10.0/24 та 192.168.1.0/24 не маскувати.

Виконати по черзі (друга команда вставляє правило перед першим):

```bash
iptables -t nat -I UBIOS_POSTROUTING_USER_HOOK 1 -s 192.168.2.0/24 -o wgclt+ -d 192.168.1.0/24 -j RETURN
iptables -t nat -I UBIOS_POSTROUTING_USER_HOOK 1 -s 192.168.2.0/24 -o wgclt+ -d 10.0.10.0/24 -j RETURN
```

### 2.2 На Syhiv17 (Syhiv17-25)

LAN — 192.168.1.0/24. Трафік з цієї мережі в wgclt+ до 10.0.10.0/24 та 192.168.2.0/24 не маскувати.

Виконати по черзі:

```bash
iptables -t nat -I UBIOS_POSTROUTING_USER_HOOK 1 -s 192.168.1.0/24 -o wgclt+ -d 192.168.2.0/24 -j RETURN
iptables -t nat -I UBIOS_POSTROUTING_USER_HOOK 1 -s 192.168.1.0/24 -o wgclt+ -d 10.0.10.0/24 -j RETURN
```

### 2.3 Перевірка

Після вставки правил:

```bash
iptables -t nat -L UBIOS_POSTROUTING_USER_HOOK -n -v --line-numbers
```

На початку ланцюга мають з’явитися два нові правила (RETURN для -o wgclt+). Далі — як раніше MASQUERADE для wgclt+.

Перевірка з хоста: з macmini7 (192.168.2.19) зробити з’єднання до etcd на beelinkeqr5 (192.168.1.19) або master (10.0.10.10) і на приймачі переконатися, що source IP — 192.168.2.19, а не 192.168.100.6.

---

## 3. Збереження правил після перезавантаження

На Unifi OS правила iptables часто **перегенеруються** при перезавантаженні мережі або пристрою, тому вставлені вручну правила можуть зникати. Варіанти:

1. **Скрипт при старті** — якщо є можливість виконати скрипт після підняття інтерфейсів (наприклад, через Task Scheduler у Controller або власний init), додати туди команди з п. 2.1 / 2.2.
2. **Cron** — періодично (наприклад, щохвилини) перевіряти наявність правил і вставляти їх при відсутності (складніше, потрібен доступ до cron).
3. **Не зберігати** — використовувати **tls-san** з тунельними IP (як у PLAN_NETWORK_AND_REBUILD_CONTROL_PLANE.md); тоді NAT на роутерах можна не чіпати.

### 3.1 Опційний скрипт для повторного застосування (VRN625)

Зберегти на роутері (наприклад `/tmp/no-nat-wg-vrn625.sh`) і викликати вручну або з cron/Task Scheduler після завантаження:

```bash
#!/bin/sh
# Повторно вставити RETURN перед MASQUERADE для трафіку кластера (VRN625)
iptables -t nat -C UBIOS_POSTROUTING_USER_HOOK -s 192.168.2.0/24 -o wgclt+ -d 10.0.10.0/24 -j RETURN 2>/dev/null || \
  iptables -t nat -I UBIOS_POSTROUTING_USER_HOOK 1 -s 192.168.2.0/24 -o wgclt+ -d 10.0.10.0/24 -j RETURN
iptables -t nat -C UBIOS_POSTROUTING_USER_HOOK -s 192.168.2.0/24 -o wgclt+ -d 192.168.1.0/24 -j RETURN 2>/dev/null || \
  iptables -t nat -I UBIOS_POSTROUTING_USER_HOOK 1 -s 192.168.2.0/24 -o wgclt+ -d 192.168.1.0/24 -j RETURN
```

`-C` перевіряє, чи правило вже є; якщо ні (`||`) — вставляємо. Для Syhiv17 аналогічно, з `-s 192.168.1.0/24` та `-d 192.168.2.0/24` і `-d 10.0.10.0/24`.

---

## 4. Відкат (прибрати обхід NAT)

Видалити вставлені правила за номером (номери видно в `--line-numbers`):

```bash
# Приклад на VRN625: якщо RETURN-правила стали 1 і 2
iptables -t nat -D UBIOS_POSTROUTING_USER_HOOK 1
iptables -t nat -D UBIOS_POSTROUTING_USER_HOOK 1
```

Другий раз видаляється правило на позиції 1 (після першого видалення індекси зміщуються).

---

## 5. Підсумок

| Мета | Рекомендація |
|------|----------------|
| Не чіпати роутери, все працює | Залишити NAT, використовувати **tls-san** з тунельними IP (PLAN). |
| Etcd бачить справжні LAN IP без NAT на роутерах | **Обхід RETURN (п. 2) на практиці призводить до втрати зв’язності** — не використовувати. Замість цього: підняти **прямі WG-тунелі між нодами** (macmini7, beelinkeqr5 ↔ Amper master/worker), див. [PLAN_DIRECT_TUNNELS_NODES_TO_AMPER.md](PLAN_DIRECT_TUNNELS_NODES_TO_AMPER.md). |

Посилання: [UniFi WireGuard Client](https://help.ui.com/hc/en-us/articles/16357883221015), [Community: Disable NAT on Wireguard Client](https://community.ui.com/questions/Disable-NAT-on-Wireguard-Client/22c2f704-a0f1-4965-b5e9-b56d200d1acc).
