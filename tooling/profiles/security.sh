#!/usr/bin/env bash
# Security tools profile for ClaudeBox
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "security" "Security Tools (scanners, crackers, packet tools)"
        ;;
    packages)
        printf '%s\n' "nmap tcpdump wireshark-common netcat-openbsd john hashcat hydra"
        ;;
    dockerfile)
        packages="nmap tcpdump wireshark-common netcat-openbsd john hashcat hydra"
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