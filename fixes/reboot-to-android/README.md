# Reboot to Android (Dual-Boot Integration)

Provides multiple seamless, user-friendly ways to reboot from Linux into Android ZUI without touching user data or reflashing:

1. **System Power Menu (GNOME Shell Extension):**
   - Integrates natively into the GNOME quick settings shutdown menu (right after Log Out / Power Off).
   - Tapping «Перезапуск в Android…» shows a standard modal confirmation dialog and reboots to Android.
2. **Desktop & App Menu Shortcut:**
   - «Перезапуск в Android» icon on Desktop (`~/Desktop` & `~/Рабочий стол`) with a simple confirmation prompt (Zenity GUI).
3. **Emergency Hardware Combo:**
   - Holding **Volume Up + Volume Down for 10 seconds** runs `/usr/local/sbin/back-to-android` even if the graphical shell freezes.

## How It Works:
- The stock Android boot image is preserved safely on `boot_b`.
- When switching to Android, `/usr/local/sbin/back-to-android`:
  1. Backs up current Linux bootloader from `boot_a` to `/var/lib/tb321fu/linux-current.img`.
  2. Verifies `boot_b` SHA-256 integrity.
  3. Copies the Android boot image back into active slot `boot_a`.
  4. Triggers a clean reboot into Android.
- From Android, the tablet can switch back to Linux at any time with 1 tap via the KernelSU / Magisk module located in `android/switch-to-linux/`.

## Manual Installation:
```bash
sudo cp back-to-android /usr/local/sbin/
sudo chmod +x /usr/local/sbin/back-to-android

sudo cp back-to-android-gui /usr/local/bin/
sudo chmod +x /usr/local/bin/back-to-android-gui

sudo cp back-to-android.desktop /usr/share/applications/
cp back-to-android.desktop ~/Desktop/
chmod +x ~/Desktop/back-to-android.desktop
gio set ~/Desktop/back-to-android.desktop metadata::trusted true

# System GNOME extension
sudo mkdir -p /usr/share/gnome-shell/extensions/reboot-to-android@sotiomake
sudo cp gnome-extension/reboot-to-android@sotiomake/* /usr/share/gnome-shell/extensions/reboot-to-android@sotiomake/
```
