#!/bin/bash
# Скрипт для тестування SNMP збірки з роутерів
# Використовуйте в консолі snmp-exporter pod

echo "=== Тест доступності роутерів ==="
echo ""

echo "1. Ping тест vrn625 (192.168.2.1):"
ping -c 3 192.168.2.1 || echo "❌ vrn625 недоступний"

echo ""
echo "2. Ping тест syhiv17 (192.168.1.1):"
ping -c 3 192.168.1.1 || echo "❌ syhiv17 недоступний"

echo ""
echo "=== Тест SNMP порту (161 UDP) ==="
echo ""

echo "3. Перевірка SNMP порту vrn625:"
nc -zv -u -w 5 192.168.2.1 161 2>&1 || echo "❌ Порт 161 недоступний на vrn625"

echo ""
echo "4. Перевірка SNMP порту syhiv17:"
nc -zv -u -w 5 192.168.1.1 161 2>&1 || echo "❌ Порт 161 недоступний на syhiv17"

echo ""
echo "=== Тест SNMP Exporter ==="
echo ""

echo "5. Тест SNMP Exporter для vrn625:"
curl -s -m 10 "http://localhost:9116/snmp?target=192.168.2.1&module=unifi_ucg" | head -20 || echo "❌ SNMP Exporter не може зібрати метрики з vrn625"

echo ""
echo "6. Тест SNMP Exporter для syhiv17:"
curl -s -m 10 "http://localhost:9116/snmp?target=192.168.1.1&module=edgerouter_x" | head -20 || echo "❌ SNMP Exporter не може зібрати метрики з syhiv17"

echo ""
echo "=== Перевірка завершена ==="
