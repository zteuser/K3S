# iptables на VRN625 та Syhiv17 — підсумок (2026-02-01)

## NAT (таблиця nat) — підтверджено

На обох роутерах у **POSTROUTING** (UBIOS_POSTROUTING_USER_HOOK) є правило:

| Пристрій | Правило | Ефект |
|----------|---------|--------|
| **Syhiv17** | `MASQUERADE  all  --  *  wgclt+  0.0.0.0/0  0.0.0.0/0` | Усі пакети в wgclt1/wgclt2 маскуються адресою тунелю (192.168.100.2, 192.168.200.2). |
| **VRN625** | `MASQUERADE  all  --  *  wgclt+  0.0.0.0/0  0.0.0.0/0` | Усі пакети в wgclt1/wgclt2 маскуються адресою тунелю (192.168.100.6, 192.168.200.6). |

Це **підтверджує**, чому в трафіку кластера (зокрема etcd) з’являються тунельні source IP замість LAN-адрес macmini7 (192.168.2.19) та beelinkeqr5 (192.168.1.19). Рішення — мати ці тунельні IP в **tls-san** на control-plane нодах (див. PLAN_NETWORK_AND_REBUILD_CONTROL_PLANE.md).

## Filter

Зони firewall (WAN, LAN, VPN, DMZ, GUEST). На Syhiv17 мережі 192.168.100.0/30 та 192.168.200.0/30 виключені з geoip (RETURN у UBIOS_IN_GEOIP / UBIOS_OUT_GEOIP).

Детальний аналіз — у [manifests/WIREGUARD_ANALYSIS.md](../manifests/WIREGUARD_ANALYSIS.md), розділ 6.
