#!/usr/bin/env bash
# Verify rendered output, not just the exit status of the command.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/claudebox-output.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home" PROJECT_PARENT_DIR="$SANDBOX/project with spaces"
mkdir -p "$HOME" "$PROJECT_PARENT_DIR"
printf '[profiles]\npython\nrust\n' > "$PROJECT_PARENT_DIR/profiles.ini"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/commands.profile.sh"
logo_output="$(logo_small)"
if [[ "$logo_output" == *'%s'* ]]; then
    printf 'FAIL: logo contains an unexpanded format placeholder\n' >&2
    exit 1
fi
printf 'PASS: logo renders its text without a literal format placeholder\n'
output="$(_cmd_profiles)"
grep -Fq '  python rust' <<< "$output"
grep -Eq 'python[[:space:]]+.*✓' <<< "$output"
grep -Eq 'rust[[:space:]]+.*✓' <<< "$output"
if [[ "$output" == *'%s'* ]] || [[ "$output" == *'%-15s'* ]]; then
    printf 'FAIL: profile list contains an unexpanded format placeholder\n' >&2
    exit 1
fi
printf 'PASS: multiple profiles are independently marked enabled and formatted\n'
