# Помилка «Datasource … was not found» у Grafana

## Симптоми

- Дашборди (наприклад **kube-state-metrics-v2**) показують **No data** і червону іконку попередження.
- У панелі видно повідомлення: **«Datasource PBFA97CFB59082093 was not found»** або **«Datasource PBFA97CFB590B2093 was not found»** (цифри 82 чи літера B — залежить від версії дашборду).
- У **Connections → Data sources** є Prometheus з URL `http://prometheus:9090`, але дашборд на нього не посилається.

## Причина

Дашборд було імпортовано з Grafana.com (або збережено з іншої інстанції). У JSON дашборду зашитий **UID датасорсу** автора шаблону (наприклад `PBFA97CFB59082093`). У вашій Grafana датасорс Prometheus створений з іншим UID — у нашому provisioning це **`prometheus`** — тому Grafana не знаходить датасорс за цим ідентифікатором.

---

## Рішення 1: Вибрати правильний датасорс у UI (найпростіше)

1. Відкрийте дашборд **kube-state-metrics-v2** (або той, де є помилка).
2. Натисніть **Dashboard settings** (іконка шестерні) → **Variables**.
3. Якщо є змінна типу **Datasource** (наприклад **DS_PROMETHEUS** або подібна):
   - У полі **Current** виберіть **Prometheus** (ваш датасорс).
   - Натисніть **Update** (або **Apply**), потім **Save dashboard**.
4. Якщо змінної датасорсу немає або панелі все одно показують помилку:
   - Відкрийте **Edit** кожної панелі з помилкою.
   - У верхній частині панелі в полі **Data source** виберіть **Prometheus** замість поточного (missing).
   - Збережіть панель і дашборд.

Після збереження дашборд буде використовувати ваш Prometheus (uid `prometheus`), і «Datasource was not found» зникне.

---

## Рішення 2: Додати датасорс з «legacy» UID (для імпортованих дашбордів)

Якщо не хочете змінювати дашборд вручну і маєте багато панелей з цим UID, можна додати **другий** датасорс Prometheus з UID, який очікує дашборд (наприклад `PBFA97CFB59082093`), що вказує на той самий URL.

1. Відкрийте `manifests/monitoring/grafana/configmap-datasources.yaml`.
2. У секції `datasources:` додайте ще один запис (скопіюйте блок Prometheus і змініть `name` та `uid`):

```yaml
  # Legacy UID для імпортованих дашбордів (наприклад kube-state-metrics-v2 з grafana.com)
  prometheus-legacy.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus (legacy)
      uid: PBFA97CFB59082093
      type: prometheus
      access: proxy
      url: http://prometheus:9090
      isDefault: false
      editable: false
      jsonData:
        timeInterval: "15s"
```

3. Застосуйте ConfigMap і перезапустіть Grafana:

```bash
kubectl apply -f manifests/monitoring/grafana/configmap-datasources.yaml -n monitoring
kubectl -n monitoring rollout restart deployment/grafana
kubectl -n monitoring rollout status deployment/grafana
```

4. У **Connections → Data sources** з’явиться другий Prometheus з UID `PBFA97CFB59082093`. Дашборд **kube-state-metrics-v2** почне знаходити датасорс, і «No data» зникне (за умови що метрики в Prometheus є; якщо ні — див. **FIX_PODS_SECTION_NO_DATA.md**).

У репозиторії вже provisioned два legacy-датасорси: **PBFA97CFB59082093** і **PBFA97CFB590B2093** (обидва вказують на `http://prometheus:9090`). Після `kubectl apply` і перезапуску Grafana обидва UID працюють. Якщо в помилці з’явиться інший UID — додайте його аналогічно в `configmap-datasources.yaml`.

---

## Перевірка UID поточного датасорсу

Щоб дізнатися UID вашого Prometheus (або іншого датасорсу):

- У браузері: **Connections → Data sources** → клік по **Prometheus** → у рядку URL буде щось на кшталт `/datasources/edit/1` або внизу сторінки може бути вказано UID.
- Через API (замініть URL і пароль на свої):

```bash
curl -s -u admin:YOUR_PASSWORD "http://<grafana-url>/api/datasources" | jq '.[] | {name, uid, type}'
```

Очікується запис з **uid: "prometheus"** для основного Prometheus з нашого provisioning.

---

## Підсумок

| Ситуація | Дія |
|----------|-----|
| Один дашборд з помилкою | **Рішення 1:** у налаштуваннях дашборду або панелі вибрати Data source = **Prometheus** і зберегти. |
| Багато дашбордів / не хочете правити вручну | **Рішення 2:** додати в provisioning датасорс з uid, який показується в помилці (наприклад `PBFA97CFB59082093`), і перезапустити Grafana. |
| Після виправлення датасорсу все ще «No data» | Перевірити метрики в Prometheus і змінні/час дашборду — див. **../FIX_PODS_SECTION_NO_DATA.md**. |

Після виправлення посилання на датасорс панелі мають показувати дані, якщо Prometheus відповідає і метрики (cAdvisor, kube-state-metrics) є.
