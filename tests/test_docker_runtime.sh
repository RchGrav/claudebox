#!/usr/bin/env bash
# Exercise host-side Docker argument construction and MCP file lifetime.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ${1:-} == --child ]]; then
    # shellcheck source=lib/docker.sh
    source "$ROOT_DIR/lib/docker.sh"
    PROJECT_DIR="$TEST_ROOT/project with spaces"
    PROJECT_PARENT_DIR="$TEST_ROOT/state"
    PROJECT_SLOT_DIR="$PROJECT_PARENT_DIR/slot"
    export DOCKER_USER=claude
    export IMAGE_NAME=claudebox-test
    export VERBOSE=false
    export TMUX="$TEST_ROOT/tmux/default,1,0"
    get_slot_index() { printf '1\n'; }
    # Docker is the external boundary: inspect the actual generated files while
    # they are mounted, then return a controlled container exit status.
    docker() {
        [[ $1 == run ]]
        shift
        local arg user_file="" project_file="" persistent=false
        for arg in "$@"; do
            case "$arg" in
                *:/tmp/user-mcp-config.json:ro) user_file=${arg%:/tmp/user-mcp-config.json:ro} ;;
                *:/tmp/project-mcp-config.json:ro) project_file=${arg%:/tmp/project-mcp-config.json:ro} ;;
                "$PROJECT_SLOT_DIR/.local/share:/home/claude/.local/share") persistent=true ;;
            esac
        done
        [[ $persistent == true && -d "$PROJECT_SLOT_DIR/.local/share" ]]
        jq -e '.mcpServers.user.command == "user-command"' "$user_file" >/dev/null
        jq -e '.mcpServers.shared.command == "shared-command" and .mcpServers.override.command == "local-command"' "$project_file" >/dev/null
        printf '%s\n' "$user_file" "$project_file" >> "$TEST_ROOT/mounted-files"
        return "$TEST_EXIT"
    }
    trap 'touch "$TEST_ROOT/parent-exit-trap"' EXIT
    run_claudebox_container "" pipe
    exit 0
fi

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudebox-runtime.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/project with spaces/.claude" "$TEST_ROOT/tmux" "$TEST_ROOT/tmp"
printf '%s\n' '{"mcpServers":{"user":{"command":"user-command"}}}' > "$TEST_ROOT/home/.claude.json"
printf '%s\n' '{"mcpServers":{"shared":{"command":"shared-command"},"override":{"command":"old-command"}}}' > "$TEST_ROOT/project with spaces/.claude/settings.json"
printf '%s\n' '{"mcpServers":{"override":{"command":"local-command"}}}' > "$TEST_ROOT/project with spaces/.claude/settings.local.json"
for expected_status in 0 23; do
    status=0
    env HOME="$TEST_ROOT/home" TMPDIR="$TEST_ROOT/tmp" TEST_ROOT="$TEST_ROOT" TEST_EXIT="$expected_status" \
        "$BASH" "$0" --child || status=$?
    [[ $status == "$expected_status" ]] || { printf 'FAIL: expected exit %s, got %s\n' "$expected_status" "$status"; exit 1; }
    while IFS= read -r mounted_file; do
        [[ ! -e "$mounted_file" ]] || { printf 'FAIL: leaked MCP file %s\n' "$mounted_file"; exit 1; }
    done < "$TEST_ROOT/mounted-files"
    [[ -z $(find "$TEST_ROOT/tmp" -type f -print) ]] || { printf 'FAIL: leaked intermediate MCP files\n'; exit 1; }
    [[ -f "$TEST_ROOT/parent-exit-trap" ]] || { printf 'FAIL: caller EXIT trap replaced\n'; exit 1; }
    printf 'PASS: merged MCP configuration, Python mount, cleanup and exit status %s\n' "$expected_status"
done
