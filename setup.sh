#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="$HOME/.claudebox"
TARGET_DIR="$INSTALL_ROOT/scripts"
LINK_PATH="$HOME/.local/bin/claudebox"

echo "📂 Installing ClaudeBox to $TARGET_DIR"
rm -rf "$TARGET_DIR"
mkdir -p "$INSTALL_ROOT"
cp -a scripts "$INSTALL_ROOT/"
chmod +x "$INSTALL_ROOT/scripts/bin/claudebox"

mkdir -p "$(dirname "$LINK_PATH")"
ln -sf "$INSTALL_ROOT/scripts/bin/claudebox" "$LINK_PATH"
echo "🔗 Symlink: $LINK_PATH → $INSTALL_ROOT/scripts/bin/claudebox"

"$LINK_PATH" --version 2>/dev/null || echo "✅ ClaudeBox installed successfully!"
echo ""
echo "To get started, run: claudebox"
exit 0