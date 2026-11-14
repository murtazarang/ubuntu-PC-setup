#!/usr/bin/env bash
# After the GUI installer finishes, choose Continue Testing, not Restart.
# Calls the author's existing --only-subvols implementation after preflight.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run without sudo from the live desktop.' >&2; exit 1; fi
[[ -d /sys/firmware/efi ]] || { echo 'Boot the live USB in UEFI mode.' >&2; exit 1; }
for d in /target /target/boot /target/boot/efi /target/cdrom; do mountpoint -q "$d" || { echo "$d is not a mount point; do not run the conversion. Check the installer state." >&2; exit 1; }; done
[[ ! -e /mnt/root ]] || { echo '/mnt/root already exists; inspect before continuing.' >&2; exit 1; }
root=$(findmnt -n -o SOURCE --target /target); boot=$(findmnt -n -o SOURCE --target /target/boot); efi=$(findmnt -n -o SOURCE --target /target/boot/efi)
root=${root%%\[*}; boot=${boot%%\[*}; efi=${efi%%\[*}
for dev in "$root" "$boot" "$efi"; do [[ -b $dev && $(lsblk -dnro TYPE "$dev") == part ]] || { echo "Invalid device $dev" >&2; exit 1; }; done
[[ $(lsblk -dnro FSTYPE "$root") == btrfs && $(lsblk -dnro FSTYPE "$boot") == ext4 && $(lsblk -dnro FSTYPE "$efi") == vfat ]] || { echo 'Expected Btrfs root, ext4 /boot, FAT32 EFI.' >&2; exit 1; }
parent=$(lsblk -dnro PKNAME "$root")
[[ -n $parent && $(lsblk -dnro PKNAME "$boot") == "$parent" && $(lsblk -dnro PKNAME "$efi") == "$parent" && $parent == nvme*n* ]] || { echo 'Root, boot and EFI must be partitions of the same NVMe.' >&2; exit 1; }
[[ $(findmnt -n -o FSROOT /target) == / ]] || { echo 'Root already uses a subvolume; refusing.' >&2; exit 1; }
if ! grep -qx 'ID=ubuntu' /target/etc/os-release || ! grep -qx 'VERSION_ID="26.04"' /target/etc/os-release; then echo 'Target is not Ubuntu 26.04.' >&2; exit 1; fi
if sudo btrfs subvolume show /target/@ >/dev/null 2>&1; then echo 'An @ subvolume already exists; refusing conversion.' >&2; exit 1; fi
grep -Eq '^.* / btrfs defaults 0 1$' /target/etc/fstab || { echo 'The installed fstab differs from the conversion script expected format; stop and inspect it.' >&2; exit 1; }
if grep -Eq '^[^#]*swapfile|^[^#]*/swap\.img' /target/etc/fstab; then echo 'Swap file is configured inside the root filesystem. Use a separate swap partition or resolve this before conversion and Timeshift.' >&2; exit 1; fi
lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS "/dev/$parent"
echo "This modifies the newly installed root $root and boot $boot / EFI $efi; it does not encrypt."
read -r -p "Type CONVERT $root to continue: " answer
[[ $answer == "CONVERT $root" ]] || { echo 'Cancelled.'; exit 1; }
tmp=$(mktemp); trap 'rm -f -- "$tmp"' EXIT
curl -fsSL --retry 3 'https://raw.githubusercontent.com/murtazarang/btrfs-encrypt-root/8e440981a50022423467164ebd45e0b35bf91a3d/btrfs-encrypt-root.sh' -o "$tmp"
sudo sh "$tmp" --only-subvols "${root#/dev/}" "${boot#/dev/}" "${efi#/dev/}"
echo 'Conversion finished. Reboot; verify @ before running setup.sh system.'
