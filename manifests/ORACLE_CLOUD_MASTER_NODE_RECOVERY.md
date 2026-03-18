# Відновлення доступу до master-node в Oracle Cloud

**master-node:** 141.144.254.42 (публічний), 10.0.10.10 (внутрішній)  
**Причина втрати доступу:** ймовірно Cilium/iptables (як на macmini7).

---

## Варіант 1: Instance Console Connection (Serial Console)

Доступ через OCI Console без SSH до інстансу.

### Передумови

- IAM політики (адмін повинен додати):
  ```
  Allow group <group_name> to manage instance-console-connection in tenancy
  Allow group <group_name> to read instance in tenancy
  ```

### Кроки

1. **OCI Console** → Compute → Instances → обрати **master-node**
2. **Resources** → **Console connection** (або **OS Management** → **Console connection**)
3. **Create local connection** → вставити публічний SSH-ключ (RSA) → **Create console connection**
4. Скопіювати згенеровану SSH-команду (виглядає приблизно так):

   ```bash
   ssh -i ~/.ssh/your_key -o ProxyCommand='ssh -i ~/.ssh/your_key -W %h:%p -p 443 ocid1.instanceconsoleconnection.oc1.eu-xxx-1.XXX@instance-console.eu-xxx-1.oci.oraclecloud.com' ocid1.instance.oc1.eu-xxx-1.YYY
   ```

5. Запустити команду — з’явиться login prompt.
6. Якщо є пароль root/ubuntu — увійти і виправити мережу/iptables.
7. Якщо пароля немає — переходити до **Варіанту 2**.

**Обмеження:** на Ubuntu GRUB може бути недоступний через serial console. Якщо login prompt не з’являється — використовувати Варіант 2.

---

## Варіант 2: Boot Volume + Rescue Instance (основний варіант)

Підключити boot volume master-node до іншого інстансу, змонтувати диск, виправити конфіг, повернути диск назад.

### Крок 1. Зупинити master-node

OCI Console → Compute → Instances → master-node → **Stop**  
Зачекати до повної зупинки (до ~15 хв).

### Крок 2. Від’єднати Boot Volume

1. Master-node → **Boot volume** (ліворуч)
2. Скопіювати **OCID** boot volume (на кшталт `ocid1.bootvolume.oc1.eu-xxx-1.xxx`)
3. **Detach boot volume**

### Крок 3. Створити Rescue Instance

1. Compute → Instances → **Create instance**
2. Той самий образ (Ubuntu), той самий compartment
3. Мінімальний shape (наприклад VM.Standard.E2.1.Micro)
4. Підключити свій SSH-ключ
5. Створити інстанс, дочекатися готовності, перевірити SSH

### Крок 4. Підключити Boot Volume до Rescue Instance

1. Rescue instance → **Attached block volumes** → **Attach block volume**
2. Вставити OCID boot volume з master-node
3. **Attachment type:** Paravirtualized
4. **Access:** Read/write
5. **Attach**

### Крок 5. Змонтувати диск на Rescue Instance

```bash
ssh ubuntu@<rescue-instance-public-ip>

sudo su -
lsblk
# Знайти новий диск (наприклад sdb або sdc, не sda з /)
# Приклад: sdb1 — partition з root master-node

mkdir /mnt/master-root
mount /dev/sdb1 /mnt/master-root   # або sdc1 — залежить від lsblk
```

### Крок 6. Виправити iptables / мережу

**Важливо:** на практиці мережа часто відновлюється лише після **reboot**. Якщо після правок iptables/config мережа не працює — перезавантажити rescue instance перед від’єднанням volume.

**Якщо причина — Cilium/iptables** (як на macmini7):

```bash
# Переглянути поточні правила
cat /mnt/master-root/etc/iptables/rules.v4

# Варіант A: змінити default policy на ACCEPT (тимчасово)
sed -i 's/:INPUT DROP/:INPUT ACCEPT/' /mnt/master-root/etc/iptables/rules.v4
sed -i 's/:FORWARD DROP/:FORWARD ACCEPT/' /mnt/master-root/etc/iptables/rules.v4

# Варіант B: додати правило для SSH (якщо є DROP)
# Відредагувати вручну, додати перед COMMIT:
# -A INPUT -p tcp --dport 22 -j ACCEPT
```

**Якщо є nftables:**

```bash
# Видалити/перейменувати конфіг nftables
mv /mnt/master-root/etc/nftables.conf /mnt/master-root/etc/nftables.conf.bak 2>/dev/null || true
```

**Відновити k3s config (Flannel замість Cilium):**

```bash
# Видалити flannel-backend: none з k3s config
sed -i '/flannel-backend: none/d' /mnt/master-root/etc/rancher/k3s/config.yaml
sed -i '/disable-network-policy: true/d' /mnt/master-root/etc/rancher/k3s/config.yaml

# Видалити CNI Cilium
rm -f /mnt/master-root/etc/cni/net.d/*cilium* 2>/dev/null || true
```

### Крок 7. Відмонтувати і від’єднати

```bash
umount /mnt/master-root
rmdir /mnt/master-root
```

OCI Console → Rescue instance → **Attached block volumes** → **Detach** boot volume.

### Крок 8. Повернути Boot Volume на master-node

1. Master-node → **Boot volume** → **Attach boot volume**
2. Після приєднання — **Start** master-node
3. Перевірити SSH: `ssh ubuntu@141.144.254.42`

### Крок 9. Видалити Rescue Instance

Після успішного відновлення доступу — Terminate rescue instance, щоб не платити за неї.

---

## Варіант 3: OCI Run Command

Якщо на інстансі працює **Oracle Cloud Agent** і Run Command увімкнено:

1. OCI Console → Compute → Instances → master-node
2. **Resources** → **Run command** (або **Cloud Agent**)
3. **Run command** → обрати скрипт або ввести команду
4. Приклад: `iptables -F && iptables -t nat -F && systemctl restart sshd`

**Обмеження:** Run Command підтримує Oracle Linux, CentOS, Windows. Для Ubuntu потрібен Oracle Cloud Agent — перевірити наявність на інстансі.

---

## Після відновлення доступу

1. Відкотити k3s на Flannel (якщо ще не зроблено):
   - Видалити `flannel-backend: none` з `/etc/rancher/k3s/config.yaml`
   - `sudo systemctl restart k3s`

2. Або перевстановити кластер з нуля (див. `K3S_FRESH_INSTALL_CILIUM_RESTORE.md`).

---

## Посилання

- [OCI Serial Console](https://docs.oracle.com/en-us/iaas/Content/Compute/References/serialconsole.htm)
- [OCI Run Command](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/runningcommands.htm)
- [dbi-services: Recover lost SSH (boot volume)](https://www.dbi-services.com/blog/oci-recover-lost-ssh-access-to-an-ubuntu-instance/)
