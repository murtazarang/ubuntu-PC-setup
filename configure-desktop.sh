#!/usr/bin/env bash
# Run within the logged-in GNOME desktop session.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user.' >&2; exit 1; fi
[[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || { echo 'Run inside your GNOME desktop session.' >&2; exit 1; }
for cmd in gnome-shell gnome-extensions gsettings jq curl unzip glib-compile-schemas; do command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }; done
shell_version=$(gnome-shell --version | awk '{print $3}' | cut -d. -f1)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
install_extension() {
  local id=$1 info uuid version
  info=$(curl -fsSL --retry 3 "https://extensions.gnome.org/extension-info/?pk=$id")
  uuid=$(jq -er .uuid <<<"$info")
  version=$(jq -er --arg v "$shell_version" '.shell_version_map[$v].pk // error("extension has no version for GNOME Shell")' <<<"$info")
  curl -fL --retry 3 "https://extensions.gnome.org/download-extension/$uuid.shell-extension.zip?version_tag=$version" -o "$tmp/$id.zip"
  gnome-extensions install --force "$tmp/$id.zip"
  gnome-extensions enable "$uuid" || echo "Enable $uuid after logging out and back in."
}
install_extension 517  # Caffeine
install_extension 4839 # Clipboard History
install_extension 9817 # Lightning GNOME Launcher
schema="$HOME/.local/share/gnome-shell/extensions/lightning-gnome-launcher@avimanyu/schemas"
[[ -f $schema/org.gnome.shell.extensions.lightning-launcher.gschema.xml ]] || { echo 'Launcher schema not found.' >&2; exit 1; }
glib-compile-schemas "$schema"
gsettings --schemadir "$schema" set org.gnome.shell.extensions.lightning-launcher shortcut-key "['<Super>F2']"
echo 'Log out and back in if the extensions do not activate; check Super+F2.'
