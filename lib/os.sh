#!/usr/bin/env bash
# Detect host OS and sane defaults needed by other modules.

# Cross-platform host detection (Linux vs. macOS)
OS_TYPE="$(uname -s)"
case "$OS_TYPE" in
  Darwin*) HOST_OS="macOS" ;;
  Linux*)  HOST_OS="linux" ;;
  *) echo "Unsupported operating system: $OS_TYPE" >&2; exit 1 ;;
esac

export HOST_OS

# Detect case‑insensitive default macOS filesystems (HFS+/APFS)
# Exit code 0  → case‑sensitive, 1 → case‑insensitive
is_case_sensitive_fs() {
  local t1 t2
  t1="$(mktemp "/tmp/.fs_case_test.XXXXXXXX")"
  # More portable uppercase conversion
  t2="$(echo "$t1" | tr '[:lower:]' '[:upper:]')"
  touch "$t1"
  [[ -e "$t2" && "$t1" != "$t2" ]] && { rm -f "$t1"; return 1; }
  rm -f "$t1"
  return 0
}

# Normalise docker‑build contexts on case‑insensitive hosts to avoid collisions
if [[ "$HOST_OS" == "macOS" ]] && ! is_case_sensitive_fs; then
  export COMPOSE_DOCKER_CLI_BUILD=1   # new BuildKit path‑normaliser
  export DOCKER_BUILDKIT=1
fi