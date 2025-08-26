#!/usr/bin/env bash
# Core profile for ClaudeBox - Essential development utilities
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "core" "Core Development Utilities (compilers, VCS, shell tools)"
        ;;
    packages)
        printf '%s\n' "gcc g++ make git pkg-config libssl-dev libffi-dev zlib1g-dev tmux"
        ;;
    dockerfile)
        packages="gcc g++ make git pkg-config libssl-dev libffi-dev zlib1g-dev tmux"
        if [[ -n "$packages" ]]; then
            printf 'RUN apt-get update && apt-get install -y %s && apt-get clean\n' "$packages"
        fi
        ;;
    depends)
        # Core has no dependencies, it's the base
        printf '%s\n' ""
        ;;
    *)
        printf 'Usage: %s {info|packages|dockerfile|depends}\n' "$0" >&2
        exit 1
        ;;
esac