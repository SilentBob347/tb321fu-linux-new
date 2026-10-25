# Пошаговая инструкция: Разметка внутренней памяти UFS и установка Linux Dual-Boot на Lenovo Legion Y700 Gen 3 (TB321FU)

В данном руководстве подробно описан процесс создания настоящего **неразрушающего Dual-Boot** с разделением внутренней UFS-памяти планшета (50% Android / 50% Linux), а также процесс разворачивания загрузочного раздела и корневой системы Ubuntu.

---

## ⚠️ Важное замечание: почему именно внутренняя память, а не USB SSD?
В загрузчике EDK2 UEFI для SM8650 драйвер контроллера Type-C (`FSA4480`) на текущем этапе не подаёт питание VBUS на порт до загрузки ядра Linux. В результате внешние USB-накопители не видны на этапе UEFI/GRUB.  
Внутренняя быстрая память UFS 4.0 (`/dev/block/sda`) поддерживается нативным драйвером `UFSDxe`, благодаря чему система загружается с неё мгновенно и без внешних проводов.

---

## 📋 Предварительные требования
1. **Разблокированный загрузчик (Bootloader)** на планшете TB321FU.
2. **Root-доступ в Android** (через KernelSU или Magisk).
3. **Компьютер с Linux** (с установленными `adb`, `fastboot`, `python3`).
4. Подключение планшета к компьютеру по кабелю USB-C с включённой «Отладкой по USB» в настройках разработчика Android.

---

## Шаг 1. Резервное копирование таблицы GPT и стокового ядра

1. Сохраните оригинальную таблицу разделов GPT с диска `/dev/block/sda` (размер сектора UFS — 4096 байт):
   ```bash
   adb shell "su -c 'dd if=/dev/block/sda of=/data/local/tmp/gpt_stock.bin bs=4096 count=3'"
   adb pull /data/local/tmp/gpt_stock.bin android/gpt_stock.bin
   ```
2. Сохраните стоковый загрузочный образ Android в неактивный слот `boot_b` (который планшет никогда не использует при виртуальном A/B):
   ```bash
   adb shell "su -c 'dd if=/dev/block/by-name/boot_a of=/dev/block/by-name/boot_b bs=4M count=24 conv=fsync'"
   ```

---

## Шаг 2. Генерация новой таблицы разделов (50/50 Split)

Скрипт [`tools/repartition-gpt.py`](../tools/repartition-gpt.py) уменьшает раздел `userdata` (раздел 16) и создаёт два новых раздела в освободившемся месте:
* **Раздел 16 (`userdata`)**: сжимается с 470 ГБ до **228.00 ГБ** (для Android).
* **Раздел 17 (`Y700BOOT`)**: создаётся размером **1.00 ГБ** (тип `EFI System Partition`, FAT32).
* **Раздел 18 (`tb321fu-root`)**: создаётся размером **227.82 ГБ** (тип `Linux Filesystem`, ext4).

Запустите скрипт на компьютере:
```bash
python3 tools/repartition-gpt.py
```
Скрипт считает `android/gpt_stock.bin`, пересчитает контрольные суммы CRC32 и сгенерирует файлы:
* `android/gpt_new_primary.bin` (LBA 0–2, 12288 байт)
* `android/gpt_new_backup.bin` (Backup GPT в конце диска)

---

## Шаг 3. Запись новой таблицы GPT на планшет

1. Загрузите сгенерированные таблицы на планшет:
   ```bash
   adb push android/gpt_new_primary.bin /data/local/tmp/
   adb push android/gpt_new_backup.bin /data/local/tmp/
   ```
2. Запишите основную и резервную таблицы GPT:
   ```bash
   # Запись первичной таблицы GPT (LBA 0-2)
   adb shell "su -c 'dd if=/data/local/tmp/gpt_new_primary.bin of=/dev/block/sda bs=4096 count=3 conv=fsync'"

   # Запись резервной таблицы GPT (в конец диска LBA 123365374)
   adb shell "su -c 'dd if=/data/local/tmp/gpt_new_backup.bin of=/dev/block/sda seek=123365374 bs=4096 count=2 conv=fsync'"
   sync
   ```
