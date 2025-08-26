#!/usr/bin/env bash
# Web development tools profile for ClaudeBox
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "web" "Web Dev Tools (nginx, HTTP test clients)"
        ;;
    packages)
        printf '%s\n' "nginx apache2-utils httpie"
        ;;
    dockerfile)
        packages="nginx apache2-utils httpie"
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