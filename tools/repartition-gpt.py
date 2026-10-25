#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
import struct, zlib, uuid, os

stock_path = '/home/sotiomake/tb321fu-linux/android/gpt_stock.bin'
out_dir = '/home/sotiomake/tb321fu-linux/android'

with open(stock_path, 'rb') as f:
    gpt = bytearray(f.read())

sec_sz = 4096
# Read stock primary header at LBA 1
hdr = bytearray(gpt[sec_sz:sec_sz+92])
sig, rev, hdr_sz, crc, res, cur_lba, bkp_lba, first_lba, last_lba, disk_guid, part_lba, num_parts, part_sz, part_crc = struct.unpack('<8sIIIIQQQQ16sQIII', hdr)

print(f"Disk GUID: {uuid.UUID(bytes_le=disk_guid)}")
print(f"Current LBA: {cur_lba}, Backup LBA: {bkp_lba}")
print(f"First usable: {first_lba}, Last usable: {last_lba}")
print(f"Partitions: {num_parts}, entry size: {part_sz}")

# Partition array is at part_lba * sec_sz
part_offset = part_lba * sec_sz
part_table = bytearray(gpt[part_offset : part_offset + num_parts * part_sz])

def get_entry(idx):
    return part_table[idx * part_sz : (idx + 1) * part_sz]

def set_entry(idx, type_guid_str, part_guid_str, first, last, flags, name_str):
    tg = uuid.UUID(type_guid_str).bytes_le
    pg = uuid.UUID(part_guid_str).bytes_le
    name_bytes = name_str.encode('utf-16le').ljust(72, b'\x00')[:72]
    entry = tg + pg + struct.pack('<QQQ', first, last, flags) + name_bytes
    part_table[idx * part_sz : (idx + 1) * part_sz] = entry

# 1. Modify Partition 16 (index 15): userdata
# First LBA: 3613096
# Size: 59768832 sectors (~228 GiB)
# Last LBA: 3613096 + 59768832 - 1 = 63381927
p16_entry = get_entry(15)
p16_tg = uuid.UUID(bytes_le=bytes(p16_entry[:16]))
p16_pg = uuid.UUID(bytes_le=bytes(p16_entry[16:32]))
p16_flags = struct.unpack('<Q', p16_entry[48:56])[0]
print(f"Partition 16 (userdata) original start: 3613096")
set_entry(15, str(p16_tg), str(p16_pg), 3613096, 63381927, p16_flags, "userdata")
print(f"Partition 16 (userdata) new: 3613096 - 63381927 ({(63381927 - 3613096 + 1)*4096/(1024**3):.2f} GiB)")

# 2. Add Partition 17 (index 16): Y700BOOT (EFI System Partition)
# Size: 262144 sectors (1 GiB)
# First LBA: 63381928, Last LBA: 63644071
p17_tg = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" # EFI System Partition
p17_pg = str(uuid.uuid4())
set_entry(16, p17_tg, p17_pg, 63381928, 63644071, 0, "Y700BOOT")
print(f"Partition 17 (Y700BOOT) new: 63381928 - 63644071 ({(63644071 - 63381928 + 1)*4096/(1024**3):.2f} GiB)")

# 3. Add Partition 18 (index 17): tb321fu-root (Linux rootfs ext4)
# First LBA: 63644072, Last LBA: 123365370 (to end of usable LBA)
p18_tg = "0fc63daf-8483-4772-8e79-3d69d8477de4" # Linux filesystem data
p18_pg = str(uuid.uuid4())
set_entry(17, p18_tg, p18_pg, 63644072, 123365370, 0, "tb321fu-root")
print(f"Partition 18 (tb321fu-root) new: 63644072 - 123365370 ({(123365370 - 63644072 + 1)*4096/(1024**3):.2f} GiB)")

# Calculate CRC32 of partition array
new_part_crc = zlib.crc32(part_table)
print(f"New partition table CRC32: {new_part_crc:#010x}")

# Build New Primary Header
pri_hdr = bytearray(hdr)
struct.pack_into('<I', pri_hdr, 88, new_part_crc)
struct.pack_into('<I', pri_hdr, 16, 0) # clear CRC for calculation
pri_hdr_crc = zlib.crc32(pri_hdr)
struct.pack_into('<I', pri_hdr, 16, pri_hdr_crc)
print(f"New Primary Header CRC32: {pri_hdr_crc:#010x}")

# Build New Primary GPT image: LBA 0 (PMBR) + LBA 1 (Header) + LBA 2 (Partitions)
# 3 sectors = 12288 bytes
pri_img = bytearray(gpt[:sec_sz]) # LBA 0 (Protective MBR)
pri_img += pri_hdr + b'\x00' * (sec_sz - len(pri_hdr)) # LBA 1 (4096 bytes)
pri_img += part_table # LBA 2 (4096 bytes)

with open(f"{out_dir}/gpt_new_primary.bin", "wb") as f:
    f.write(pri_img)
print(f"Saved {out_dir}/gpt_new_primary.bin (size {len(pri_img)} bytes, 3 sectors)")

# Build New Backup GPT image: LBA 123365374 (Partitions) + LBA 123365375 (Backup Header)
# In backup header: cur_lba = bkp_lba, bkp_lba = 1, part_lba = 123365374 (bkp_lba - 1)
bkp_hdr = bytearray(pri_hdr)
struct.pack_into('<QQ', bkp_hdr, 24, bkp_lba, 1) # cur_lba, bkp_lba
struct.pack_into('<Q', bkp_hdr, 72, bkp_lba - 1) # part_lba
struct.pack_into('<I', bkp_hdr, 16, 0) # clear CRC
bkp_hdr_crc = zlib.crc32(bkp_hdr)
struct.pack_into('<I', bkp_hdr, 16, bkp_hdr_crc)
print(f"New Backup Header CRC32: {bkp_hdr_crc:#010x}")

bkp_img = bytearray(part_table) # LBA 123365374
bkp_img += bkp_hdr + b'\x00' * (sec_sz - len(bkp_hdr)) # LBA 123365375

with open(f"{out_dir}/gpt_new_backup.bin", "wb") as f:
    f.write(bkp_img)
print(f"Saved {out_dir}/gpt_new_backup.bin (size {len(bkp_img)} bytes, 2 sectors)")
