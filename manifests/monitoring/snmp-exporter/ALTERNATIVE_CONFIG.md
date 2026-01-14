# Альтернативна конфігурація SNMP Exporter

Якщо мінімальна конфігурація все ще не працює, можна використати готову конфігурацію з офіційного репозиторію.

## Варіант 1: Використати приклад з GitHub

1. Відкрийте: https://github.com/prometheus/snmp_exporter/tree/main
2. Знайдіть файл `snmp.yml` в корені репозиторію
3. Скопіюйте базову конфігурацію
4. Додайте ваш `router_auth` в секцію `auths`
5. Створіть простий модуль для роутерів

## Варіант 2: Використати генератор

Якщо потрібна повна конфігурація, використайте генератор:

```bash
# Завантажте генератор
git clone https://github.com/prometheus/snmp_exporter.git
cd snmp_exporter/generator

# Створіть generator.yml
cat > generator.yml <<EOF
modules:
  router:
    walk:
      - 1.3.6.1.2.1.1
      - 1.3.6.1.2.1.2
      - 1.3.6.1.2.1.4
      - 1.3.6.1.2.1.5
      - 1.3.6.1.2.1.6
      - 1.3.6.1.2.1.7
    auth:
      community: dfktyrb1
      version: 2
EOF

# Згенеруйте snmp.yml
./generator generate
```

## Варіант 3: Найпростіша конфігурація

Спробуйте цю мінімальну конфігурацію:

```yaml
auths:
  router_auth:
    version: 2
    community: dfktyrb1

modules:
  router:
    walk:
      - 1.3.6.1.2.1.1
      - 1.3.6.1.2.1.2
    auth: router_auth
```

Якщо це працює, поступово додавайте інші OID.
