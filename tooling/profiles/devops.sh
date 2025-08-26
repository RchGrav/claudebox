#!/usr/bin/env bash
# DevOps tools profile for ClaudeBox
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "devops" "DevOps Tools (Docker, Kubernetes, Terraform, etc.)"
        ;;
    packages)
        printf '%s\n' "docker.io docker-compose kubectl helm terraform ansible awscli"
        ;;
    dockerfile)
        packages="docker.io docker-compose kubectl helm terraform ansible awscli"
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