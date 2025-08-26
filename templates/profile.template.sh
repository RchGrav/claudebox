#!/usr/bin/env bash
# Profile template for ClaudeBox
# Copy this file to create a new profile
set -euo pipefail

case "${1:-}" in
    info)
        # Return profile name and description separated by |
        printf '%s|%s\n' "PROFILE_NAME" "Profile description here"
        ;;
    packages)
        # Return space-separated list of apt packages to install
        # Leave empty if no packages needed
        printf '%s\n' ""
        ;;
    dockerfile)
        # Output Dockerfile RUN commands for this profile
        # Can be multiple lines, will be inserted into Dockerfile
        cat << 'EOF'
# Profile-specific Docker commands here
# RUN apt-get update && apt-get install -y something
EOF
        ;;
    depends)
        # Return space-separated list of profile dependencies
        # Common dependencies: core, build-tools
        printf '%s\n' ""
        ;;
    *)
        printf 'Usage: %s {info|packages|dockerfile|depends}\n' "$0" >&2
        exit 1
        ;;
esac