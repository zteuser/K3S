# Ubiquiti UCG — документація FRR/BGP

Посилання та короткий підсумок офіційної та користувацької документації щодо налаштування FRR та BGP на UniFi Cloud Gateway (UCG).

---

## 1. Офіційна документація Ubiquiti

**UniFi — Border Gateway Protocol (BGP)**  
https://help.ui.com/hc/en-us/articles/16271338193559-UniFi-Border-Gateway-Protocol-BGP

- **Підтримувані пристрої (станом на публікацію):**
  - **UXG-Enterprise** — firmware 4.1.8 або новіший
  - **EFG, UDM-Pro-Max, UDM-SE, UDM-Pro, UDW** — UniFi OS 4.1.13 або новіший  
  Примітка: **Cloud Gateway Ultra (UCG Ultra)** у статті явно не перелічений, але на практиці BGP на UCG Ultra працює (Early Access / новіші версії UniFi OS); варто перевірити поточний список у статті та версію прошивки.

- **Спосіб налаштування:** завантаження **текстового конфігураційного файлу у форматі FRR BGP**. Файл створюється вручну; рядки конфігурації залежать від вашого сценарію.

- **Важливо:** додаткові рядки (Prefix Lists, Route Maps тощо) мають бути **після виходу з секції `router bgp`** (після `exit`), в кінці файлу.

- **Приклади з офіційної статті:**
  - BGP neighbor до ISP (multi-homing, реклама публічної мережі)
  - BGP neighbor до AWS через IPsec Site-to-Site VPN (динамічний обмін маршрутами)

- **Firewall:** для BGP до зовнішнього peer (наприклад ISP) потрібно дозволити **TCP 179** — правило типу External → Gateway (або аналог) для сервісу BGP.

- **Формат конфігу:** посилання на [FRR BGP documentation](https://docs.frrouting.org/en/latest/bgp.html).

---

## 2. Обмеження UI на UCG

- У веб-інтерфейсі UniFi **немає** повноцінного BGP-інтерфейсу: лише завантаження одного FRR-файлу та (залежно від версії) опція на кшталт «disable WAN monitoring».
- **Немає відображення:** вивчені BGP-маршрути, статус сесій, сусіди (neighbors), peer groups.
- Для перевірки та діагностики потрібен **SSH** на пристрій та:
  - **vtysh** — FRR Virtual Router Shell (Cisco-подібний синтаксис: `show ip route`, `show ip bgp`, `show run` тощо)
  - лог-файли, наприклад `/var/log/frr/bgpd.log`

---

## 3. Практичні гайди (BGP на UCG Ultra)

- **Migrating from USG to UCG Ultra (BGP, FRR)**  
  https://etse.me/tech/usg/ucg/unifi/bgp/2025/01/02/Migrating-from-USG-to-UCG-Ultra.html  

  - Розробка конфігу: краще спочатку зібрати та перевірити `frr.conf` на **окремій машині з FRR** (наприклад Debian: `apt install frr`, `vtysh`), потім перенести файл на UCG.
  - На UCG: Early Access канал оновлень (наприклад 4.1.13), увімкнути BGP у `/etc/frr/daemons` (`bgpd=yes`), скопіювати `frr.conf` в `/etc/frr/`, перезапустити FRR (`systemctl restart frr`, `systemctl enable frr`).
  - Приклади: router bgp, neighbor, address-family ipv4/ipv6, prefix-list, route-map (наприклад `set local-preference` для вибору кращого peer), `soft-reconfiguration inbound`, збереження конфігу через `wr me` у vtysh.

- **BGP with MetalLB and a Cloud Gateway Ultra**  
  https://dglloyd.net/2025/07/04/bgp-with-metallb-and-a-cloud-gateway-ultra/  

  - Реальний приклад FRR-конфігу для BGP peer з MetalLB (k8s): peer-group, `no bgp default ipv4-unicast`, `maximum-paths`, `bfd`, таймери, route-map in/out, prefix-list для фільтрації.
  - Підтвердження: в UI лише завантаження файлу, без відображення сесій/маршрутів; діагностика через SSH та `bgpd.log`.

---

## 4. Збереження конфігурації (persistence)

- Конфігурація FRR у **`/etc/frr/`** (зокрема `frr.conf`, `daemons`) за звітами користувачів **зберігається після перезавантаження**.
- Офіційно BGP налаштовується через **завантаження файлу в UniFi** — як саме UI зберігає його на пристрої (той самий `/etc/frr/` чи інший механізм), залежить від версії; при ручній зміні через SSH варто мати резервну копію та перевірити, чи оновлення UniFi OS не перезатирає зміни.

---

## 5. Корисні посилання

| Ресурс | URL |
|--------|-----|
| UniFi BGP (офіційно) | https://help.ui.com/hc/en-us/articles/16271338193559-UniFi-Border-Gateway-Protocol-BGP |
| FRR BGP (формат конфігу) | https://docs.frrouting.org/en/latest/bgp.html |
| FRR vtysh | https://docs.frrouting.org/en/latest/vtysh.html |
| Міграція USG → UCG Ultra (BGP/FRR) | https://etse.me/tech/usg/ucg/unifi/bgp/2025/01/02/Migrating-from-USG-to-UCG-Ultra.html |
| BGP + MetalLB на UCG Ultra | https://dglloyd.net/2025/07/04/bgp-with-metallb-and-a-cloud-gateway-ultra/ |

Для нашої схеми (4 роутери, full-mesh WG, перехід з OSPF на BGP) див. **OSPF_VS_BGP_FOUR_ROUTERS_MESH.md**.