3. **Сброс userdata (Factory Reset):**  
   Поскольку размер раздела `userdata` изменился, файловая система F2FS Android должна быть отформатирована под новый размер:
   * Перезагрузите планшет в Recovery и выполните **Wipe Data / Factory Reset** (либо через настройки Android: «Сброс до заводских настроек»).
   * После перезагрузки Android запустится штатно, и в настройках накопителя будет отображаться ~256 ГБ памяти.

---

## Шаг 4. Форматирование новых разделов `sda17` и `sda18`

После первой загрузки настройте Android и верните Root (KernelSU / Magisk). Подключитесь по ADB:

```bash
# 1. Форматируем раздел 17 в FAT32 с меткой Y700BOOT (сектор 4096)
adb shell "su -c 'mkfs.vfat -F 32 -S 4096 -n Y700BOOT /dev/block/sda17'"

# 2. Форматируем раздел 18 в ext4 с меткой tb321fu-root
adb shell "su -c 'mke2fs -t ext4 -F -L tb321fu-root /dev/block/sda18'"
```

---

## Шаг 5. Запись загрузочного раздела (`sda17`)

Раздел `sda17` содержит ядро Linux 7.1.1, DTB и загрузчик GRUB/EFI. Запишите готовый образ `y700boot.img`:

```bash
# Если образ в архиве .gz, сначала распакуйте: gzip -dk boot/y700boot.img.gz
adb push boot/y700boot.img /data/local/tmp/
adb shell "su -c 'dd if=/data/local/tmp/y700boot.img of=/dev/block/sda17 bs=4M conv=fsync && rm /data/local/tmp/y700boot.img'"
```

---

## Шаг 6. Разворачивание корневой системы Ubuntu (`sda18`)

1. Смонтируйте раздел `sda18` во временную папку в Android:
   ```bash
   adb shell "su -c 'mkdir -p /data/local/tmp/linux_root && mount -t ext4 /dev/block/sda18 /data/local/tmp/linux_root'"
   ```
2. Отправьте архив корневой системы `rootfs.tar.gz` на планшет:
   ```bash
   adb push rootfs.tar.gz /data/local/tmp/
   ```
3. Распакуйте корневую систему с сохранением всех прав доступа:
   ```bash
   adb shell "su -c 'tar -xzf /data/local/tmp/rootfs.tar.gz -C /data/local/tmp/linux_root/ && sync'"
   ```
4. Удалите архив и отмонтируйте раздел:
   ```bash
   adb shell "su -c 'rm /data/local/tmp/rootfs.tar.gz && umount /data/local/tmp/linux_root'"
   ```

---

## Шаг 7. Установка модуля KernelSU / Magisk для переключения в Linux

1. На компьютере перейдите в папку `android/`:
   ```bash
   cd android
   ./install-module.sh prepare-boot-b
   ./install-module.sh install
   ```
2. В приложении KernelSU или Magisk на планшете появится модуль **«Switch to Linux (TB321FU)»**.

---

## Шаг 8. Первый запуск Linux и установка фиксов оборудования

1. В приложении KernelSU / Magisk нажмите кнопку **«Действие» (Action)** у модуля переключения.  
   *Планшет запишет загрузчик Linux в `boot_a` и перезагрузится прямо в Ubuntu.*
2. Дождитесь запуска GNOME и авторизуйтесь (по умолчанию: логин `sotiomake`, пароль `2141`).
3. Запустите скрипт автоматической установки исправлений:
   ```bash
   cd ~/tb321fu-linux
   sudo ./install-fixes.sh
   ```
4. Скрипт настроит звук для внешних мониторов, калибровку и автоповорот стилуса, автояркость и добавит пункт **«Перезапуск в Android…»** в меню выключения GNOME.

---

## Как переключаться между системами в дальнейшем:
* **Из Android в Linux:** Откройте KernelSU / Magisk -> нажмите **Action** на модуле *Switch to Linux*.
* **Из Linux в Android:**
  * Нажмите в правом верхнем углу меню питания -> **📱 «Перезапуск в Android…»**
  * Или нажмите иконку **«Перезапуск в Android»** прямо на рабочем столе.
  * *Аварийный способ:* Зажмите обе кнопки громкости (**Volume Up + Volume Down**) на 10 секунд при включении.
