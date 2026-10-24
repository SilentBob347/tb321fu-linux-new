#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# build-rootfs.sh -- Build a clean Ubuntu GNOME root filesystem for Lenovo Legion Y700 Gen 3 (TB321FU)
# Run natively on an arm64 host into a mounted ext4 partition:
#   sudo ./build-rootfs.sh /mnt [noble|resolute]
set -euo pipefail

TARGET_DIR=${1:?Usage: sudo $0 TARGET_DIR [RELEASE]}
REL=${2:-resolute}
ROOT_PARTLABEL=${ROOT_PARTLABEL:-tb321fu-root}
HOSTNAME_NEW=${HOSTNAME_NEW:-tb321fu-ubuntu}
TIMEZONE=${TIMEZONE:-Europe/Kyiv}
USER_NAME=${USER_NAME:-sotiomake}
USER_PASS=${USER_PASS:-2141}
MIRROR="http://ports.ubuntu.com/ubuntu-ports"
KEYRING="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
HERE=$(cd "$(dirname "$0")/.." && pwd)

say() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "Please run as root (sudo $0 ...)"; exit 1; }
mountpoint -q "$TARGET_DIR" || { echo "Warning: $TARGET_DIR is not a mount point; proceed? (Press Ctrl+C to abort)"; sleep 2; }

case $(uname -m) in
aarch64) ;;
*) echo "This script should run on an arm64 host (or with qemu-user-static)"; exit 1 ;;
esac

# 1. debootstrap base system
if [ ! -e "$TARGET_DIR/etc/os-release" ]; then
    say "Running debootstrap for Ubuntu $REL (arm64)..."
    debootstrap --arch=arm64 --keyring="$KEYRING" --components=main,universe \
        --include=ca-certificates,systemd,udev "$REL" "$TARGET_DIR" "$MIRROR"
fi

# Chroot plumbing
for m in proc sys dev dev/pts run; do
    mountpoint -q "$TARGET_DIR/$m" || mount --bind "/$m" "$TARGET_DIR/$m"
done
cleanup() {
    for m in run dev/pts dev sys proc; do
        umount -l "$TARGET_DIR/$m" 2>/dev/null || true
    done
}
trap cleanup EXIT

rm -f "$TARGET_DIR/etc/resolv.conf"
cp -L /etc/resolv.conf "$TARGET_DIR/etc/resolv.conf"
ch() { chroot "$TARGET_DIR" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 "$@"; }

# 2. APT Sources
say "Configuring APT sources..."
cat > "$TARGET_DIR/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: $MIRROR
Suites: $REL $REL-updates $REL-security
Components: main universe restricted multiverse
Signed-By: $KEYRING
EOF
[ -e "$TARGET_DIR/etc/apt/sources.list" ] && : > "$TARGET_DIR/etc/apt/sources.list"

# Disable snapd by default for lightweight and fast operation
mkdir -p "$TARGET_DIR/etc/apt/preferences.d"
printf 'Package: snapd\nPin: release a=*\nPin-Priority: -10\n' > "$TARGET_DIR/etc/apt/preferences.d/no-snapd"

ch apt-get update -q
ch apt-get -y -q dist-upgrade

# 3. Install GNOME Desktop and Core Packages
say "Installing minimal GNOME Wayland desktop and system utilities..."
base_pkgs="systemd-resolved network-manager openssh-server sudo bluez pipewire \
pipewire-pulse wireplumber alsa-ucm-conf alsa-utils iio-sensor-proxy dbus-user-session \
polkitd rfkill locales tzdata vim-tiny less wpasupplicant wireless-regdb \
mesa-vulkan-drivers libgl1-mesa-dri plymouth plymouth-theme-spinner fonts-noto-core \
python3 python3-gi python3-pydbus"

gnome_pkgs="gdm3 gnome-shell gnome-session gnome-control-center gnome-terminal nautilus \
gnome-text-editor gnome-keyring libpam-gnome-keyring gnome-initial-setup-"

# shellcheck disable=SC2086
ch apt-get -y -q --no-install-recommends install $base_pkgs $gnome_pkgs
ch apt-get -y -q purge snapd 2>/dev/null || true

# Mask problematic modem services
ch systemctl mask rmtfs.service tqftpserv.service 2>/dev/null || true

