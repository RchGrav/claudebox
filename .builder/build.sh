#!/bin/bash
# Build the ClaudeBox self-extracting installer script
# Packages entire repo for extraction to ~/.claudebox/

set -euo pipefail

# Get version from main.sh
VERSION=$(grep -m1 'readonly CLAUDEBOX_VERSION=' main.sh | cut -d'"' -f2)
if [[ -z "$VERSION" ]]; then
  echo "❌ Could not extract version from main.sh" >&2
  exit 1
fi

echo "🔨 Building ClaudeBox v$VERSION"

# Clean dist directory
echo "🧹 Cleaning dist directory..."
rm -rf dist
mkdir -p dist

TEMPLATE=".builder/script_template_root.sh"
OUTPUT="dist/claudebox.run"
ARCHIVE="dist/claudebox-${VERSION}.tar.gz"

# Create archive in temp location to avoid "file changed as we read it" error
TEMP_ARCHIVE="/tmp/claudebox_archive_$$.tar.gz"

# Create archive of entire repo (excluding hidden files and build output)
echo "📦 Creating archive..."
tar -czf "$TEMP_ARCHIVE" \
  --exclude='.git' \
  --exclude='.gitignore' \
  --exclude='.github' \
  --exclude='.builder' \
  --exclude='.omx' \
  --exclude='.agents' \
  --exclude='.codex' \
  --exclude='.claude' \
  --exclude='.vscode' \
  --exclude='.idea' \
  --exclude='.mcp.json' \
  --exclude='dist' \
  --exclude='claudebox.run' \
  --exclude='*.swp' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  --exclude='*~' \
  --exclude='archive.tar.gz' \
  --exclude='*.tar.gz' \
  .

# Move to final location
mv "$TEMP_ARCHIVE" "$ARCHIVE"

if tar -tzf "$ARCHIVE" | grep -E '^\./\.(omx|agents|codex)(/|$)' >/dev/null; then
  echo "❌ Archive includes local runtime state" >&2
  exit 1
fi

# Calculate SHA256
if command -v sha256sum >/dev/null 2>&1; then
  SHA256=$(sha256sum "$ARCHIVE" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  SHA256=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
else
  echo "❌ sha256sum or shasum required" >&2
  exit 1
fi

# Create final script with SHA256 embedded
echo "🔧 Assembling $OUTPUT..."
sed "s/__ARCHIVE_SHA256__/$SHA256/g" "$TEMPLATE" > "$OUTPUT"
cat "$ARCHIVE" >> "$OUTPUT"
chmod +x "$OUTPUT"

# Keep the archive (don't delete it)

echo "✅ Files created:"
echo "   📦 Installer: $OUTPUT ($(wc -c < "$OUTPUT" | tr -d ' ') bytes)"
echo "   📄 Archive: $ARCHIVE ($(wc -c < "$ARCHIVE" | tr -d ' ') bytes)"
echo "   🔐 SHA256: $SHA256"

# Create a symlink from the root for backward compatibility
ln -sf "$OUTPUT" claudebox.run
