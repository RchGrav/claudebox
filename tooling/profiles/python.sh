#!/usr/bin/env bash
# Python development profile for ClaudeBox
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "python" "Python Development (managed via uv)"
        ;;
    packages)
        # Python packages are managed via uv, not apt
        printf '%s\n' ""
        ;;
    dockerfile)
        cat << 'EOF'
# Python profile - uv already installed in base image
# Python venv and dev tools are managed via entrypoint flag system
EOF
        ;;
    depends)
        printf '%s\n' "core"
        ;;
    *)
        printf 'Usage: %s {info|packages|dockerfile|depends}\n' "$0" >&2
        exit 1
        ;;
esac