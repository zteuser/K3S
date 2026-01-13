# Виправлення збору метрик з Traefik

## Проблема

Prometheus намагається збирати метрики з Traefik pod на порту 9100, але отримує помилку:
```
Get "http://10.42.0.146:9100/metrics": context deadline exceeded
```

**Причина:** Traefik має анотації для збору метрик, але вказує неправильний порт.

## Рішення

### Варіант 1: Ігнорувати помилку (рекомендовано)

Це не критична помилка. Prometheus продовжить збирати метрики з інших компонентів. Можна просто ігнорувати цей target.

**Переваги:**
- Не потрібно нічого змінювати
- Не впливає на інші метрики

### Варіант 2: Виправити анотації Traefik

Якщо потрібно збирати метрики з Traefik, потрібно виправити анотації.

#### Крок 1: Перевірка поточних анотацій

```bash
kubectl get deployment traefik -n kube-system -o yaml | grep -A 5 annotations
```

#### Крок 2: Перевірка порту метрик Traefik

Traefik зазвичай експортує метрики на:
- Порт `8080` (внутрішній metrics endpoint)
- Або через спеціальний `/metrics` endpoint

Перевірте:
```bash
# Перевірка сервісу Traefik
kubectl get svc -n kube-system traefik -o yaml

# Перевірка endpoints
kubectl get endpoints -n kube-system traefik
```

#### Крок 3: Оновлення анотацій Traefik

Через Portainer:
1. Kubernetes → Applications → kube-system
2. Знайдіть deployment **traefik**
3. Натисніть **Editor**
4. Знайдіть секцію `annotations` в `template.metadata`
5. Змініть:
   ```yaml
   annotations:
     prometheus.io/scrape: "true"
     prometheus.io/port: "8080"  # Або правильний порт для метрик
     prometheus.io/path: "/metrics"
   ```
6. Натисніть **Update**

Або через kubectl:
```bash
kubectl patch deployment traefik -n kube-system -p '{"spec":{"template":{"metadata":{"annotations":{"prometheus.io/port":"8080"}}}}}'
```

### Варіант 3: Виключити Traefik зі збору метрик

Якщо не потрібні метрики Traefik, видаліть анотації:

Через Portainer:
1. Kubernetes → Applications → kube-system
2. Знайдіть deployment **traefik**
3. Натисніть **Editor**
4. Видаліть анотації:
   - `prometheus.io/scrape`
   - `prometheus.io/port`
   - `prometheus.io/path`
5. Натисніть **Update**

Або через kubectl:
```bash
kubectl patch deployment traefik -n kube-system --type=json -p='[{"op": "remove", "path": "/spec/template/metadata/annotations/prometheus.io~1scrape"}, {"op": "remove", "path": "/spec/template/metadata/annotations/prometheus.io~1port"}, {"op": "remove", "path": "/spec/template/metadata/annotations/prometheus.io~1path"}]'
```

### Варіант 4: Оновити конфігурацію Prometheus для кращої обробки помилок

Можна додати `scrape_timeout` та `scrape_interval` для job `kubernetes-pods`, щоб він не чекав так довго на недоступні targets.

Оновіть `prometheus/configmap.yaml`:

```yaml
- job_name: 'kubernetes-pods'
  scrape_interval: 30s
  scrape_timeout: 10s  # Зменшити timeout
  kubernetes_sd_configs:
    - role: pod
  relabel_configs:
    # ... існуючі relabel_configs ...
```

Потім оновіть ConfigMap через Portainer або:
```bash
kubectl apply -f prometheus/configmap.yaml
kubectl delete pods -n monitoring -l app=prometheus  # Перезапуск для застосування конфігурації
```

## Перевірка

Після виправлення:

1. Перевірте targets в Prometheus: `http://<node-ip>:30001/targets`
2. Target `kubernetes-pods` має показувати менше помилок або взагалі не показувати Traefik

## Рекомендація

**Найпростіше рішення:** Варіант 1 (ігнорувати помилку) або Варіант 3 (видалити анотації з Traefik), якщо метрики Traefik не потрібні.

Якщо потрібні метрики Traefik, використайте Варіант 2 (виправити анотації).
