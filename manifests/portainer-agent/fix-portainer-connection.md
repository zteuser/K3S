# Виправлення підключення Portainer UI до Agent

## Проблема

Portainer UI показує environment як "Down" і "Disconnected", хоча Agent працює і відповідає на HTTPS запити.

## Важлива інформація

**Portainer UI працює на `master-node` або `work-node`** (через nodeAffinity), а не на `macmini7`.

Це означає, що коли Portainer UI намагається підключитися до Agent, він робить це з `master-node` або `work-node`, а не з `macmini7`.

## Рішення

### Варіант 1: Використати IP ноди, де працює Portainer UI

1. **Визначте, на якій ноді працює Portainer UI:**
   ```bash
   kubectl get pods -n portainer -l app=portainer -o wide
   ```

2. **Якщо Portainer працює на `master-node` (10.0.10.10):**
   - Використайте адресу: `10.0.10.10:30778`
   - Або перевірте, чи `master-node` може досягти `192.168.2.19:30778`

3. **Якщо Portainer працює на `work-node` (10.0.10.20):**
   - Використайте адресу: `10.0.10.20:30778`
   - Або перевірте, чи `work-node` може досягти `192.168.2.19:30778`

### Варіант 2: Використати Service DNS (рекомендовано)

Замість IP адреси, використайте Service DNS ім'я:

```
portainer-agent.portainer.svc.cluster.local:9001
```

**Переваги:**
- Працює незалежно від ноди
- Не залежить від IP адрес
- Використовує внутрішній Kubernetes DNS

### Варіант 3: Перевірка маршрутизації

Якщо Portainer UI працює на `master-node` або `work-node`, перевірте, чи ці ноди можуть досягти `192.168.2.19`:

```bash
# З master-node або work-node
ping 192.168.2.19
curl -k -v https://192.168.2.19:30778/ping
```

Якщо `ping` або `curl` не працюють, можливо:
- Немає маршруту до `192.168.2.19`
- Firewall блокує з'єднання
- `192.168.2.19` доступний тільки з локальної мережі macmini7

## Рекомендоване рішення

**Використайте Service DNS** замість IP адреси:

1. Відкрийте Portainer UI
2. Перейдіть до "Environment details" для "k3s-cluster-vrn625"
3. Оновіть **Environment address** на:
   ```
   portainer-agent.portainer.svc.cluster.local:9001
   ```
4. Натисніть "Update environment"

**Альтернатива:** Якщо Service DNS не працює, використайте IP ноди, де працює Portainer UI:
- Якщо Portainer на `master-node`: `10.0.10.10:30778`
- Якщо Portainer на `work-node`: `10.0.10.20:30778`

## Перевірка

Після оновлення адреси:

1. Перевірте статус environment в Portainer UI
2. Перевірте логи Agent:
   ```bash
   kubectl logs -n portainer -l app=portainer-agent --tail=50
   ```
3. Шукайте спроби підключення від Portainer UI
