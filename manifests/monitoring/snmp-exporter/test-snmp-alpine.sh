#!/bin/sh
# Скрипт для тестування SNMP збірки (для Alpine-based образів)
# Використовуйте в консолі snmp-exporter pod

echo "=== Тест SNMP Exporter через wget ==="
echo ""

echo "1. Тест SNMP Exporter для vrn625 (192.168.2.1):"
wget -q -O- --timeout=60 "http://localhost:9116/snmp?target=192.168.2.1&module=unifi_ucg" | head -30
if [ $? -eq 0 ]; then
    echo "✅ vrn625: SNMP Exporter працює"
else
    echo "❌ vrn625: Помилка SNMP Exporter"
fi

echo ""
echo "2. Тест SNMP Exporter для syhiv17 (192.168.1.1):"
wget -q -O- --timeout=60 "http://localhost:9116/snmp?target=192.168.1.1&module=edgerouter_x" | head -30
if [ $? -eq 0 ]; then
    echo "✅ syhiv17: SNMP Exporter працює"
else
    echo "❌ syhiv17: Помилка SNMP Exporter"
fi

echo ""
echo "=== Альтернативний тест через netcat ==="
echo ""

echo "3. Тест HTTP запиту до SNMP Exporter:"
echo "GET /snmp?target=192.168.2.1&module=unifi_ucg HTTP/1.1
Host: localhost:9116
" | nc localhost 9116 | head -50

echo ""
echo "=== Перевірка завершена ==="
