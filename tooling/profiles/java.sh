#!/usr/bin/env bash
# Java development profile for ClaudeBox
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "java" "Java Development (OpenJDK 17, Maven, Gradle, Ant)"
        ;;
    packages)
        printf '%s\n' "openjdk-17-jdk maven gradle ant"
        ;;
    dockerfile)
        packages="openjdk-17-jdk maven gradle ant"
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