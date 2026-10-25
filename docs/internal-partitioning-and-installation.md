# Step-by-Step Guide: Internal UFS Dual-Boot Partitioning & Installation on Lenovo Legion Y700 Gen 3 (TB321FU)

[English](internal-partitioning-and-installation.md) | [Русская версия](internal-partitioning-and-installation.ru.md)

This guide walks you through setting up a **true non-destructive Dual-Boot** on the tablet's internal UFS 4.0 storage (50% Android ZUI / 50% Ubuntu Linux), including partition division, EFI bootloader setup, and root filesystem extraction.

---

## ⚠️ Why Internal UFS Storage instead of USB SSD?
In the current EDK2 UEFI bring-up for Qualcomm SM8650, the Type-C switch driver (`FSA4480`) does not supply VBUS power to external ports before the Linux kernel boots. Consequently, external USB drives are completely invisible to UEFI and GRUB.  
In contrast, internal UFS 4.0 storage (`/dev/block/sda`) is handled natively by the `UFSDxe` UEFI driver and boots instantaneously with zero cables or external dongles attached.

---

## 📋 Prerequisites
1. **Unlocked Bootloader** on the Lenovo Legion Y700 Gen 3 (`TB321FU`).
2. **Root Access in Android** (via KernelSU or Magisk).
3. **Host PC running Linux** with `adb`, `fastboot`, and `python3` installed.
4. USB-C data cable connecting tablet to PC, with **USB Debugging** enabled in Android Developer Options.

---

## Step 1. Backup Stock GPT Table & Stock Kernel

1. Dump the original GPT partition table from disk `/dev/block/sda` (UFS sector size is 4096 bytes):
   ```bash
   adb shell "su -c 'dd if=/dev/block/sda of=/data/local/tmp/gpt_stock.bin bs=4096 count=3'"
   adb pull /data/local/tmp/gpt_stock.bin android/gpt_stock.bin
   ```
2. Backup the running stock Android boot image into inactive slot `boot_b` (virtual A/B tablets never boot slot `_b`):
   ```bash
   adb shell "su -c 'dd if=/dev/block/by-name/boot_a of=/dev/block/by-name/boot_b bs=4M count=24 conv=fsync'"
   ```

---

## Step 2. Generate New Partition Table (50/50 Split)

The [`tools/repartition-gpt.py`](../tools/repartition-gpt.py) script resizes partition 16 (`userdata`) and adds two new dedicated partitions in the freed space:
* **Partition 16 (`userdata`)**: Shrunk from ~470 GiB down to **228.00 GiB** (for Android).
* **Partition 17 (`Y700BOOT`)**: Created as **1.00 GiB** (type `EFI System Partition`, FAT32).
* **Partition 18 (`tb321fu-root`)**: Created as **227.82 GiB** (type `Linux filesystem data`, ext4).

Run the repartition script on your host PC:
```bash
python3 tools/repartition-gpt.py
```
The script parses `android/gpt_stock.bin`, updates partition bounds, calculates fresh CRC32 checksums, and produces:
* `android/gpt_new_primary.bin` (LBA 0–2, 12,288 bytes)
* `android/gpt_new_backup.bin` (Backup GPT at the end of the disk)

---

## Step 3. Flash New GPT Table to Tablet

1. Push the generated partition tables to the tablet:
   ```bash
   adb push android/gpt_new_primary.bin /data/local/tmp/
   adb push android/gpt_new_backup.bin /data/local/tmp/
   ```
2. Write primary and backup GPT tables:
   ```bash
   # Flash Primary GPT (LBA 0-2)
   adb shell "su -c 'dd if=/data/local/tmp/gpt_new_primary.bin of=/dev/block/sda bs=4096 count=3 conv=fsync'"

   # Flash Backup GPT (at disk end LBA 123365374)
   adb shell "su -c 'dd if=/data/local/tmp/gpt_new_backup.bin of=/dev/block/sda seek=123365374 bs=4096 count=2 conv=fsync'"
   sync
   ```
