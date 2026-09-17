#!/bin/bash
# Build the ClaudeBox self-extracting installer script
# Packages entire repo for extraction to ~/.claudebox/

set -Eeuo pipefail
IFS=$'\n\t'

# Get version from main.sh
VERSION=$(grep -m1 'readonly CLAUDEBOX_VERSION=' main.sh | cut -d'"' -f2)
if [[ -z "$VERSION" ]]; then
  printf '❌ Could not extract version from main.sh\n' >&2
  exit 1
fi

printf '🔨 Building ClaudeBox v%s\n' "$VERSION"

# Clean dist directory
printf '🧹 Cleaning dist directory...\n'
rm -rf dist
mkdir -p dist

TEMPLATE=".builder/script_template_root.sh"
OUTPUT="dist/claudebox.run"
ARCHIVE="dist/claudebox-${VERSION}.tar.gz"

# Create archive in temp location to avoid "file changed as we read it" error
TEMP_ARCHIVE="/tmp/claudebox_archive_$$.tar.gz"

# Create archive of entire repo (excluding hidden files and build output)
printf '📦 Creating archive...\n'
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
  printf '❌ Archive includes local runtime state\n' >&2
  exit 1
fi

# Calculate SHA256
if command -v sha256sum >/dev/null 2>&1; then
  SHA256=$(sha256sum "$ARCHIVE" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  SHA256=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
else
  printf '❌ sha256sum or shasum required\n' >&2
  exit 1
fi

# Create final script with SHA256 embedded
printf '🔧 Assembling %s...\n' "$OUTPUT"
sed "s/__ARCHIVE_SHA256__/$SHA256/g" "$TEMPLATE" > "$OUTPUT"
cat "$ARCHIVE" >> "$OUTPUT"
chmod +x "$OUTPUT"

# Keep the archive (don't delete it)

printf '✅ Files created:\n'
printf '   📦 Installer: %s (%s bytes)\n' "$OUTPUT" "$(wc -c < "$OUTPUT" | tr -d ' ')"
printf '   📄 Archive: %s (%s bytes)\n' "$ARCHIVE" "$(wc -c < "$ARCHIVE" | tr -d ' ')"
printf '   🔐 SHA256: %s\n' "$SHA256"

# Create a symlink from the root for backward compatibility
ln -sf "$OUTPUT" claudebox.run
