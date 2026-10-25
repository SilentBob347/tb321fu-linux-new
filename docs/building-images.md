# Guide: Building Boot and RootFS Images for Lenovo Legion Y700 Gen 3 (TB321FU)

[English](building-images.md) | [Русская версия](building-images.ru.md)

This document explains how to compile and prepare the two system payloads required for Linux dual-boot on the TB321FU:
1. **`y700boot.img`**: The 1 GiB FAT32 EFI boot partition image containing the kernel, Device Tree Blob, and direct EFI loader.
2. **`rootfs.tar.gz`**: The Ubuntu 26.04/24.04 ARM64 root filesystem archive containing GNOME Wayland and TB321FU hardware packages.

---

## 🛠️ Prerequisites & Build Dependencies

On Debian/Ubuntu host machines, install required tooling:
```bash
sudo apt-get update
sudo apt-get install -y dosfstools mtools debootstrap e2fsprogs tar gzip qemu-user-static
```

---

## 1. Building the Boot Image (`y700boot.img`)

The boot partition image is written to internal partition `/dev/block/sda17` (`Y700BOOT`).  
It must use **4096-byte sector alignment** to match the native physical block size of the UFS 4.0 storage.

We provide an automated script [`tools/build-boot-image.sh`](../tools/build-boot-image.sh) that builds the image using `mtools` without needing loopback root privileges:

```bash
./tools/build-boot-image.sh
```

### What this script does:
1. Creates a 1024 MiB blank image file at `boot/y700boot.img`.
2. Formats it as FAT32 with 4K cluster alignment (`mkfs.vfat -F 32 -S 4096 -n Y700BOOT`).
3. Copies kernel and device tree:
   * `boot/Image` -> `/Image`
   * `boot/dtb/platform.dtb` -> `/dtb/platform.dtb`
4. Deploys the direct EFI loader:
   * `boot/EFI/BOOT/QCOMRAMP.EFI` -> `/EFI/BOOT/BOOTAA64.EFI`
   * `boot/EFI/BOOT/QCOMRAMP.EFI` -> `/EFI/BOOT/QCOMRAMP.EFI`
5. Copies [`boot/EFI/BOOT/linux.cfg`](../boot/EFI/BOOT/linux.cfg) across standard config paths (`/EFI/BOOT/linux.cfg`, `/linux.cfg`, `/boot/grub/grub.cfg`).

Output file: `boot/y700boot.img` (~1.0 GB).

---

## 2. Building the Root Filesystem (`rootfs.tar.gz`)

The root filesystem is unpacked onto internal partition `/dev/block/sda18` (`tb321fu-root`).

### Option A: Automated Build via `rootfs/build-rootfs.sh` (Recommended)

The repository includes a complete bootstrap script [`rootfs/build-rootfs.sh`](../rootfs/build-rootfs.sh) that sets up Ubuntu GNOME Wayland from upstream `ports.ubuntu.com` repositories:

1. **Create and mount a temporary ext4 build workspace:**
   ```bash
   truncate -s 20G /tmp/rootfs_workspace.ext4
   mkfs.ext4 -L tb321fu-root /tmp/rootfs_workspace.ext4
   mkdir -p /tmp/mnt_rootfs
   sudo mount /tmp/rootfs_workspace.ext4 /tmp/mnt_rootfs
   ```

2. **Run the rootfs builder:**
   ```bash
   # Syntax: sudo rootfs/build-rootfs.sh TARGET_DIR [noble|resolute]
   sudo rootfs/build-rootfs.sh /tmp/mnt_rootfs resolute
   ```

   **What the script configures automatically:**
   * Runs `debootstrap` for ARM64 (`aarch64`).
   * Configures APT sources and disables Snapd for maximum performance.
   * Installs lightweight GNOME Wayland, PipeWire/WirePlumber, and system utilities.
   * Installs TB321FU kernel modules (`packages/*.deb`).
   * Configures `fstab` (`PARTLABEL=tb321fu-root` as `/` and `PARTLABEL=Y700BOOT` as `/boot/efi`).
   * Configures default user `sotiomake` (password `2141`) with sudo permissions.
   * Configures automatic Wayland login in GDM3 and installs the autorotation daemon.

3. **Pack the workspace into `rootfs.tar.gz`:**
   ```bash
   cd /tmp/mnt_rootfs
   sudo tar -czf /home/sotiomake/tb321fu-linux/rootfs.tar.gz .
   cd -
   sudo umount /tmp/mnt_rootfs
   rm -f /tmp/rootfs_workspace.ext4
   ```

---

### Option B: Backing Up an Existing Working Installation

If you already have a configured TB321FU Linux installation and want to make a deployable archive:

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

## 🚀 Flashing & Deployment

Once both `boot/y700boot.img` and `rootfs.tar.gz` are ready:
Follow the complete deployment steps in:  
👉 [**docs/internal-partitioning-and-installation.md**](internal-partitioning-and-installation.md)
