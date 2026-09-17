#!/bin/sh
set -e
SKIP=$(awk '/^__ARCHIVE_BELOW__/ {print NR+1; exit}' "$0")
INSTALL_ROOT="$HOME/.claudebox"

mkdir -p "$INSTALL_ROOT"
echo "📦 Extracting ClaudeBox to $INSTALL_ROOT"
tail -n +"$SKIP" "$0" | tar -xz -C "$INSTALL_ROOT"
chmod +x "$INSTALL_ROOT/setup.sh"
echo "🚀 Launching setup..."
# The archive marker below is data, not a command after exec.
# shellcheck disable=SC2093
exec "$INSTALL_ROOT/setup.sh" "$@"
# shellcheck disable=SC2317
__ARCHIVE_BELOW__
