#!/usr/bin/env bash
# Guards slot selection preflight. An explicit slot command should validate the
# requested slot, not depend on the default "next inactive slot" selector.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/claudebox-slot-selection.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
export PROJECT_DIR="$SANDBOX/project"
export SCRIPT_DIR="$ROOT_DIR"
export CLAUDEBOX_SCRIPT_DIR="$ROOT_DIR"
export VERBOSE=false
export IMAGE_NAME="claudebox-test-image"

mkdir -p "$HOME" "$PROJECT_DIR" "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "${1:-}" in' \
    '    ps)' \
    '        printf "%s\n" "${DOCKER_PS_NAMES:-}"' \
    '        ;;' \
    '    attach)' \
    '        printf "attach:%s\n" "${2:-}"' \
    '        exit "${DOCKER_ATTACH_STATUS:-0}"' \
    '        ;;' \
    '    inspect)' \
    '        printf "%s\n" "${DOCKER_INSPECT_ENV:-}"' \
    '        ;;' \
    '    image|info)' \
    '        ;;' \
    'esac' \
    'exit 0' > "$HOME/.local/bin/docker"
chmod +x "$HOME/.local/bin/docker"

setup_claude_agent_command() { :; }
logo_small() { :; }
cecho() { printf '%s\n' "$1"; }
show_no_slots_menu() { printf '%s\n' "No available slots found"; return 1; }
error() { printf '%s\n' "$1"; return 1; }
check_docker() { return 0; }
needs_docker_rebuild() { return 1; }
setup_shared_commands() { :; }
build_docker_image() { :; }
run_claudebox_container() {
    printf 'run:%s:%s:%s\n' "$1" "$2" "$*"
}
docker_attach_status=0
export DOCKER_ATTACH_STATUS=0
export DOCKER_INSPECT_ENV=""

docker() {
    case "${1:-}" in
        ps)
            printf '%s\n' "${DOCKER_PS_NAMES:-}"
            ;;
        attach)
            printf 'attach:%s\n' "${2:-}"
            return "$docker_attach_status"
            ;;
        inspect)
            printf '%s\n' "${DOCKER_INSPECT_ENV:-}"
            ;;
        image|info)
            ;;
    esac
    return 0
}

# shellcheck disable=SC1091
source "$ROOT_DIR/lib/project.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/preflight.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/clipboard.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/commands.slot.sh"

clipboard_probe_status=0
clipboard_bridge_probe() {
    [[ -n "${1:-}" ]] || return 1
    [[ -n "${2:-}" ]] || return 1
    return "$clipboard_probe_status"
}

TESTS_RUN=0
TESTS_PASSED=0

check() {
    local name="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'Test %d: %s... ' "$TESTS_RUN" "$name"
    if "$@"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf 'PASS\n'
    else
        printf 'FAIL\n'
    fi
}

parent="$(get_parent_dir "$PROJECT_DIR")"
mkdir -p "$parent"
printf '1' > "$parent/.project_container_counter"

slot_name="$(generate_container_name "$PROJECT_DIR" 1)"
slot_dir="$parent/$slot_name"
mkdir -p "$slot_dir/.claude"

running_container="claudebox-$(basename "$parent")-$slot_name"
export DOCKER_PS_NAMES="$running_container"

slot_preflight_allows_existing_active_slot() {
    preflight_check slot 1 >/dev/null 2>&1
}

check "explicit slot preflight ignores default availability" slot_preflight_allows_existing_active_slot

export DOCKER_PS_NAMES=""

missing_slot_zero_fails() {
    ! preflight_check slot 0 >/dev/null 2>&1
}

missing_slot_zero_padded_fails() {
    ! preflight_check slot 00 >/dev/null 2>&1
}

missing_slot_noninteger_fails() {
    ! preflight_check slot abc >/dev/null 2>&1
}

missing_slot_empty_fails() {
    ! preflight_check slot >/dev/null 2>&1
}

missing_slot_two_fails() {
    ! preflight_check slot 2 >/dev/null 2>&1
}

check "slot 0 is rejected before launch" missing_slot_zero_fails
check "zero-padded slot 0 is rejected before launch" missing_slot_zero_padded_fails
check "noninteger slot is rejected before launch" missing_slot_noninteger_fails
check "missing slot number is rejected before launch" missing_slot_empty_fails
check "missing explicit slot is rejected before launch" missing_slot_two_fails

