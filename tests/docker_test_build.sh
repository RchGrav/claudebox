#!/usr/bin/env bash
# Docker-based ClaudeBox build and install test
# This script runs inside the Docker container

set -euo pipefail

bash .builder/build.sh || {
    echo "FAIL - Build failed with exit code: $?" >&2
    exit 1
}

if [[ ! -f dist/claudebox.run ]]; then
    echo "FAIL - Build output not found." >&2
    exit 1
fi

if [[ ! -x dist/claudebox.run ]]; then
    echo "FAIL - Build output is not executable." >&2
    exit 1
fi

bash ./dist/claudebox.run || {
    echo "FAIL - Installation failed with exit code: $?" >&2
    exit 1
}

if [[ ! -d "$HOME/.claudebox" ]]; then
    echo "FAIL - Installation directory not found." >&2
    exit 1
fi

export PATH="$HOME/.local/bin:$PATH"
claudebox --help >/dev/null || {
    echo "claudebox command failed!" >&2
    exit 1
}
