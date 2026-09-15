#!/usr/bin/env bash
# Regressions for command statuses that declaration builtins used to hide.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT_DIR

status=0
if "$BASH" -euo pipefail <<'TEST'
source "$ROOT_DIR/lib/config.sh"
get_profile_packages() { return 23; }
get_profile_core
TEST
then
    status=0
else
    status=$?
fi
if [[ "$status" -ne 23 ]]; then
    printf 'FAIL: profile generator hid package lookup failure (status %s)\n' "$status" >&2
    exit 1
fi
printf 'PASS: profile generator preserves package lookup failure\n'

status=0
if "$BASH" -euo pipefail <<'TEST'
source "$ROOT_DIR/lib/cli.sh"
get_command_requirements() { return 23; }
requires_docker_image shell
TEST
then
    status=0
else
    status=$?
fi
if [[ "$status" -ne 23 ]]; then
    printf 'FAIL: command requirement lookup hid failure (status %s)\n' "$status" >&2
    exit 1
fi
printf 'PASS: command requirement lookup preserves failure\n'
