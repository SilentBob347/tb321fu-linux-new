#!/system/bin/sh
# SPDX-License-Identifier: MIT
# Switch to Linux: KernelSU Action button for Lenovo Legion Y700 (TB321FU)
MOD=${0%/*}
D=/data/adb/tb321fu
img=$D/linux.img
a=/dev/block/by-name/boot_a
b=/dev/block/by-name/boot_b
fail() { echo "! $*"; echo "! stopped, still in Android"; exit 1; }
h() { sha256sum "$1" | cut -c1-64; }

android=$(cut -c1-64 "$MOD/android.sha256" 2>/dev/null)
[ ${#android} -eq 64 ] || fail "module has no android.sha256"
M=$D/root
cleanup() { umount "$M" 2>/dev/null; }
trap cleanup EXIT
img= want= src=

roots() { { ls /dev/block/by-name/ 2>/dev/null
	for u in /sys/class/block/*/uevent; do sed -n 's/^PARTNAME=//p' "$u" 2>/dev/null; done
	} | grep -E '^(tb321fu-root|tb321fu-root-usb|tb321fu-.+)$' | LC_ALL=C sort -u; }
partdev() { [ -b "/dev/block/by-name/$1" ] && { echo "/dev/block/by-name/$1"; return 0; }
	for u in /sys/class/block/*/uevent; do
		grep -qx "PARTNAME=$1" "$u" 2>/dev/null || continue
		d=/dev/block/$(sed -n 's/^DEVNAME=//p' "$u")
		[ -b "$d" ] && { echo "$d"; return 0; }
	done; return 1; }
state=$(roots | head -n1)

if [ -n "$state" ] && root=$(partdev "$state"); then
	mkdir -p "$M" && mount -t ext4 -o ro,noload "$root" "$M" 2>/dev/null &&
		[ -f "$M/var/lib/tb321fu/linux-current.img" ] && {
		img=$M/var/lib/tb321fu/linux-current.img
		want=$(cut -c1-64 "$img.sha256" 2>/dev/null)
		src="last running Linux (root partition $state)"
	}
fi

if [ ${#want} -ne 64 ]; then
	cleanup
	img=$D/linux.img
	want=$(cut -c1-64 "$img.sha256" 2>/dev/null)
	src="staged $img"
fi
[ ${#want} -eq 64 ] && [ -f "$img" ] || fail "no Linux image (none saved by back-to-android, none staged)"
echo "- image: $src"
[ "$(getprop ro.boot.slot_suffix)" = _a ] || fail "running slot is not _a"
[ -b "$a" ] && [ -b "$b" ] || fail "no boot_a/boot_b"
size=$(blockdev --getsize64 "$a")
[ "$(stat -c %s "$img")" = "$size" ] || fail "image is not $size bytes (boot_a size)"

echo "- checking the image"
if [ "$(h "$img")" != "$want" ]; then
	[ "$img" = "$D/linux.img" ] && fail "image hash mismatch"
	echo "- $src does not match its hash; using the staged image"
	cleanup; img=$D/linux.img; want=$(cut -c1-64 "$img.sha256" 2>/dev/null)
	[ ${#want} -eq 64 ] && [ -f "$img" ] || fail "no staged image either"
	[ "$(stat -c %s "$img")" = "$size" ] || fail "staged image is not $size bytes"
	[ "$(h "$img")" = "$want" ] || fail "staged image hash mismatch"
fi
echo "- checking boot_b (the way back)"
[ "$(h "$b")" = "$android" ] || fail "boot_b is not the Android image -- there would be no way back"
[ "$(h "$a")" = "$android" ] || echo "- note: boot_a was not the stock Android image"

echo "- writing boot_a"
dd if="$img" of="$a" bs=1M conv=fsync 2>/dev/null
sync
cleanup
echo 3 > /proc/sys/vm/drop_caches
if [ "$(h "$a")" != "$want" ]; then
	echo "! boot_a mismatch after the write; restoring Android from boot_b"
	dd if="$b" of="$a" bs=1M conv=fsync 2>/dev/null; sync
	echo 3 > /proc/sys/vm/drop_caches
	[ "$(h "$a")" = "$android" ] && fail "boot_a is Android again" ||
		fail "boot_a is NEITHER image -- do not reboot; rerun or use EDL"
fi
echo "- boot_a = Linux $(echo $want | cut -c1-16)"
echo "- rebooting into Linux in 3 s (back: volume up+down held 10 s)"
sleep 3
reboot
