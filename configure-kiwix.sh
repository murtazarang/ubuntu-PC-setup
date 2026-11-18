#!/usr/bin/env bash
# Compatibility entry point; no OMP integration remains.
set -Eeuo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "$here/configure-openwebui.sh"