# 4. Install TB321FU Hardware Packages
say "Installing TB321FU kernel modules and hardware packages..."
mkdir -p "$TARGET_DIR/tmp/tb321fu_pkgs"
cp "$HERE/packages"/*.deb "$TARGET_DIR/tmp/tb321fu_pkgs/"
ch sh -c 'dpkg -i --force-overwrite /tmp/tb321fu_pkgs/*.deb || apt-get -y -q -o Dpkg::Options::="--force-overwrite" install -f'
rm -rf "$TARGET_DIR/tmp/tb321fu_pkgs"

# 4.1 Install fixed iio-sensor-proxy with libssc support
say "Installing fixed iio-sensor-proxy with FastRPC DSP support..."
if [ -f /usr/local/libexec/iio-sensor-proxy ]; then
    install -Dm755 /usr/local/libexec/iio-sensor-proxy "$TARGET_DIR/usr/local/libexec/iio-sensor-proxy"
    mkdir -p "$TARGET_DIR/etc/systemd/system/iio-sensor-proxy.service.d"
    cat > "$TARGET_DIR/etc/systemd/system/iio-sensor-proxy.service.d/tb321fu-libssc.conf" << 'CONF_EOF'
[Unit]
StartLimitIntervalSec=0

[Service]
ExecStart=
ExecStart=/usr/local/libexec/iio-sensor-proxy
RestrictAddressFamilies=AF_QIPCRTR
Restart=always
RestartSec=3
CONF_EOF
fi
if [ -d /usr/local/lib/aarch64-linux-gnu ]; then
    mkdir -p "$TARGET_DIR/usr/local/lib/aarch64-linux-gnu"
    cp -a /usr/local/lib/aarch64-linux-gnu/libssc* "$TARGET_DIR/usr/local/lib/aarch64-linux-gnu/" 2>/dev/null || true
    echo "/usr/local/lib/aarch64-linux-gnu" > "$TARGET_DIR/etc/ld.so.conf.d/local-libs.conf"
    ch ldconfig
fi

# 5. Dual-Boot & Scripts Integration
say "Installing dual-boot scripts..."
install -Dm755 "$HERE/android/back-to-android" "$TARGET_DIR/usr/local/sbin/back-to-android"
mkdir -p "$TARGET_DIR/var/lib/tb321fu"

# Auto-rotation daemon
say "Configuring auto-rotation for GNOME Wayland..."
install -Dm755 "$HERE/rootfs/tb321fu-autorotate" "$TARGET_DIR/usr/local/bin/tb321fu-autorotate"

# User systemd service for autorotate
mkdir -p "$TARGET_DIR/etc/systemd/user"
cat > "$TARGET_DIR/etc/systemd/user/tb321fu-autorotate.service" << 'SERVICE_EOF'
[Unit]
Description=TB321FU Screen Auto-Rotate Daemon (ignores external keyboard/mouse lock)
After=gnome-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/tb321fu-autorotate
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
SERVICE_EOF

# Enable autorotate user service by default
mkdir -p "$TARGET_DIR/etc/systemd/user/default.target.wants"
ln -sf /etc/systemd/user/tb321fu-autorotate.service "$TARGET_DIR/etc/systemd/user/default.target.wants/tb321fu-autorotate.service"

# System configuration
say "Configuring user, hostname, locales, and fstab..."
echo "$HOSTNAME_NEW" > "$TARGET_DIR/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\t%s\n' "$HOSTNAME_NEW" > "$TARGET_DIR/etc/hosts"
printf 'PARTLABEL=%s\t/\text4\tdefaults,noatime\t0\t1\n' "$ROOT_PARTLABEL" > "$TARGET_DIR/etc/fstab"
printf 'PARTLABEL=Y700BOOT\t/boot/efi\tvfat\tdefaults,nofail\t0\t2\n' >> "$TARGET_DIR/etc/fstab"
mkdir -p "$TARGET_DIR/boot/efi"

ch sh -c 'sed -i "s/^# *en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen && locale-gen >/dev/null'
ch sh -c 'sed -i "s/^# *ru_RU.UTF-8/ru_RU.UTF-8/" /etc/locale.gen && locale-gen >/dev/null || true'
echo "LANG=en_US.UTF-8" > "$TARGET_DIR/etc/default/locale"

# Timezone
if [ -e "$TARGET_DIR/usr/share/zoneinfo/$TIMEZONE" ]; then
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" "$TARGET_DIR/etc/localtime"
    echo "$TIMEZONE" > "$TARGET_DIR/etc/timezone"
fi

# Create default user
ch id "$USER_NAME" >/dev/null 2>&1 || ch useradd -m -s /bin/bash -G sudo,video,audio,input,render "$USER_NAME"
printf '%s:%s\n' "$USER_NAME" "$USER_PASS" | ch chpasswd
printf 'root:%s\n' "$USER_PASS" | ch chpasswd

# GDM autologin for user
mkdir -p "$TARGET_DIR/etc/gdm3"
cat > "$TARGET_DIR/etc/gdm3/custom.conf" <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=$USER_NAME
WaylandEnable=true
EOF

# NetworkManager unmanage USB gadget
mkdir -p "$TARGET_DIR/etc/NetworkManager/conf.d"
printf '[keyfile]\nunmanaged-devices=interface-name:usb0\n' > "$TARGET_DIR/etc/NetworkManager/conf.d/10-tb321fu-usb0.conf"

ch apt-get -y -q clean
ln -sf ../run/systemd/resolve/stub-resolv.conf "$TARGET_DIR/etc/resolv.conf"

say "TB321FU Ubuntu rootfs successfully created!"
say "User: $USER_NAME, Password: $USER_PASS"
say "Target directory: $TARGET_DIR"
