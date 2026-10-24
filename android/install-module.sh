#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# install-module.sh -- PC/Host side of the Android -> Linux switch for TB321FU.
# Supports KernelSU, KernelSU Next, APatch, and Magisk.
set -eo pipefail
here=$(cd "$(dirname "$0")" && pwd)

su_() { printf '%s\n' "$*" | adb shell su -c sh 2>/dev/null | tr -d '\r'; }
slot_a() { [ "$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')" = _a ] || { echo "Android is not running from slot _a"; exit 1; }; }
hash_of() { su_ "sha256sum /dev/block/by-name/$1" | cut -c1-64; }

usage() {
    cat <<EOF
Usage:
  $0 prepare-boot-b   Copy the running Android boot image (boot_a) into boot_b once (the way back)
  $0 install          Build the switch-to-linux module with android.sha256 and install it (KernelSU/Magisk)
  $0 stage IMG        Push a Linux boot image as the fallback /data/adb/tb321fu/linux.img (+ .sha256)
  $0 status           Check boot_a/boot_b hashes, staged image, and module status
EOF
    exit 1
}

cmd=${1:-}
shift || true

case "$cmd" in
prepare-boot-b)
    slot_a
    a=$(hash_of boot_a); b=$(hash_of boot_b)
    echo "boot_a: $a"
    echo "boot_b: $b"
    if [ "$a" = "$b" ] && [ ${#a} -eq 64 ]; then
        echo "boot_b already holds the running Android boot image ($a)"
        echo "$b" > "$here/switch-to-linux/android.sha256"
        exit 0
    fi
    read -r -p "Copy boot_a (the Android kernel running now) over boot_b? [yes/N] " ok
    [ "$ok" = yes ] || exit 1
    su_ "dd if=/dev/block/by-name/boot_a of=/dev/block/by-name/boot_b bs=1M conv=fsync 2>/dev/null; sync"
    hb=$(hash_of boot_b)
    if [ "$hb" = "$a" ]; then
        echo "boot_b successfully updated: $hb"
        echo "$hb" > "$here/switch-to-linux/android.sha256"
    else
        echo "Error: boot_b does not match after the copy!"
        exit 1
    fi
    ;;
install)
    slot_a
    a=$(hash_of boot_a); b=$(hash_of boot_b)
    [ ${#b} -eq 64 ] && [ "$a" = "$b" ] || { echo "boot_a ($a) != boot_b ($b): run prepare-boot-b first"; exit 1; }
    echo "Creating module zip with Android hash $b..."
    echo "$b" > "$here/switch-to-linux/android.sha256"
    tmp=$(mktemp -d)
    cp -r "$here/switch-to-linux" "$tmp/m"
    sed -i 's/\r$//' "$tmp"/m/*
    (cd "$tmp/m" && python3 -c "
import zipfile, os
with zipfile.ZipFile('../switch-to-linux.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    for f in sorted(os.listdir('.')):
        i = zipfile.ZipInfo(f); i.external_attr = (0o755 if f.endswith('.sh') else 0o644) << 16
        z.writestr(i, open(f, 'rb').read())")
    MSYS_NO_PATHCONV=1 adb push "$tmp/switch-to-linux.zip" /data/local/tmp/ > /dev/null
    
    echo "Installing module on device..."
    su_ "
        if command -v ksud >/dev/null 2>&1; then
            echo 'Detected KernelSU: installing via ksud...'
            ksud module install /data/local/tmp/switch-to-linux.zip
        elif command -v magisk >/dev/null 2>&1; then
            echo 'Detected Magisk: installing via magisk...'
            magisk --install-module /data/local/tmp/switch-to-linux.zip
        else
            echo 'Manual install needed: module pushed to /sdcard/switch-to-linux.zip'
            cp /data/local/tmp/switch-to-linux.zip /sdcard/
        fi
    "
    rm -rf "$tmp"
    echo "android.sha256 = $b (keep it: back-to-android uses it)"
    ;;
stage)
    IMG=${1:?usage: $0 stage IMG}
    [ -f "$IMG" ] || { echo "File $IMG not found!"; exit 1; }
    want=$(sha256sum "$IMG" | cut -c1-64)
    MSYS_NO_PATHCONV=1 adb push "$IMG" /data/local/tmp/linux.img > /dev/null
    su_ "mkdir -p /data/adb/tb321fu && mv /data/local/tmp/linux.img /data/adb/tb321fu/linux.img && echo $want > /data/adb/tb321fu/linux.img.sha256 && chmod 600 /data/adb/tb321fu/linux.img*"
    got=$(su_ "sha256sum /data/adb/tb321fu/linux.img" | cut -c1-64)
    [ "$got" = "$want" ] && echo "Staged ${want:0:16} successfully" || { echo "Staged copy mismatch $got"; exit 1; }
    ;;
status)
    echo "slot:   $(adb shell getprop ro.boot.slot_suffix | tr -d '\r')"
    echo "boot_a: $(hash_of boot_a)"
    echo "boot_b: $(hash_of boot_b)"
    echo "staged: $(su_ "cat /data/adb/tb321fu/linux.img.sha256 2>/dev/null" | cut -c1-16)"
    su_ "
        if command -v ksud >/dev/null 2>&1; then
            ksud module list | grep -A3 -i tb321fu-switch || echo 'KernelSU module not installed'
        elif command -v magisk >/dev/null 2>&1; then
            magisk --list-modules | grep -i tb321fu || echo 'Magisk module installed or check /data/adb/modules'
        fi
    "
    ;;
*)
    usage
    ;;
esac
