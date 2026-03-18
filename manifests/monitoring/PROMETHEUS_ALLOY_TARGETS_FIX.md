# Prometheus — Alloy targets (по одному на ноду)

## Два різних речі

1. **Збір логів з усіх нод** — це робить **Alloy DaemonSet**: на кожній ноді крутиться один под Alloy, який збирає логи цієї ноди і відправляє їх у Loki (або інший backend). Це **не залежить** від Prometheus targets і працює на всіх нодах.
2. **Prometheus targets «alloy»** — це скрейп **метрик** (ендпоінт `/metrics`) кожного екземпляра Alloy. У конфігу один job з discovery за endpoints → виходить **по одному таргету на ноду** (master-node, work-node, macmini7, beelinkeqr5). Це потрібно для дашбордів у Grafana, де показуються метрики Alloy з кожної ноди.

Тобто логи з усіх нод Alloy вже збирає; у Prometheus ми лише налаштовуємо, що скрейпимо метрики з усіх цих екземплярів (4 таргети).

## Чому частина таргетів DOWN

Prometheus працює з **hostNetwork** на master-node. Він скрейпить за pod IP (10.244.x.x). До pod'ів на інших нодах (work-node, macmini7, beelinkeqr5) з master-node часто **немає маршруту** (OCI Security List не пропускає 10.244.0.0/16, або немає маршрутів до on-prem нод) → `no route to host` / `context deadline exceeded`, таргети цих нод у стані DOWN.

## Що зроблено в конфігу

- **Prometheus job `alloy`** — використовується **endpoints discovery** (namespace monitoring, service label app=alloy), щоб було **4 таргети** (по одному на ноду). Лейбл `instance` = ім’я ноди.
- Щоб **усі 4 таргети були UP**, потрібна cross-node доступність (див. нижче).

## Як зробити всі 4 таргети UP

- **OCI:** додати в Security List 10.244.0.0/16 (див. `manifests/POD_CONNECTIVITY_FIX_10_244.md`).
- **macmini7 / beelinkeqr5:** переконатися, що з master-node є маршрути до 10.244.2.0/24 та 10.244.4.0/24 (наприклад через WireGuard).

Файли: `manifests/monitoring/prometheus/configmap.yaml`, `manifests/cilium/networkpolicy-allow-dns-from-monitoring.yaml` (DNS для monitoring).