3. **Android Factory Reset (Resize userdata):**  
   Because the physical boundaries of `userdata` have changed, Android's F2FS filesystem must be re-formatted to match the new size:
   * Reboot tablet into Recovery and perform **Wipe Data / Factory Reset** (or navigate to Android Settings -> System -> Reset Options -> Erase all data).
   * After rebooting, Android will start fresh with ~256 GB total storage reported.

---

## Step 4. Format New Partitions (`sda17` & `sda18`)

After Android boots up, complete initial setup and restore root access (KernelSU / Magisk). Open ADB shell:

```bash
# 1. Format Partition 17 as FAT32 with label Y700BOOT (4K sector alignment)
adb shell "su -c 'mkfs.vfat -F 32 -S 4096 -n Y700BOOT /dev/block/sda17'"

# 2. Format Partition 18 as ext4 with label tb321fu-root
adb shell "su -c 'mke2fs -t ext4 -F -L tb321fu-root /dev/block/sda18'"
```

---

## Step 5. Write Bootloader Partition (`sda17`)

Partition `sda17` holds the Linux 7.1.1 kernel, Device Tree Blob, and GRUB/EFI direct loader. Write the pre-built `y700boot.img` image directly:

```bash
# If your image is compressed, unpack first: gzip -dk boot/y700boot.img.gz
adb push boot/y700boot.img /data/local/tmp/
adb shell "su -c 'dd if=/data/local/tmp/y700boot.img of=/dev/block/sda17 bs=4M conv=fsync && rm /data/local/tmp/y700boot.img'"
```

---

## Step 6. Extract Ubuntu Root Filesystem (`sda18`)

1. Mount partition `sda18` into a temporary directory in Android:
   ```bash
   adb shell "su -c 'mkdir -p /data/local/tmp/linux_root && mount -t ext4 /dev/block/sda18 /data/local/tmp/linux_root'"
   ```
2. Upload the rootfs tarball to the device:
   ```bash
   adb push rootfs.tar.gz /data/local/tmp/
   ```
3. Extract rootfs preserving all Linux file permissions:
   ```bash
   adb shell "su -c 'tar -xzf /data/local/tmp/rootfs.tar.gz -C /data/local/tmp/linux_root/ && sync'"
   ```
4. Clean up and unmount:
   ```bash
   adb shell "su -c 'rm /data/local/tmp/rootfs.tar.gz && umount /data/local/tmp/linux_root'"
   ```

---

## Step 7. Install KernelSU / Magisk Dual-Boot Module

1. On your PC, navigate into the `android/` directory:
   ```bash
   cd android
   ./install-module.sh prepare-boot-b
   ./install-module.sh install
   ```
2. In KernelSU or Magisk manager on the tablet, you will now see the module **«Switch to Linux (TB321FU)»**.

---

## Step 8. First Boot into Linux & Apply Community Fixes

1. In KernelSU / Magisk manager, tap the **Action** button next to *Switch to Linux*.  
   *The tablet writes the Linux bootloader to `boot_a` and boots straight into Ubuntu.*
2. Complete login in GNOME Wayland (default credentials: username `sotiomake`, password `2141`).
3. Run the automated fixes installer:
   ```bash
   git clone https://github.com/vitalo233-eng/tb321fu-linux.git
   cd tb321fu-linux
   sudo ./install-fixes.sh
   ```
4. The installer configures external display audio, stylus scaling and auto-rotation, auto-brightness, and integrates the **«Reboot to Android…»** button into the system power menu.

---

## Switching Between OSes Anytime:
* **Android -> Linux:** Open KernelSU / Magisk -> tap **Action** on *Switch to Linux*.
* **Linux -> Android:**
  * Click top-right status area -> Power menu -> **📱 «Reboot to Android…»**
  * Or double-click the **«Reboot to Android»** icon on your Desktop.
  * *Emergency fallback:* Hold **Volume Up + Volume Down** together for 10 seconds during startup.
