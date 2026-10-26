#!/usr/bin/env bash
# ==============================================================================
# Lenovo Legion Y700 Gen 3 (TB321FU) - All-In-One Linux Hardware Fixes Installer
# ==============================================================================
# Installs:
#  1. Audio & UCM: fixes speakers dropping on external USB-C monitor connection.
#  2. Stylus & Digitizer: fixes Novatek scale calibration and Wayland rotation sync.
#  3. Power & Sensors: enables auto-brightness (ALS) and idle dimming.
#  4. Reboot to Android:
#     - /usr/local/sbin/back-to-android (A/B non-destructive dual-boot switcher)
#     - /usr/local/bin/back-to-android-gui (Zenity confirmation prompt)
#     - GNOME Shell Extension in quick settings power menu
#     - Desktop & Application menu launchers
# ==============================================================================

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

log() { echo -e "\033[1;32m[+] $*\033[0m"; }
info() { echo -e "\033[1;34m[*] $*\033[0m"; }
err() { echo -e "\033[1;31m[-] ERROR: $*\033[0m" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root (use sudo ./install-fixes.sh)"
fi

TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "sotiomake")}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

echo "=========================================================="
echo " Lenovo Legion Y700 Gen 3 (TB321FU) Fixes Installer"
echo " Target user: $TARGET_USER ($TARGET_HOME)"
echo "=========================================================="

# ------------------------------------------------------------------------------
# 1. Audio & ALSA UCM Fixes
# ------------------------------------------------------------------------------
log "1/5 Installing ALSA UCM audio configuration..."
mkdir -p /usr/share/alsa/ucm2/LenovoY700TB321
mkdir -p /usr/share/alsa/ucm2/conf.d/snd_soc_sc8280xp

cp "$SCRIPT_DIR/fixes/audio/LenovoY700TB321/LenovoY700TB321.conf" /usr/share/alsa/ucm2/LenovoY700TB321/
cp "$SCRIPT_DIR/fixes/audio/LenovoY700TB321/HiFi.conf" /usr/share/alsa/ucm2/LenovoY700TB321/
cp "$SCRIPT_DIR/fixes/audio/conf.d/snd_soc_sc8280xp/Lenovo-Y700-TB321FU.conf" /usr/share/alsa/ucm2/conf.d/snd_soc_sc8280xp/

# Restart sound server for the active user if possible
if command -v systemctl >/dev/null 2>&1; then
    USER_UID=$(id -u "$TARGET_USER")
    su - "$TARGET_USER" -c "XDG_RUNTIME_DIR=/run/user/$USER_UID systemctl --user restart wireplumber pipewire 2>/dev/null || true"
fi

# ------------------------------------------------------------------------------
# 2. Stylus & Digitizer Fixes
# ------------------------------------------------------------------------------
log "2/6 Installing Stylus, Digitizer & Touchscreen rules..."
mkdir -p /etc/udev/hwdb.d /etc/udev/rules.d /etc/libwacom /usr/share/libwacom /etc/modules-load.d

cp "$SCRIPT_DIR/fixes/stylus/70-y700-stylus.hwdb" /etc/udev/hwdb.d/
cp "$SCRIPT_DIR/fixes/stylus/70-y700-stylus.rules" /etc/udev/rules.d/

if [ -f "$SCRIPT_DIR/fixes/stylus/lenovo-y700-pen.tablet" ]; then
    cp "$SCRIPT_DIR/fixes/stylus/lenovo-y700-pen.tablet" /etc/libwacom/
    cp "$SCRIPT_DIR/fixes/stylus/lenovo-y700-pen.tablet" /usr/share/libwacom/
fi

echo "nt36523_ts" > /etc/modules-load.d/y700-touch.conf

systemd-hwdb update || true
udevadm control --reload || true
udevadm trigger || true

# ------------------------------------------------------------------------------
# 3. 16 GB ZRAM In-Memory Fast Swap
# ------------------------------------------------------------------------------
log "3/6 Installing 16 GB ZRAM fast swap configuration..."
if command -v apt-get >/dev/null 2>&1; then
    if ! dpkg -s systemd-zram-generator >/dev/null 2>&1; then
        apt-get update -qq || true
        apt-get install -y -qq systemd-zram-generator || true
    fi
