#!/usr/bin/env bash
set -euo pipefail
ENABLE_SUDO=false
DISABLE_FIREWALL=false
SHELL_MODE=false
FORWARD=()

# ---------------------------------- flag parse -------------------------------
while (($#)); do
  case "$1" in
    --enable-sudo)   ENABLE_SUDO=true   ;;
    --disable-firewall) DISABLE_FIREWALL=true ;;
    --shell-mode)    SHELL_MODE=true    ;;
    *)               FORWARD+=("$1")    ;;
  esac
  shift
done
set -- "${FORWARD[@]}"

export DISABLE_FIREWALL

# (real firewall/sudo logic intentionally omitted – fill in later)
echo "↪  [ENTRYPOINT] enable_sudo=${ENABLE_SUDO}  disable_firewall=${DISABLE_FIREWALL} shell_mode=${SHELL_MODE}"
exec "$@"