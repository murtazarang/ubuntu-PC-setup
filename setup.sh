#!/usr/bin/env bash
set -Eeuo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
case "${1:-}" in
  system)
    "$here/install-system.sh"
    echo 'System stage complete. Reboot, log in, then run ./setup.sh desktop.'
    ;;
  desktop)
    "$here/install-apps.sh"
    "$here/install-local-tools.sh"
    "$here/configure-firefox.sh"
    "$here/configure-desktop.sh"
    "$here/configure-ai.sh"
    "$here/configure-kiwix.sh"
    "$here/download-wikipedia.sh"
    echo 'Setup stages finished. Read README.md for physical-PC verification and any follow-up.'
    ;;
  *) echo 'Usage: ./setup.sh system  OR  ./setup.sh desktop' >&2; exit 2;;
esac
