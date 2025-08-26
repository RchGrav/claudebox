#!/usr/bin/env bash
# Embedded development profile for ClaudeBox
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "embedded" "Embedded Dev (ARM toolchain, serial debuggers)"
        ;;
    packages)
        printf '%s\n' "gcc-arm-none-eabi gdb-multiarch openocd picocom minicom screen"
        ;;
    dockerfile)
        cat << 'EOF'
RUN apt-get update && apt-get install -y gcc-arm-none-eabi gdb-multiarch openocd picocom minicom screen && apt-get clean
USER claude
RUN ~/.local/bin/uv tool install platformio
USER root
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