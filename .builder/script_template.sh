#!/bin/sh
set -e
SKIP=$(awk '/^__ARCHIVE_BELOW__/ {print NR+1; exit}' "$0")
INSTALL_ROOT="$HOME/.claudebox"
PAYLOAD="$INSTALL_ROOT/scripts"

mkdir -p "$INSTALL_ROOT"
echo "📦 Extracting ClaudeBox to $INSTALL_ROOT"
tail -n +"$SKIP" "$0" | tar -xz -C "$INSTALL_ROOT"
chmod +x "$INSTALL_ROOT/setup.sh"
echo "🚀 Launching setup..."
exec "$INSTALL_ROOT/setup.sh" "$@"
exit 1
__ARCHIVE_BELOW__
