#!/usr/bin/env bash
# Clipboard opt-in remains a host flag; it must never become a Claude prompt.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/cli.sh
source "$ROOT_DIR/lib/cli.sh"
parse_cli_args --clipboard 'inspect this image'
process_host_flags
[[ ${CLAUDEBOX_CLIPBOARD:-false} == true ]] || { echo 'FAIL: clipboard opt-in not recognized'; exit 1; }
[[ ${#CLI_PASS_THROUGH[@]} == 1 && ${CLI_PASS_THROUGH[0]} == 'inspect this image' ]]
printf 'PASS: clipboard is an explicit host-only option\n'

if [[ $(uname -s) != Darwin ]]; then
    printf 'SKIP: native clipboard process lifecycle requires macOS\n'
    exit 0
fi

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudebox-clipboard-lifecycle.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/project" "$TEST_ROOT/state/slot" "$TEST_ROOT/tmux"

for expected_status in 0 23; do
    status=0
    # The subprocess owns the bridge and its traps, just like the real CLI.
    # shellcheck disable=SC2016
    env HOME="$TEST_ROOT/home" ROOT_DIR="$ROOT_DIR" TEST_ROOT="$TEST_ROOT" TEST_EXIT="$expected_status" \
        "$BASH" -c '
        set -euo pipefail
        source "$ROOT_DIR/lib/clipboard.sh"
        source "$ROOT_DIR/lib/docker.sh"
        export CLAUDEBOX_SCRIPT_DIR="$ROOT_DIR" CLAUDEBOX_HOME="$TEST_ROOT/home/.claudebox"
        export PROJECT_DIR="$TEST_ROOT/project" PROJECT_PARENT_DIR="$TEST_ROOT/state" PROJECT_SLOT_DIR="$TEST_ROOT/state/slot"
        export DOCKER_USER=claude IMAGE_NAME=fixture VERBOSE=true HOST_OS=macOS CLAUDEBOX_CLIPBOARD=true
        export TMUX="$TEST_ROOT/tmux/default,1,0"
        get_slot_index() { printf "1\n"; }
        docker() {
            local arg token_found=false url_found=false shim_found=false
            for arg in "$@"; do
                case "$arg" in
                    "CLAUDEBOX_CLIPBOARD_TOKEN=$CLAUDEBOX_CLIPBOARD_TOKEN") token_found=true ;;
                    "CLAUDEBOX_CLIPBOARD_URL=$CLAUDEBOX_CLIPBOARD_URL") url_found=true ;;
                    *:/opt/claudebox-clipboard/xclip:ro) shim_found=true ;;
                esac
            done
            [[ $token_found == true && $url_found == true && $shim_found == true ]]
            [[ ${#CLAUDEBOX_CLIPBOARD_TOKEN} -ge 32 ]]
            kill -0 "$clipboard_pid"
            printf "%s\n%s\n" "$clipboard_pid" "$clipboard_dir" > "$TEST_ROOT/bridge-state"
            printf "%s" "$CLAUDEBOX_CLIPBOARD_TOKEN" > "$TEST_ROOT/token"
            return "$TEST_EXIT"
        }
        run_claudebox_container "" pipe
        ' > "$TEST_ROOT/output" 2>&1 || status=$?
    if [[ $status != "$expected_status" ]]; then
        cat "$TEST_ROOT/output"
        printf 'FAIL: expected container status %s, got %s\n' "$expected_status" "$status"
        exit 1
    fi
    bridge_pid=$(sed -n '1p' "$TEST_ROOT/bridge-state")
    bridge_dir=$(sed -n '2p' "$TEST_ROOT/bridge-state")
    if kill -0 "$bridge_pid" 2>/dev/null; then
        printf 'FAIL: clipboard server leaked after container exit\n'
        exit 1
    fi
    [[ ! -d $bridge_dir ]]
    if grep -Fq -f "$TEST_ROOT/token" "$TEST_ROOT/output"; then
        printf 'FAIL: clipboard token leaked in verbose output\n'
        exit 1
    fi
    printf 'PASS: authenticated clipboard lifetime follows container exit %s\n' "$expected_status"
done
