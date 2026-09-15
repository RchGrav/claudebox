#!/usr/bin/env bash
# All immutable or rarely‑changing environment variables live here.

# Configuration
# DEFAULT_FLAGS is loaded from file in main.sh, don't reset it here

# Docker and user settings
# Shared with the launcher and command modules.
# shellcheck disable=SC2034
readonly DOCKER_USER="claude"
USER_ID=$(id -u)
readonly USER_ID
GROUP_ID=$(id -g)
readonly GROUP_ID

# Directories and paths
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
# Shared with the launcher and command modules.
# shellcheck disable=SC2034
readonly LINK_TARGET="$HOME/.local/bin/claudebox"
export CLAUDEBOX_HOME="${HOME}/.claudebox"

# Version constants
# Shared with the launcher and command modules.
# shellcheck disable=SC2034
readonly NODE_VERSION="--lts"
# Shared with the launcher and command modules.
# shellcheck disable=SC2034
readonly DELTA_VERSION="0.17.0"

# Script path resolution - moved to main claudebox.sh since it needs BASH_SOURCE
# SCRIPT_PATH will be set by main script

# Export what other modules need
export USER_ID
export GROUP_ID
export PROJECT_DIR