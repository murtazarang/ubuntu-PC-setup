#!/usr/bin/env bash
# Formats one explicitly selected unmounted ~1 TB rotational disk. ALL DATA IS LOST.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user, without sudo.' >&2; exit 1; fi
[[ $# == 2 && $2 =~ ^(ext4|btrfs)$ ]] || { echo "Usage: $0 /dev/sdX ext4|btrfs" >&2; exit 2; }
dev=$(readlink -f -- "$1"); fs=$2
[[ -b $dev && $(lsblk -dnro TYPE "$dev") == disk && $(lsblk -dnro ROTA "$dev") == 1 ]] || { echo 'Select a rotational whole disk, not a partition or NVMe.' >&2; exit 1; }
size=$(lsblk -dnbo SIZE "$dev")
(( size >= 900000000000 && size <= 1100000000000 )) || { echo 'Refusing: disk is not approximately 1 TB.' >&2; exit 1; }
mounts=$(lsblk -nrpo MOUNTPOINTS "$dev")
if grep -q '[^[:space:]]' <<<"$mounts"; then echo 'Disk or a partition is mounted; refusing.' >&2; exit 1; fi
swaps=$(swapon --noheadings --show=NAME)
if grep -Fq "$dev" <<<"$swaps"; then echo 'Disk has active swap; refusing.' >&2; exit 1; fi
if findmnt --fstab /mnt/storage >/dev/null || mountpoint -q /mnt/storage; then echo '/mnt/storage already configured or mounted; refusing.' >&2; exit 1; fi
lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS "$dev"
echo "THIS ERASES ALL DATA on $dev and formats it as $fs."
read -r -p "Type ERASE $dev to continue: " answer
[[ $answer == "ERASE $dev" ]] || { echo 'Cancelled.'; exit 1; }
sudo -v
# Recheck just before writing.
mounts=$(lsblk -nrpo MOUNTPOINTS "$dev")
if grep -q '[^[:space:]]' <<<"$mounts"; then echo 'Disk became mounted; refusing.' >&2; exit 1; fi
sudo wipefs -a "$dev"
sudo parted -s "$dev" mklabel gpt mkpart primary 1MiB 100%
sudo partprobe "$dev"; sudo udevadm settle
mapfile -t parts < <(lsblk -lnpo NAME,TYPE "$dev" | awk '$2=="part" {print $1}')
[[ ${#parts[@]} == 1 && -b ${parts[0]} ]] || { echo 'Expected exactly one new partition; stop.' >&2; exit 1; }
part=${parts[0]}
if [[ $fs == ext4 ]]; then sudo mkfs.ext4 -L storage "$part"; else sudo mkfs.btrfs -L storage "$part"; fi
uuid=$(sudo blkid -s UUID -o value "$part")
[[ -n $uuid ]] || { echo 'Could not get filesystem UUID.' >&2; exit 1; }
sudo mkdir -p /mnt/storage
sudo cp -a /etc/fstab "/etc/fstab.backup.$(date +%s)"
pass=2; [[ $fs == btrfs ]] && pass=0
printf 'UUID=%s /mnt/storage %s defaults,nofail 0 %s\n' "$uuid" "$fs" "$pass" | sudo tee -a /etc/fstab >/dev/null
sudo systemctl daemon-reload
sudo mount /mnt/storage
sudo chown "$USER:$(id -gn)" /mnt/storage
echo "Mounted $dev at /mnt/storage."
