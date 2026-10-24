# Lenovo Legion Y700 Gen 3 (TB321FU) Linux Dual-Boot

Non-destructive dual-boot Linux port for the Lenovo Legion Y700 Gen 3 (`TB321FU`), Qualcomm Snapdragon 8 Gen 3 (`SM8650` / `pineapple`).

Based on the dual-boot architecture of [tb323fu-linux](https://github.com/joonhoekim/tb323fu-linux) by Joonhoe Kim, combined with the SM8650 hardware bring-up from GUF296.

---

## Key Differences from Legacy/GUF296 Methods

| Feature | GUF296 Method | `tb321fu-linux` Dual-Boot |
|---|---|---|
| **Android System (`super`)** | ❌ Wiped (overwritten with grub.img) | ✅ **Untouched** (stays 100% stock) |
| **Android Data (`userdata`)** | ❌ Wiped (overwritten with rootfs.img) | ✅ **Preserved** (Linux on USB SSD or shrunk partition) |
| **Boot Chain** | Destructive single-boot UEFI | Non-destructive A/B slot dual-boot |
| **Switch to Android** | Requires full EDL / QFIL restore | 1-click in Linux or emergency volume buttons |
| **Switch to Linux** | N/A (Android destroyed) | 1-click in Android via KernelSU / Magisk module |

---

## Directory Structure

```
/home/sotiomake/tb321fu-linux/
├── android/
│   ├── back-to-android       # Linux command to restore Android boot_b into boot_a
│   ├── install-module.sh     # Android setup helper (backup boot_b & make module)
│   └── switch-to-linux/      # KernelSU / Magisk module with Action button
├── boot/
│   ├── boot.img              # 2.4 MB Android bootloader image for slot boot_a
│   ├── Image                 # Compiled Linux 7.1.1 ARM64 kernel (SM8650)
│   ├── dtb/
│   │   ├── sm8650-lenovo-tb321fu.dtb
│   │   └── platform.dtb
│   └── EFI/BOOT/
│       ├── BOOTAA64.EFI      # GRUB EFI entry
│       ├── QCOMRAMP.EFI      # Patched direct loader (reads dynamic linux.cfg)
│       ├── grub.cfg          # Chainloader
│       └── linux.cfg         # Plain-text editable boot configuration
├── packages/
│   ├── y700-daily-kernel-modules_7.1.1-00009-g570b90203d97_arm64.deb
│   └── y700-daily-rootfs-overlay_0.1+20260624-201420_arm64.deb
└── tools/
    ├── prepare-usb-ssd.sh    # Format external USB SSD (FAT32 boot + ext4 root)
    └── flash-boot-a.sh       # Fastboot helper to flash boot_a
```

---

## Quick Start Guide

### Step 1: Format External USB SSD
Plug in a USB SSD or USB-C flash drive and run:
```bash
sudo tools/prepare-usb-ssd.sh /dev/sdX
```
This creates:
- Partition 1 (`Y700BOOT`, FAT32): kernel, dtb, patched EFI loader, `linux.cfg`.
- Partition 2 (`tb321fu-root`, ext4): formatted and ready for rootfs.

### Step 2: Extract Rootfs
Mount Partition 2 of the USB SSD and extract rootfs (Ubuntu 26.04 Noble / Arch / Kubuntu), then install packages from `packages/` and copy `android/back-to-android` to `/usr/local/sbin/`.

### Step 3: Backup Android boot and Install KernelSU Module
Connect TB321FU to PC/tablet via USB:
```bash
cd android
./install-module.sh prepare-boot-b
./install-module.sh install
```
This saves stock Android `boot.img` safely into `boot_b` and generates the `Switch to Linux` module.

### Step 4: Flash Linux Bootloader
Reboot tablet into bootloader (`adb reboot bootloader`):
```bash
tools/flash-boot-a.sh
```

### Step 5: Booting and Switching
- Plug in the USB SSD and turn on the tablet -> Boots into Linux!
- To return to Android:
  - In Linux terminal: `sudo back-to-android <sha256>`
  - Or emergency chord: **Hold Volume Up + Down together for 10 seconds**!
- To boot back to Linux from Android:
  - Open KernelSU / Magisk -> tap Action on **Switch to Linux**.
