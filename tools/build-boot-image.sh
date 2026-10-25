#!/usr/bin/env bash
# ==============================================================================
# Build Y700BOOT FAT32 partition image (1 GiB, 4096-byte sector alignment)
# Used for flashing onto internal partition /dev/block/sda17
# ==============================================================================
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
OUT_IMG="${1:-$HERE/boot/y700boot.img}"
SIZE_MB="${2:-1024}"

log() { echo -e "\033[1;32m[+] $*\033[0m"; }
err() { echo -e "\033[1;31m[-] ERROR: $*\033[0m" >&2; exit 1; }

for cmd in truncate mkfs.vfat mcopy mmd; do
    command -v "$cmd" >/dev/null 2>&1 || err "Missing required command: $cmd (install via: sudo apt install dosfstools mtools)"
done

log "Creating $SIZE_MB MiB raw image at $OUT_IMG..."
mkdir -p "$(dirname "$OUT_IMG")"
truncate -s "${SIZE_MB}M" "$OUT_IMG"

log "Formatting FAT32 with 4096-byte sector size (aligned for UFS partition sda17)..."
mkfs.vfat -F 32 -S 4096 -n "Y700BOOT" "$OUT_IMG"

log "Populating boot files into image using mtools..."
# 1. Directories
mmd -i "$OUT_IMG" "::EFI" "::EFI/BOOT" "::dtb" "::boot" "::boot/grub" 2>/dev/null || true

# 2. Kernel & DTB
mcopy -i "$OUT_IMG" "$HERE/boot/Image" "::Image"
mcopy -i "$OUT_IMG" "$HERE/boot/dtb/platform.dtb" "::dtb/platform.dtb"
mcopy -i "$OUT_IMG" "$HERE/boot/dtb/sm8650-lenovo-tb321fu.dtb" "::dtb/sm8650-lenovo-tb321fu.dtb"

# 3. EFI Bootloaders (QCOMRAMP is direct loader reading linux.cfg)
mcopy -i "$OUT_IMG" "$HERE/boot/EFI/BOOT/QCOMRAMP.EFI" "::EFI/BOOT/BOOTAA64.EFI"
mcopy -i "$OUT_IMG" "$HERE/boot/EFI/BOOT/QCOMRAMP.EFI" "::EFI/BOOT/QCOMRAMP.EFI"

# 4. Boot configs in all standard search paths
mcopy -i "$OUT_IMG" "$HERE/boot/EFI/BOOT/linux.cfg" "::EFI/BOOT/linux.cfg"
mcopy -i "$OUT_IMG" "$HERE/boot/EFI/BOOT/linux.cfg" "::EFI/BOOT/grub.cfg"
mcopy -i "$OUT_IMG" "$HERE/boot/EFI/BOOT/linux.cfg" "::linux.cfg"
mcopy -i "$OUT_IMG" "$HERE/boot/EFI/BOOT/linux.cfg" "::grub.cfg"
mcopy -i "$OUT_IMG" "$HERE/boot/EFI/BOOT/linux.cfg" "::boot/grub/grub.cfg"

# Copy initramfs if present
if [ -f "$HERE/boot/initramfs.cpio.gz" ]; then
    mcopy -i "$OUT_IMG" "$HERE/boot/initramfs.cpio.gz" "::initramfs.cpio.gz"
fi

log "Successfully built: $OUT_IMG ($(ls -lh "$OUT_IMG" | awk '{print $5}'))"
log "Ready to flash to /dev/block/sda17 via ADB!"
