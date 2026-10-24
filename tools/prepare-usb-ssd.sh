#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# prepare-usb-ssd.sh: Format USB SSD and optionally build Ubuntu GNOME for TB321FU Linux Dual-Boot
set -eo pipefail

DEV=${1:-}
OPT=${2:-}

if [ -z "$DEV" ] || [ ! -b "$DEV" ]; then
    echo "Usage: sudo $0 /dev/sdX [--build-rootfs]"
    echo ""
    echo "Options:"
    echo "  --build-rootfs    Automatically build clean Ubuntu GNOME rootfs onto the SSD"
    echo ""
    echo "WARNING: All data on $DEV will be erased!"
    echo "Current block devices:"
    lsblk -d -o NAME,SIZE,MODEL,TRAN
    exit 1
fi

ASSUME_YES=${ASSUME_YES:-0}
for arg in "$@"; do
    if [ "$arg" = "-y" ] || [ "$arg" = "--yes" ]; then
        ASSUME_YES=1
    fi
done

echo "=========================================="
echo "Preparing USB SSD for Lenovo Legion Y700 (TB321FU)"
echo "Target device: $DEV"
[ "$OPT" = "--build-rootfs" ] && echo "Mode: Partitioning + Full Ubuntu GNOME installation"
echo "=========================================="
if [ "$ASSUME_YES" != "1" ]; then
    read -p "Are you SURE you want to erase $DEV? (yes/NO): " confirm
    [ "$confirm" = "yes" ] || { echo "Aborted."; exit 1; }
fi

echo "[1/4] Unmounting and creating GPT partitions on $DEV..."
for p in $(lsblk -ln -o NAME "$DEV"); do
    umount -l "/dev/$p" 2>/dev/null || true
done
udevadm settle
sgdisk --zap-all "$DEV"
dd if=/dev/zero of="$DEV" bs=1M count=4 status=none conv=fsync || true
sgdisk -n 1:2048:+1G -t 1:0700 -c 1:"Y700BOOT" "$DEV"
sgdisk -n 2:0:0      -t 2:8300 -c 2:"tb321fu-root" "$DEV"
partprobe "$DEV" || true
udevadm settle
sleep 2

# Identify partition device names
if [ -b "${DEV}1" ]; then
    P1="${DEV}1"; P2="${DEV}2"
elif [ -b "${DEV}p1" ]; then
    P1="${DEV}p1"; P2="${DEV}p2"
else
    echo "Error locating partition devices for $DEV"; exit 1
fi

echo "[2/4] Formatting partitions..."
mkfs.vfat -F 32 -n "Y700BOOT" "$P1"
mkfs.ext4 -F -L "tb321fu-root" "$P2"

echo "[3/4] Installing boot files to Partition 1 (FAT32)..."
MOUNT_BOOT=$(mktemp -d)
mount "$P1" "$MOUNT_BOOT"

HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$MOUNT_BOOT/EFI/BOOT" "$MOUNT_BOOT/dtb"

cp "$HERE/boot/EFI/BOOT/BOOTAA64.EFI" "$MOUNT_BOOT/EFI/BOOT/"
cp "$HERE/boot/EFI/BOOT/QCOMRAMP.EFI" "$MOUNT_BOOT/EFI/BOOT/"
cp "$HERE/boot/EFI/BOOT/grub.cfg"     "$MOUNT_BOOT/EFI/BOOT/"
cp "$HERE/boot/EFI/BOOT/linux.cfg"    "$MOUNT_BOOT/EFI/BOOT/"
cp "$HERE/boot/Image"                 "$MOUNT_BOOT/Image"
cp "$HERE/boot/dtb/platform.dtb"      "$MOUNT_BOOT/dtb/"
cp "$HERE/boot/dtb/sm8650-lenovo-tb321fu.dtb" "$MOUNT_BOOT/dtb/"

sync
umount "$MOUNT_BOOT"
rm -rf "$MOUNT_BOOT"
echo "Boot partition configured successfully."

if [ "$OPT" = "--build-rootfs" ]; then
    echo "[4/4] Building clean Ubuntu GNOME rootfs on Partition 2..."
    MOUNT_ROOT=$(mktemp -d)
    mount "$P2" "$MOUNT_ROOT"
    
    REL=${UBUNTU_RELEASE:-resolute}
    "$HERE/rootfs/build-rootfs.sh" "$MOUNT_ROOT" "$REL"
    
    sync
    umount "$MOUNT_ROOT"
    rm -rf "$MOUNT_ROOT"
    echo ""
    echo "=========================================="
    echo "COMPLETE! The USB SSD is 100% ready to boot."
    echo "Plug it into your TB321FU and power on."
    echo "=========================================="
else
    echo "[4/4] Partition 2 (ext4, labeled tb321fu-root) is formatted and ready."
    echo "Run with '--build-rootfs' to automatically build Ubuntu, or mount $P2 and extract rootfs."
fi
