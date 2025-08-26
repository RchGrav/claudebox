#!/usr/bin/env bash
# Networking tools profile for ClaudeBox
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "networking" "Network Tools (IP stack, DNS, route tools)"
        ;;
    packages)
        printf '%s\n' "iptables ipset iproute2 dnsutils"
        ;;
    dockerfile)
        packages="iptables ipset iproute2 dnsutils"
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