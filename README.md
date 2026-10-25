# Lenovo Legion Y700 Gen 3 (TB321FU) Linux Dual-Boot & Community Fixes

Non-destructive dual-boot Linux port and comprehensive hardware fixes for the **Lenovo Legion Y700 Gen 3 (`TB321FU`)**, powered by the **Qualcomm Snapdragon 8 Gen 3 (`SM8650` / `pineapple`)**.

Based on the dual-boot architecture of [tb323fu-linux](https://github.com/joonhoekim/tb323fu-linux) by Joonhoe Kim, combined with the mainline SM8650 bring-up from GUF296 and community improvements.

---

## 🚀 Hardware Support Matrix

| Hardware Component | Status | Notes & Fixes Applied |
|---|---|---|
| **CPU / SoC** | ✅ Working | Qualcomm SM8650 8-core (Cortex-X4, A720, A520) |
| **GPU / 3D Graphics** | ✅ Working | Adreno 750 (Mesa Turnip / Freedreno / Zink) |
| **Display Panel** | ✅ Working | 8.8" 2560×1600 (CSOT / Novatek NT36523, Dual-DSI, 144Hz / 165Hz) |
| **Touchscreen** | ✅ Working | Novatek NT36523 multi-touch over SPI (`spi4`) |
| **Stylus / Pen** | ✅ Working | **Fixed:** hwdb scale fix (136/135) + Wayland DSI-1 sync (rotates with screen) |
| **Internal Speakers** | ✅ Working | Dual AW882xx amplifiers on Secondary TDM |
| **Microphone** | ✅ Working | Qualcomm WCD939x analog capture (ADC1) |
| **External Monitor** | ✅ Working | **Fixed:** Type-C DP Alt Mode audio routing (no false speaker mute) |
| **Cameras** | ✅ Working | **Fixed:** Patched CAMSS CSI endpoints; rear (`sc820cs`) & front (`sc202cs`) |
| **Wi-Fi & Bluetooth** | ✅ Working | Qualcomm FastConnect 7800 (WCN7850 / WCN7851) |
| **Sensors & ALS** | ✅ Working | **Fixed:** Ambient Light Sensor auto-brightness enabled via dconf |
| **Dual-Boot Switching** | ✅ Working | **Fixed:** GNOME shutdown menu + Desktop 1-click + emergency hardware chord |

---

## ⚡ Quick Fixes Installation (1-Click)

If you already have Ubuntu or Kubuntu running on your TB321FU tablet, simply clone this repository and run:

```bash
git clone https://github.com/vitalo233-eng/tb321fu-linux.git
cd tb321fu-linux
sudo ./install-fixes.sh
```

This single command automatically deploys:
1. **ALSA UCM audio fix** (fixes internal speakers dropping when plugging into USB-C external monitors / docks).
2. **Stylus scale & orientation fix** (1:1 coordinate mapping and automatic rotation sync with display).
3. **GNOME Shell Android Reboot extension** (native button in quick settings shutdown menu).
4. **Desktop & Application launcher** for 1-click reboot to Android.
5. **Auto-brightness profile** (ambient light sensor integration in GNOME).

---

## 🛠️ Summary of Applied Fixes

### 1. USB-C External Monitor & Audio Fix (`fixes/audio/`)
* **Problem:** Connecting a Type-C cable, hub, or external monitor (DisplayPort Alt Mode) caused all tablet sound to disappear, leaving only `auto_null` ("Холостой выход"). Video playback on YouTube froze indefinitely.
* **Cause:** DisplayPort AUX channel lines in Type-C share physical SBU pins with Qualcomm WCD939x analog headset detection (MBHC). Cable connection falsely triggered "Headphones plugged in". Stock UCM had `JackHWMute "Speaker"` and a missing mixer element, crashing PipeWire's sink.
* **Solution:** Removed hardware muting, eliminated dead mixer controls, and set internal speakers and microphone to permanent high priority (`200`). Speakers and mic now play simultaneously without interruption.

### 2. Stylus Calibration & Wayland Orientation (`fixes/stylus/`)
* **Problem:** Pen pointer had wrong coordinate scaling and did not rotate when rotating the tablet in GNOME.
* **Solution:**
  * [`70-y700-stylus.hwdb`](fixes/stylus/70-y700-stylus.hwdb): Corrects `EVDEV_ABS_00=::136` and `EVDEV_ABS_01=::135`.
  * [`70-y700-stylus.rules`](fixes/stylus/70-y700-stylus.rules): Declares `ID_INPUT_TABLET_INTEGRATED=1` and assigns `WL_OUTPUT=DSI-1` so Wayland compositor rotates the pen together with the display.

### 3. Native "Reboot to Android" Extension (`fixes/reboot-to-android/`)
* Built-in GNOME Shell extension (`reboot-to-android@sotiomake`) adding **«Перезапуск в Android…»** to the system power menu (right next to Log Out / Power Off).
* Shows a standard confirmation dialog and cleanly swaps the boot image and reboots into ZUI.
* Desktop shortcut on `~/Desktop` and `~/Рабочий стол` for easy access by children.
* Emergency hardware combo: **Hold Volume Up + Volume Down for 10 seconds** to trigger reboot if GUI freezes.

### 4. Camera CAMSS Endpoint Fix (`patches/dts-camera-fix.patch`)
* **Problem:** Camera subsystem failed to probe sensors due to an invalid placeholder `camera@11` on CSI port 3.
* **Solution:** Disabled conflicting node in DTS; both `sc820cs` (rear) and `sc202cs` (front) cameras now initialize cleanly and stream via `libcamera` and PipeWire.

---

## 💾 Dual-Boot Architecture: How It Works

Traditional single-boot ports overwrite Android partitions (`super` and `userdata`), destroying Android.  
Our approach keeps Android 100% stock and safe:

1. **Android System & Data:**  
   - `sda16` (`userdata`) and `super` remain completely untouched.
   - Linux runs either from an external USB-C SSD or a dedicated secondary partition.
2. **A/B Slot Boot Switching:**  
   - Slot `boot_b` safely stores the stock Android boot image.
   - Slot `boot_a` runs the Linux bootloader (UEFI / GRUB `QCOMRAMP.EFI`).
   - When switching to Android: `/usr/local/sbin/back-to-android` copies the Android kernel from `boot_b` into `boot_a`.
   - When switching to Linux: In Android, tap **Switch to Linux** in the KernelSU / Magisk module to flash Linux kernel back into `boot_a`.

---

## 📦 Repository Structure

```
tb321fu-linux/
├── README.md                           # This documentation
├── install-fixes.sh                    # Automated all-in-one fixes installer
├── .gitignore                          # Ignores large raw images (>100MB)
├── fixes/
│   ├── audio/                          # ALSA UCM2 configs (external monitor fix)
│   ├── stylus/                         # Stylus hwdb & udev calibration rules
│   ├── power-and-sensors/              # Auto-brightness (ALS) dconf configuration
│   └── reboot-to-android/              # Dual-boot scripts & GNOME Shell extension
├── patches/
│   └── dts-camera-fix.patch            # Device tree camera patch
├── boot/                               # Verified EFI bootloader and Linux kernel
│   ├── boot.img                        # Android fastboot bootloader image
│   ├── Image                           # Linux 7.1.1 SM8650 kernel
│   ├── dtb/
│   │   ├── sm8650-lenovo-tb321fu.dtb   # Camera & Audio patched DTB
│   │   └── platform.dtb
│   └── EFI/BOOT/                       # GRUB & QCOMRAMP direct loader
├── android/                            # KernelSU / Magisk module for switching to Linux
│   └── switch-to-linux/
└── tools/                              # Drive preparation & flashing scripts
    ├── flash-boot-a.sh
    └── prepare-usb-ssd.sh
```

---

## 📄 License
Scripts and configurations are provided under the MIT / BSD-3-Clause License.  
Kernel and boot components are subject to GNU GPL v2.
