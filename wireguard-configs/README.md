# Зібрані конфігурації WireGuard для аналізу тунелів

Інструкції збору — у [manifests/WIREGUARD_TUNNEL_CONFIG_COLLECTION.md](../manifests/WIREGUARD_TUNNEL_CONFIG_COLLECTION.md).

## Файли (після збору)

| Файл | Пристрій |
|------|----------|
| `amper-master-wg-YYYYMMDD.txt` | Amper master (10.0.10.10) |
| `amper-worker-wg-YYYYMMDD.txt` | Amper worker (10.0.10.20) |
| `vrn625-wg-YYYYMMDD.txt` (або скріншоти) | VRN625 (192.168.2.1) |
| `syhiv17-wg-YYYYMMDD.txt` (або скріншоти) | Syhiv17 (192.168.1.1) |

Або вставте вивід у відповідні секції файлу **COLLECTED_OUTPUTS.md**.

**Приватні ключі:** не вставляйте повні приватні ключі; можна замаскувати (наприклад `***REDACTED***`).

Після збору — можна проаналізувати allowed-ips, маршрути та NAT і порівняти з діаграмою Syhiv VPN-2.pdf.
