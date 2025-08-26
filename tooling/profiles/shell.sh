#!/usr/bin/env bash
# Shell tools profile for ClaudeBox
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "shell" "Optional Shell Tools (fzf, SSH, man, rsync, file)"
        ;;
    packages)
        printf '%s\n' "rsync openssh-client man-db gnupg2 aggregate file"
        ;;
    dockerfile)
        packages="rsync openssh-client man-db gnupg2 aggregate file"
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