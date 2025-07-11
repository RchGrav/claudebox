#!/usr/bin/env bash
# All immutable or rarely‑changing environment variables live here.

# Configuration
DEFAULT_FLAGS=()

# Docker and user settings
readonly DOCKER_USER="claude"
readonly USER_ID=$(id -u)
readonly GROUP_ID=$(id -g)

# Directories and paths
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
readonly LINK_TARGET="$HOME/.local/bin/claudebox"
export CLAUDEBOX_HOME="${HOME}/.claudebox"

# Version constants
readonly NODE_VERSION="--lts"
readonly DELTA_VERSION="0.17.0"

# Script path resolution - moved to main claudebox.sh since it needs BASH_SOURCE
# SCRIPT_PATH will be set by main script

# Export what other modules need
export USER_ID
export GROUP_ID
export PROJECT_DIR