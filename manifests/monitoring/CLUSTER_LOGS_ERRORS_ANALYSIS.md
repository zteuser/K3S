# Аналіз помилок у Cluster pod logs

## 1. etcd: required revision has been compacted

**Повідомлення:** `watch chan error: etcdserver: mvcc: required revision has been compacted`

**Джерело:** kube-apiserver на master-node

**Причина:** etcd видалив старі ревізії (compaction), а клієнт (API server) ще намагається читати вже видалену ревізію. Часто тимчасова помилка — клієнт перепідключається.

**Дія:**
- Якщо помилка **рідкісна** (1–2 рази на день) — можна ігнорувати.
- Якщо **часта** — перезапустити kube-apiserver:
  ```bash
  kubectl delete pod -n kube-system -l component=kube-apiserver
  ```
- Або на master-node: `sudo systemctl restart k3s` (перезапуск всього k3s).

---

## 2. garbage-collector: unable to get REST mapping for helm.cattle.io/v1/HelmChart

**Повідомлення:** `"error syncing item" err="unable to get REST mapping for helm.cattle.io/v1/HelmChart"` для `traefik-crd` та `traefik`

**Джерело:** kube-controller-manager (garbage-collector-controller)

**Причина:** Залишки від **старого k3s** — у etcd залишились об'єкти `HelmChart` (traefik-crd, traefik) після міграції на k8s з Cilium. Поточний кластер не має CRD `helm.cattle.io` (це було в k3s), тому garbage collector не може обробити ці orphaned об'єкти.

**Дії (по черзі):**

### Крок 1: Перевірити наявність CRD та об'єктів
```bash
kubectl get crd | grep helm
kubectl get helmcharts.helm.cattle.io -n kube-system 2>/dev/null || echo "CRD не знайдено"
```

### Крок 2a: Якщо CRD є і об'єкти відображаються — видалити orphaned HelmCharts
```bash
kubectl delete helmchart traefik-crd -n kube-system --ignore-not-found
kubectl delete helmchart traefik -n kube-system --ignore-not-found
```

### Крок 2b: Якщо CRD відсутній — перезапустити k3s на master-node
Іноді API mappings підвантажуються пізно. Після перезапуску CRD може з'явитись:
```bash
# На master-node
sudo systemctl restart k3s
```

### Крок 2c: Якщо CRD відсутній — встановити CRD і видалити об'єкти
Типово для **k8s (kubeadm)** — helm-controller і CRD `helm.cattle.io` тут не використовуються (це було в k3s). Об'єкти traefik-crd/traefik — залишки в etcd після міграції з k3s.

**Рішення:** Встановити CRD `helmcharts.helm.cattle.io`, потім видалити orphaned HelmCharts:
```bash
./manifests/FIX_HELMCHART_GARBAGE_COLLECTOR/fix-helmchart-garbage-collector.sh
```
Детальніше: `manifests/FIX_HELMCHART_GARBAGE_COLLECTOR/README.md`

---

## 3. Ingress HTTP server: Failed to parse user ID

**Повідомлення:** `"Failed to parse user ID" error="identifier is not initialized"`

**Джерело:** ймовірно Traefik або інший Ingress/HTTP gateway

**Причина:** Запит прийшов без коректного user/identity (наприклад, auth header або client cert). Часто це запити без аутентифікації (health checks, metrics, звичайний браузер).

**Дія:** Якщо Ingress і сервіси відповідають коректно — можна ігнорувати. Якщо є проблеми з доступом — перевірити конфіг Ingress (auth, middleware).

---

## Підсумок

| Помилка | Критичність | Рекомендація |
|--------|-------------|--------------|
| etcd compacted | Низька (якщо рідко) | Ігнорувати або перезапустити API server |
| HelmChart REST mapping | Середня | Видалити orphaned HelmCharts або перезапустити k3s |
| Failed to parse user ID | Низька | Ігнорувати, якщо доступ працює |
