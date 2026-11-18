#!/usr/bin/env bash
# Run after install-system.sh and a reboot, as the desktop user.
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
if (( EUID == 0 )); then echo 'Run without sudo as the desktop user.' >&2; exit 1; fi
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 26.04 ]] || { echo 'Requires Ubuntu 26.04.x.' >&2; exit 1; }
command -v sudo >/dev/null || exit 1
sudo -v
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common curl git jq wget unzip python3-yaml gnome-shell-extension-manager gnome-shell-extensions snapd
sudo add-apt-repository -y multiverse
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y steam-installer

# Explicitly requested downloads. Temporary files are removed on exit.
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fetch_deb() { curl -fL --retry 3 --connect-timeout 20 "$1" -o "$tmp/$2"; sudo apt-get install -y "$tmp/$2"; }
curl -fL --retry 3 --connect-timeout 20 'https://dl.strem.io/shell-linux/v4.4.168/stremio_4.4.168-1_amd64.deb' -o "$tmp/stremio.deb"
if sudo apt-get -s install "$tmp/stremio.deb" >/dev/null 2>&1; then
  sudo apt-get install -y "$tmp/stremio.deb"
else
  echo 'Requested Stremio deb cannot resolve dependencies; using the user-approved official-listed Flatpak.'
  sudo apt-get install -y flatpak
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --user -y flathub com.stremio.Stremio
fi
# ArtCraft Studio's official latest Linux x86_64 .deb.
art_url=$(curl -fsSL https://api.github.com/repos/storytold/artcraft/releases/latest | jq -er '[.assets[] | select(.name | test("^artcraft-[0-9].*-linux-x86_64\\.deb$")) | .browser_download_url] | if length == 1 then .[0] else error("Expected one ArtCraft amd64 deb") end')
fetch_deb "$art_url" artcraft.deb
sudo snap install spotify || { snap list spotify >/dev/null 2>&1 || exit 1; }
sudo snap install code --classic || { snap list code >/dev/null 2>&1 || exit 1; }
sudo snap install mailspring || { snap list mailspring >/dev/null 2>&1 || exit 1; }
# Remove Thunderbird only after Mailspring has been installed.
if snap list thunderbird >/dev/null 2>&1; then sudo snap remove thunderbird; fi
if dpkg-query -W -f='${db:Status-Status}' thunderbird 2>/dev/null | grep -qx installed; then sudo apt-get remove -y thunderbird; fi

# Install official uv as the current desktop user.
if ! command -v uv >/dev/null; then curl -LsSf https://astral.sh/uv/install.sh | sh; fi
printf '%s\n' 'Applications installed. Sign in to your online services yourself. Run the desktop and AI setup stages next.'
