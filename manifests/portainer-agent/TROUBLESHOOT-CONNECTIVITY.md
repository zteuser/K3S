# Portainer Agent — Connection Timeout / Connection Refused

Якщо `curl` з пода в namespace `portainer` до `portainer-agent.portainer-agent.svc.cluster.local:9001/ping` повертає **timeout (exit 28)** або **connection refused**, перевірте кроки нижче.

## 1. Agent pod і endpoints

```bash
kubectl get pods -n portainer-agent -l app=portainer-agent -o wide
kubectl get endpoints -n portainer-agent portainer-agent
```

- Под має бути `Running` і `Ready 1/1`.
- Endpoints мають містити адресу пода (наприклад `10.244.x.x:9001`). Якщо `ENDPOINTS` порожні — сервіс не знайде под, з’єднання не встановиться.

**Якщо под не Ready або endpoints порожні:** перезапустіть deployment і дочекайтесь готовності:

```bash
kubectl rollout restart deployment/portainer-agent -n portainer-agent
kubectl rollout status deployment/portainer-agent -n portainer-agent
```

---

## 2. Cilium network policies

Щоб трафік із Portainer Server (namespace `portainer`) доходив до Agent (namespace `portainer-agent`), мають бути застосовані обидва набори політик.

**Egress з namespace portainer (до agent):**

```bash
kubectl get ciliumnetworkpolicies -n portainer
# Мають бути: allow-portainer-server-egress-to-agent, allow-portainer-server-egress-dns
```

Якщо політик немає (наприклад, застосовували лише окремі файли без kustomize):

```bash
kubectl apply -k manifests/portainer/
# або окремо:
kubectl apply -f manifests/portainer/networkpolicy-portainer-to-agent.yaml
```

**Ingress до namespace portainer-agent (від portainer):**

```bash
kubectl get ciliumnetworkpolicies -n portainer-agent
# Мають бути: allow-portainer-server-to-agent, allow-portainer-agent-egress-dns
```

Якщо політик немає:

```bash
kubectl apply -f manifests/portainer-agent/networkpolicy-allow-from-portainer.yaml
```

---

## 3. Cross-node pod connectivity (10.244.x.x)

Якщо под Portainer і под Agent на **різних нодах**, а між нодами трафік з pod CIDR (10.244.0.0/16) блокується (наприклад, OCI Security List), з’єднання буде таймаутити.

Перевірка:

```bash
# На яких нодах сидять поди
kubectl get pods -n portainer -l app=portainer -o wide
kubectl get pods -n portainer-agent -l app=portainer-agent -o wide
```

Якщо ноди різні — виконайте кроки з документу **POD_CONNECTIVITY_FIX_10_244.md** (додати правило в OCI Security List для 10.244.0.0/16 або перейти на VXLAN).

---

## 4. Тест з пода з правильними лейблами

Політики дозволяють трафік лише від подів із **namespace: portainer** та **label: app=portainer**. Debug-под має мати цей лейбл:

**Agent очікує HTTPS на порту 9001.** Якщо в поді з образом `curlimages/curl` не резолвиться DNS — використовуйте ClusterIP (варіант A).

**Варіант A (по ClusterIP):**
```bash
AGENT_IP=$(kubectl get svc -n portainer-agent portainer-agent -o jsonpath='{.spec.clusterIP}')
kubectl run -n portainer debug-curl --restart=Never --image=curlimages/curl --labels="app=portainer" \
  -- curl -sk -m 10 https://${AGENT_IP}:9001/ping
kubectl logs -n portainer debug-curl
kubectl delete pod -n portainer debug-curl --ignore-not-found
```

**Варіант B (по DNS):**
```bash
kubectl run -n portainer debug-curl --restart=Never --image=curlimages/curl --labels="app=portainer" \
  -- curl -sk -m 10 https://portainer-agent.portainer-agent.svc.cluster.local:9001/ping
kubectl logs -n portainer debug-curl
kubectl delete pod -n portainer debug-curl --ignore-not-found
```
- Якщо з’єднання встановлюється, але відповідь не очікувана — перевірте логи агента:  
  `kubectl logs -n portainer-agent -l app=portainer-agent --tail=50`

---

## 5. Швидкий чеклист

| Крок | Команда / дія |
|------|----------------|
| Agent Running | `kubectl get pods -n portainer-agent -l app=portainer-agent` |
| Endpoints є | `kubectl get ep -n portainer-agent portainer-agent` |
| Egress policy (portainer) | `kubectl get cnp -n portainer` |
| Ingress policy (portainer-agent) | `kubectl get cnp -n portainer-agent` |
| Cross-node (якщо OCI) | Додати 10.244.0.0/16 у Security List або VXLAN |
| Тест з пода | `curl` з `--labels="app=portainer"` у namespace `portainer` |

Після виправлення в Portainer UI використовуйте адресу:

- **Кластер (agent в ns portainer-agent):** `portainer-agent.portainer-agent.svc.cluster.local:9001`
