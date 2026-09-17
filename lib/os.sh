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

# ============================================================================
# MD5 Command Detection and Helpers
# ============================================================================

# Detect and set the appropriate MD5 command based on OS
set_md5_command() {
    if command -v md5sum >/dev/null 2>&1; then
        # Linux style: md5sum outputs "hash  filename"
        MD5_CMD="md5sum"
        MD5_EXTRACT='cut -d" " -f1'
    elif command -v md5 >/dev/null 2>&1; then
        # macOS style: md5 -q outputs just the hash
        MD5_CMD="md5 -q"
        MD5_EXTRACT='cat'
    else
        error "No MD5 command found. Please install md5sum or md5."
    fi
    export MD5_CMD
    export MD5_EXTRACT
}

# Calculate MD5 hash of a file (cross-platform)
md5_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        $MD5_CMD "$file" 2>/dev/null | eval "$MD5_EXTRACT"
    else
        echo ""
    fi
}

# Calculate MD5 hash of a string (cross-platform)
md5_string() {
    local string="$1"
    echo -n "$string" | $MD5_CMD 2>/dev/null | eval "$MD5_EXTRACT"
}

# Initialize MD5 command on library load
set_md5_command

# ============================================================================
# Portable SHA256 Helpers
# ============================================================================

# Accept filenames or '-' for stdin, matching both platform checksum tools.
sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$@"
    else
        error "No SHA256 command found. Please install sha256sum or shasum."
    fi | cut -d ' ' -f1
}

sha256_string() {
    local string="$1"
    printf '%s' "$string" | sha256_file -
}

# Export functions
export -f set_md5_command md5_file md5_string
export -f sha256_file sha256_string
