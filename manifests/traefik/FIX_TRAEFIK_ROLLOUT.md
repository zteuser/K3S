# Traefik: под не планується після rollout restart (hostNetwork)

## Симптоми

Після `kubectl rollout restart deployment traefik -n kube-system` новий под Traefik у статусі **Pending**, Events:

```
0/3 nodes are available: 1 node(s) didn't have free ports for the requested pod ports,
2 node(s) didn't match Pod's node affinity/selector.
```

**Причина:** У Traefik увімкнено **hostNetwork** і **nodeSelector: master-node**. Новий под має заплануватися на master-node, але порти **80, 443, 8080** (і при потребі 9102) на цій ноді ще зайняті **старим** подом Traefik. Під час rolling update старий под не завершують, поки новий не стане Ready, тому виникає блокування.

## Що зробити

1. Подивитися поди Traefik:
   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o wide
   ```
   Буде один под у **Running** (на master-node) і один у **Pending**.

2. **Видалити старий (Running) под**, щоб звільнити порти на master-node:
   ```bash
   kubectl delete pod -n kube-system -l app.kubernetes.io/name=traefik --field-selector=status.phase=Running
   ```
   Або вказати ім’я Running-пода вручну:
   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
   kubectl delete pod <ім'я-running-пода> -n kube-system
   ```

3. Після видалення старого пода Pending-под має заплануватися на master-node і перейти у Running. Перевірити:
   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o wide
   ```

4. На master-node переконатися, що метрики слухають на **9102** (а 9100 вільний для node-exporter):
   ```bash
   ss -tlnp | grep -E '9100|9102'
   ```

Після цього можна перевірити, що node-exporter також запланувався на master-node:
`kubectl get pods -n monitoring -l app=node-exporter -o wide`.
