#!/bin/bash
# Build the ClaudeBox self-extracting installer script

set -euo pipefail

TEMPLATE=".builder/script_template.sh"
OUTPUT="claudebox.run.sh"
ARCHIVE="archive.tar.gz"

# Include only files that will be extracted under .claudebox/scripts
INCLUDE_PATHS=(
  scripts/
  setup.sh
  README.md
)

# Safety check
if [[ ${#INCLUDE_PATHS[@]} -eq 0 ]]; then
  echo "❌ No content to package. Aborting." >&2
  exit 1
fi

# Create compressed payload
echo "📦 Creating archive..."
tar -czf "$ARCHIVE" "${INCLUDE_PATHS[@]}"

# Combine template + archive into final .run.sh
echo "🔧 Assembling $OUTPUT..."
cat "$TEMPLATE" "$ARCHIVE" > "$OUTPUT"
chmod +x "$OUTPUT"
rm "$ARCHIVE"

echo "✅ $OUTPUT created with contents:"
printf ' - %s\n' "${INCLUDE_PATHS[@]}"