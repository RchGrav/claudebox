#!/bin/bash
#
# Single-file "claudebox" installer & updater (silent on success)
# macOS (bash 3.2+) & Linux compatible
# Release SHA256: __ARCHIVE_SHA256__
#

# Fail fast
set -e

# 1) Release mode install/update
INSTALL_DIR="$HOME/.claudebox"
SOURCE_DIR="$INSTALL_DIR/source"
ARCHIVE_SHA256="__ARCHIVE_SHA256__"
ARCHIVE_PATH="$INSTALL_DIR/archive.tar.gz"

mkdir -p "$SOURCE_DIR"

# 3) Choose checksum tool
if   command -v sha256sum >/dev/null 2>&1; then
  CHECKSUM_COMMAND=(sha256sum)
elif command -v shasum   >/dev/null 2>&1; then
  CHECKSUM_COMMAND=(shasum -a 256)
else
  echo "⛔ sha256sum or shasum required." >&2
  exit 1
fi

# 4) Compare and extract if needed
if [ -f "$ARCHIVE_PATH" ] \
  && [ "$("${CHECKSUM_COMMAND[@]}" "$ARCHIVE_PATH" | awk '{print $1}')" = "$ARCHIVE_SHA256" ]; then
  :  # up-to-date, silent
else
  SKIP=$(awk '/^__ARCHIVE_BELOW__/ {print NR+1; exit}' "$0")
  tail -n +"$SKIP" "$0" > "$ARCHIVE_PATH"
  tar -xz -f "$ARCHIVE_PATH" -C "$SOURCE_DIR" --strip-components=1
fi

# 5) Launch main.sh from source directory
# The archive marker below is data, not a command after exec.
# shellcheck disable=SC2093
CLAUDEBOX_INSTALLER_RUN="true" exec bash "$SOURCE_DIR/main.sh" "$@"

# shellcheck disable=SC2317
__ARCHIVE_BELOW__
