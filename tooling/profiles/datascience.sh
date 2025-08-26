#!/usr/bin/env bash
# Data Science profile for ClaudeBox
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "datascience" "Data Science (Python, Jupyter, R)"
        ;;
    packages)
        printf '%s\n' "r-base"
        ;;
    dockerfile)
        packages="r-base"
        if [[ -n "$packages" ]]; then
            printf 'RUN apt-get update && apt-get install -y %s && apt-get clean\n' "$packages"
        fi
        ;;
    depends)
        printf '%s\n' "core"
        ;;
    *)
        printf 'Usage: %s {info|packages|dockerfile|depends}\n' "$0" >&2
        exit 1
        ;;
esac