fi

if [ -d "$SCRIPT_DIR/fixes/zram" ]; then
    cp "$SCRIPT_DIR/fixes/zram/zram-generator.conf" /etc/systemd/zram-generator.conf
    cp "$SCRIPT_DIR/fixes/zram/99-swap.conf" /etc/sysctl.d/99-swap.conf
    sysctl --system >/dev/null 2>&1 || true
    systemctl daemon-reload || true
    systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 4. Power & Sensors (Auto-Brightness)
# ------------------------------------------------------------------------------
log "4/6 Installing Power & Ambient Sensor (ALS) profile..."
mkdir -p /etc/dconf/db/local.d
cp "$SCRIPT_DIR/fixes/power-and-sensors/01-power" /etc/dconf/db/local.d/
dconf update || true

# ------------------------------------------------------------------------------
# 5. Reboot to Android Utilities & Permissions
# ------------------------------------------------------------------------------
log "5/6 Installing Reboot to Android scripts & passwordless sudoers..."
cp "$SCRIPT_DIR/fixes/reboot-to-android/back-to-android" /usr/local/sbin/
chmod 755 /usr/local/sbin/back-to-android

cp "$SCRIPT_DIR/fixes/reboot-to-android/back-to-android-gui" /usr/local/bin/
chmod 755 /usr/local/bin/back-to-android-gui

# Ensure sudoers allows passwordless reboot for back-to-android
mkdir -p /etc/sudoers.d
cat << "SUDO_EOF" > /etc/sudoers.d/99-back-to-android
ALL ALL=(root) NOPASSWD: /usr/local/sbin/back-to-android
SUDO_EOF
chmod 440 /etc/sudoers.d/99-back-to-android

# Desktop file
cp "$SCRIPT_DIR/fixes/reboot-to-android/back-to-android.desktop" /usr/share/applications/

# Desktop shortcuts
for d in "$TARGET_HOME/Desktop" "$TARGET_HOME/Рабочий стол"; do
    if [ -d "$d" ]; then
        cp "$SCRIPT_DIR/fixes/reboot-to-android/back-to-android.desktop" "$d/"
        chown "$TARGET_USER:$TARGET_USER" "$d/back-to-android.desktop"
        chmod +x "$d/back-to-android.desktop"
        su - "$TARGET_USER" -c "gio set '$d/back-to-android.desktop' metadata::trusted true 2>/dev/null || true"
    fi
done

# ------------------------------------------------------------------------------
# 6. GNOME Shell Extension
# ------------------------------------------------------------------------------
log "6/6 Installing GNOME Shell Extension in system power menu..."
EXT_DIR="/usr/share/gnome-shell/extensions/reboot-to-android@sotiomake"
mkdir -p "$EXT_DIR"
cp "$SCRIPT_DIR/fixes/reboot-to-android/gnome-extension/reboot-to-android@sotiomake/metadata.json" "$EXT_DIR/"
cp "$SCRIPT_DIR/fixes/reboot-to-android/gnome-extension/reboot-to-android@sotiomake/extension.js" "$EXT_DIR/"
chmod -R 755 "$EXT_DIR"

# Add to Ubuntu session mode enabledExtensions
UBUNTU_MODE="/usr/share/gnome-shell/modes/ubuntu.json"
if [ -f "$UBUNTU_MODE" ] && command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json
try:
    with open('$UBUNTU_MODE', 'r') as f:
        data = json.load(f)
    exts = data.get('enabledExtensions', [])
    if 'reboot-to-android@sotiomake' not in exts:
        exts.append('reboot-to-android@sotiomake')
        data['enabledExtensions'] = exts
        with open('$UBUNTU_MODE', 'w') as f:
            json.dump(data, f, indent=4)
        print('Added extension to $UBUNTU_MODE')
except Exception as e:
    print('Failed to update ubuntu.json:', e)
"
fi

echo ""
log "All fixes successfully installed!"
echo "Note: If you are currently in a GNOME session, log out or restart gdm to see the new menu item."
