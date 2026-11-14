#!/usr/bin/env bash
# First post-install stage. Run as the logged-in desktop user, not as root.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run this as the Ubuntu desktop user, without sudo.' >&2; exit 1; fi
. /etc/os-release
if [[ $ID != ubuntu || $VERSION_ID != 26.04 ]]; then echo 'Requires Ubuntu 26.04.x.' >&2; exit 1; fi
if [[ $(findmnt -n -o FSTYPE /) != btrfs ]]; then echo 'Root is not Btrfs; complete the installation instructions first.' >&2; exit 1; fi
sudo -v
sudo dpkg --add-architecture i386
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y btrfs-progs timeshift
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
"$here/configure-timeshift.sh"
sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl wget jq unzip xz-utils ca-certificates pciutils parted e2fsprogs ubuntu-drivers-common mesa-vulkan-drivers mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386 vulkan-tools
graphics=$(lspci -nn | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)
if grep -qi nvidia <<<"$graphics"; then
  echo 'NVIDIA GPU detected. Discovering recommended proprietary driver.'
  sudo ubuntu-drivers devices
  recommended=$(ubuntu-drivers devices | awk '/nvidia-driver-[0-9]+/ && /recommended/ {for(i=1;i<=NF;i++) if($i ~ /^nvidia-driver-[0-9]+(-open)?$/ && !found) {gsub(/-open$/, "", $i); found=$i}} END {if(found) print found}')
  if [[ ! $recommended =~ ^nvidia-driver-[0-9]+$ ]]; then echo 'Could not determine a recommended proprietary NVIDIA driver. Use Ubuntu Additional Drivers; do not continue blindly.' >&2; exit 1; fi
  echo "Installing proprietary kernel-module package: $recommended"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$recommended" "libnvidia-gl-${recommended#nvidia-driver-}:i386"
  echo 'Reboot now, complete any Secure Boot enrollment prompt, then run the user setup.'
else
  if grep -qi intel <<<"$graphics"; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y intel-media-va-driver vainfo
  fi
  echo 'No NVIDIA GPU detected. Intel graphics uses Ubuntu kernel and Mesa; reboot if updates require it.'
fi
