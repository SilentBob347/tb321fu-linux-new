# Руководство: Сборка и подготовка образов Boot и RootFS для Lenovo Legion Y700 Gen 3 (TB321FU)

[English](building-images.md) | [Русская версия](building-images.ru.md)

В этом документе описывается, как с нуля скомпилировать и подготовить два основных компонента, необходимых для запуска Linux Dual-Boot на TB321FU:
1. **`y700boot.img`**: образ загрузочного раздела FAT32 объёмом 1 ГБ, содержащий ядро, DTB и прямой EFI-загрузчик.
2. **`rootfs.tar.gz`**: архив корневой файловой системы Ubuntu 26.04/24.04 ARM64 с графическим окружением GNOME Wayland и модулями ядра TB321FU.

---

## 🛠️ Зависимости для сборки

На компьютере с Linux (Ubuntu / Debian) установите необходимые утилиты:
```bash
sudo apt-get update
sudo apt-get install -y dosfstools mtools debootstrap e2fsprogs tar gzip qemu-user-static
```

---

## 1. Сборка загрузочного образа (`y700boot.img`)

Этот образ прошивается во внутренний раздел `/dev/block/sda17` (`Y700BOOT`).  
Он должен иметь **размер сектора 4096 байт** для точного соответствия физическому размеру блоков флеш-памяти UFS 4.0.

В репозиторий добавлен скрипт [`tools/build-boot-image.sh`](../tools/build-boot-image.sh), который собирает образ через `mtools` без необходимости root-прав для loopback-монтирования:

```bash
./tools/build-boot-image.sh
```

### Что делает скрипт:
1. Создаёт пустой образ размером 1024 МБ в `boot/y700boot.img`.
2. Форматирует его в FAT32 с выравниванием по 4K-секторам (`mkfs.vfat -F 32 -S 4096 -n Y700BOOT`).
3. Копирует ядро и дерево устройств:
   * `boot/Image` -> `/Image`
   * `boot/dtb/platform.dtb` -> `/dtb/platform.dtb`
4. Разворачивает прямой EFI-загрузчик:
   * `boot/EFI/BOOT/QCOMRAMP.EFI` -> `/EFI/BOOT/BOOTAA64.EFI`
   * `boot/EFI/BOOT/QCOMRAMP.EFI` -> `/EFI/BOOT/QCOMRAMP.EFI`
5. Дублирует файл конфигурации [`boot/EFI/BOOT/linux.cfg`](../boot/EFI/BOOT/linux.cfg) во все стандартные пути поиска (`/EFI/BOOT/linux.cfg`, `/linux.cfg`, `/boot/grub/grub.cfg`).

Итоговый файл: `boot/y700boot.img` (~1.0 ГБ).

---

## 2. Сборка корневой файловой системы (`rootfs.tar.gz`)

Корневая система распаковывается во внутренний раздел `/dev/block/sda18` (`tb321fu-root`).

### Вариант A: Автоматическая сборка через `rootfs/build-rootfs.sh` (Рекомендуется)

В репозитории есть скрипт [`rootfs/build-rootfs.sh`](../rootfs/build-rootfs.sh), который разворачивает чистый Ubuntu GNOME Wayland из официальных репозиториев `ports.ubuntu.com`:

1. **Создайте и смонтируйте временную ext4-папку для сборки:**
   ```bash
   truncate -s 20G /tmp/rootfs_workspace.ext4
   mkfs.ext4 -L tb321fu-root /tmp/rootfs_workspace.ext4
   mkdir -p /tmp/mnt_rootfs
   sudo mount /tmp/rootfs_workspace.ext4 /tmp/mnt_rootfs
   ```

2. **Запустите сборщик rootfs:**
   ```bash
   # Синтаксис: sudo rootfs/build-rootfs.sh ЦЕЛЕВАЯ_ПАПКА [noble|resolute]
   sudo rootfs/build-rootfs.sh /tmp/mnt_rootfs resolute
   ```

   **Что скрипт настраивает автоматически:**
   * Скачивает базовую систему через `debootstrap` для ARM64 (`aarch64`).
   * Настраивает репозитории APT и отключает Snapd для максимального быстродействия.
   * Устанавливает легковесный GNOME Wayland, звуковой сервер PipeWire/WirePlumber и базовые системные пакеты.
   * Устанавливает модули ядра TB321FU (`packages/*.deb`).
   * Прописывает точки монтирования в `fstab` (`PARTLABEL=tb321fu-root` как `/` и `PARTLABEL=Y700BOOT` как `/boot/efi`).
   * Создаёт пользователя по умолчанию `sotiomake` (пароль `2141`) с правами sudo.
   * Настраивает автологин в GDM3 и устанавливает службу автоповорота экрана.

3. **Упакуйте рабочее пространство в архив `rootfs.tar.gz`:**
   ```bash
   cd /tmp/mnt_rootfs
   sudo tar -czf /home/sotiomake/tb321fu-linux/rootfs.tar.gz .
   cd -
   sudo umount /tmp/mnt_rootfs
   rm -f /tmp/rootfs_workspace.ext4
   ```

---

### Вариант B: Создание архива из уже работающей системы на планшете

Если у вас уже настроена рабочая система на планшете и вы хотите сохранить её в архив для переноса:

```bash
sudo tar -C / -czf rootfs.tar.gz \
  --exclude='proc/*' \
  --exclude='sys/*' \
  --exclude='dev/*' \
  --exclude='run/*' \
  --exclude='tmp/*' \
  --exclude='mnt/*' \
  --exclude='media/*' \
  --exclude='var/cache/apt/archives/*' \
  --exclude='home/*/.cache/*' \
  .
```

---

## 🚀 Прошивка и установка

Когда оба файла `boot/y700boot.img` и `rootfs.tar.gz` готовы:
Следуйте полной пошаговой инструкции по установке:  
👉 [**docs/internal-partitioning-and-installation.ru.md**](internal-partitioning-and-installation.ru.md)
