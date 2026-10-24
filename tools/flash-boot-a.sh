#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# flash-boot-a.sh: Safe flash of Linux bootloader to boot_a via fastboot
set -eo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
IMG="$HERE/boot/boot.img"

[ -f "$IMG" ] || { echo "Image $IMG not found!"; exit 1; }

echo "Checking fastboot device..."
fastboot wait-for-device

echo "Current active slot:"
fastboot getvar current-slot 2>&1 | grep "current-slot" || true

echo "Flashing Linux bootloader to boot_a..."
fastboot flash boot_a "$IMG"

echo "Done! The tablet will boot Linux when powered on with USB SSD attached."
echo "If USB SSD is not attached or fails, you can restore Android at any time."