main_slot_command_reaches_dispatch_when_default_none() {
    DOCKER_PS_NAMES="$running_container" /bin/bash "$ROOT_DIR/main.sh" slot 1 2>&1 | grep -q "^attach:$running_container$"
}

check "main slot command bypasses default availability gate" main_slot_command_reaches_dispatch_when_default_none

active_slot_with_args_fails_actionably() {
    local output=""
    local status=0

    export DOCKER_PS_NAMES="$running_container"
    output="$(_cmd_slot 1 --version 2>&1)"
    status=$?

    [ "$status" -ne 0 ] && printf '%s' "$output" | grep -q 'already running'
}

idle_slot_runs_container() {
    local output=""

    export DOCKER_PS_NAMES=""
    output="$(_cmd_slot 1 --version 2>&1)" || return 1
    printf '%s' "$output" | grep -q "^run:$running_container:interactive:$running_container interactive --version$"
}

active_slot_attach_preserves_status() {
    export DOCKER_PS_NAMES="$running_container"
    docker_attach_status=23
    export DOCKER_ATTACH_STATUS=23
    unset CLAUDEBOX_CLIPBOARD
    _cmd_slot 1 >/dev/null 2>&1
    [ "$?" -eq 23 ]
}

active_slot_clipboard_without_bridge_fails() {
    local output=""
    local status=0

    export DOCKER_PS_NAMES="$running_container"
    export DOCKER_INSPECT_ENV=""
    export CLAUDEBOX_CLIPBOARD=true
    output="$(_cmd_slot 1 2>&1)"
    status=$?
    unset CLAUDEBOX_CLIPBOARD

    [ "$status" -ne 0 ] &&
        printf '%s' "$output" | grep -q -- '--clipboard' &&
        ! printf '%s' "$output" | grep -q "^attach:"
}

active_slot_clipboard_with_bridge_attaches() {
    local output=""

    export DOCKER_PS_NAMES="$running_container"
    export DOCKER_INSPECT_ENV="CLAUDEBOX_CLIPBOARD_URL=http://host.docker.internal:45678
CLAUDEBOX_CLIPBOARD_TOKEN=test-token"
    export CLAUDEBOX_CLIPBOARD=true
    clipboard_probe_status=0
    docker_attach_status=0
    export DOCKER_ATTACH_STATUS=0
    output="$(_cmd_slot 1 2>&1)" || return 1
    unset CLAUDEBOX_CLIPBOARD

    printf '%s' "$output" | grep -q "^attach:$running_container$"
}

active_slot_clipboard_with_dead_bridge_fails() {
    local output=""
    local status=0

    export DOCKER_PS_NAMES="$running_container"
    export DOCKER_INSPECT_ENV="CLAUDEBOX_CLIPBOARD_URL=http://host.docker.internal:45678
CLAUDEBOX_CLIPBOARD_TOKEN=test-token"
    export CLAUDEBOX_CLIPBOARD=true
    clipboard_probe_status=1
    output="$(_cmd_slot 1 2>&1)"
    status=$?
    unset CLAUDEBOX_CLIPBOARD
    clipboard_probe_status=0

    [ "$status" -ne 0 ] &&
        printf '%s' "$output" | grep -q 'without live clipboard support' &&
        ! printf '%s' "$output" | grep -q "^attach:"
}

main_clipboard_slot_without_bridge_fails() {
    local output=""
    local status=0

    export DOCKER_INSPECT_ENV=""
    output="$(DOCKER_PS_NAMES="$running_container" /bin/bash "$ROOT_DIR/main.sh" --clipboard slot 1 2>&1)"
    status=$?

    [ "$status" -ne 0 ] &&
        printf '%s' "$output" | grep -q -- '--clipboard' &&
        ! printf '%s' "$output" | grep -q "^attach:"
}

check "active slot with extra args fails actionably" active_slot_with_args_fails_actionably
check "idle explicit slot launches selected container" idle_slot_runs_container
check "active explicit slot attach preserves status" active_slot_attach_preserves_status
check "active slot rejects late clipboard enablement" active_slot_clipboard_without_bridge_fails
check "active slot with existing clipboard bridge attaches" active_slot_clipboard_with_bridge_attaches
check "active slot rejects stale clipboard bridge" active_slot_clipboard_with_dead_bridge_fails
check "main clipboard slot rejects active session without bridge" main_clipboard_slot_without_bridge_fails

printf '\n%d/%d passed\n' "$TESTS_PASSED" "$TESTS_RUN"
if [ "$TESTS_PASSED" -ne "$TESTS_RUN" ]; then
    exit 1
fi
