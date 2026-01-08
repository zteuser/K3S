#!/bin/bash

# Скрипт для активації PVC через створення тестового Pod
# Використання: ./activate-pvc.sh

set -e

echo "=== Активація PVC через створення тестових Pods ==="
echo ""

# Перевірка поточного стану
echo "1. Поточний стан PVC:"
kubectl get pvc -n default | grep sharedata
echo ""

# Створення тестових Pods для активації PVC
echo "2. Створення тестових Pods для активації PVC..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pvc-sharedata1
  namespace: default
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/hostname
            operator: In
            values:
            - master-node
            - work-node
  containers:
  - name: test
    image: busybox
    command: ['sh', '-c', 'sleep 3600']
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: pvc-sharedata1
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pvc-sharedata2
  namespace: default
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/hostname
            operator: In
            values:
            - master-node
            - work-node
  containers:
  - name: test
    image: busybox
    command: ['sh', '-c', 'sleep 3600']
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: pvc-sharedata2
EOF

echo "✅ Тестові Pods створено"
echo ""

# Очікування зв'язування
echo "3. Очікування зв'язування PVC з PV..."
sleep 5

# Перевірка статусу
echo "4. Статус PVC після активації:"
kubectl get pvc -n default | grep sharedata
echo ""

echo "5. Статус PV:"
kubectl get pv | grep sharedata
echo ""

# Видалення тестових Pods
read -p "Видалити тестові Pods? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "6. Видалення тестових Pods..."
    kubectl delete pod test-pvc-sharedata1 test-pvc-sharedata2 -n default
    echo "✅ Тестові Pods видалено"
    echo ""
    echo "📝 PVC залишаються зв'язаними з PV навіть після видалення Pods"
else
    echo "6. Тестові Pods залишено запущеними"
fi

echo ""
echo "=== Готово ==="
