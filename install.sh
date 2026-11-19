#!/bin/bash
set -euo pipefail

DISK="${1:?用法: sudo ./install.sh /dev/sdX [镜像文件]}"
IMG="${2:-dfl.img.zst}"

[[ $EUID -eq 0 ]] || { echo "需要 root"; exit 1; }
[[ -b $DISK ]]    || { echo "$DISK 不是块设备"; exit 1; }
[[ -f $IMG ]]     || { echo "找不到 $IMG"; exit 1; }

if [[ $DISK == *nvme* || $DISK == *mmcblk* ]]; then SUF=p; else SUF=""; fi
P1="${DISK}${SUF}1"
P2="${DISK}${SUF}2"

echo "即将清空 $DISK 的全部数据，10 秒后开始，Ctrl-C 取消"
sleep 10

wipefs -a "$DISK"
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:EFI      "$DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:dfl-root "$DISK"
partprobe "$DISK" || true
udevadm settle; sleep 2

mkfs.vfat -F32 -n EFI "$P1"
zstd -dc "$IMG" | dd of="$P2" bs=8M status=progress conv=fsync

mkdir -p /mnt/dfl
mount "$P2" /mnt/dfl
resize2fs "$P2"

mkdir -p /mnt/dfl/boot/efi
mount "$P1" /mnt/dfl/boot/efi
grep -q LABEL=EFI /mnt/dfl/etc/fstab || \
  echo "LABEL=EFI /boot/efi vfat umask=0077 0 1" >> /mnt/dfl/etc/fstab

for d in dev proc sys; do mount --bind /$d /mnt/dfl/$d; done

chroot /mnt/dfl bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends grub-efi-amd64 grub-efi-amd64-signed
  grub-install --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=dongfanglong --removable
  grub-mkconfig -o /boot/grub/grub.cfg
'

for d in sys proc dev; do umount /mnt/dfl/$d || true; done
umount /mnt/dfl/boot/efi
umount /mnt/dfl
sync
echo "完成。重启并从 $DISK 引导，root 密码 dongfanglong"
