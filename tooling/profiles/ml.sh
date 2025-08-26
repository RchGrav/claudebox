#!/usr/bin/env bash
# Machine Learning profile for ClaudeBox
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "ml" "Machine Learning (build layer only; Python via uv)"
        ;;
    packages)
        # ML profile just needs build tools which are dependencies
        printf '%s\n' ""
        ;;
    dockerfile)
        # ML profile uses build-tools for compilation
        printf '%s\n' "# ML profile uses build-tools for compilation"
        ;;
    depends)
        printf '%s\n' "core build-tools"
        ;;
    *)
        printf 'Usage: %s {info|packages|dockerfile|depends}\n' "$0" >&2
        exit 1
        ;;
esac