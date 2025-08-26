#!/usr/bin/env bash
# Build tools profile for ClaudeBox
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "build-tools" "Build Tools (CMake, autotools, Ninja)"
        ;;
    packages)
        printf '%s\n' "cmake ninja-build autoconf automake libtool"
        ;;
    dockerfile)
        packages="cmake ninja-build autoconf automake libtool"
        if [[ -n "$packages" ]]; then
            printf 'RUN apt-get update && apt-get install -y %s && apt-get clean\n' "$packages"
        fi
        ;;
    depends)
        printf '%s\n' ""
        ;;
    *)
        printf 'Usage: %s {info|packages|dockerfile|depends}\n' "$0" >&2
        exit 1
        ;;
esac