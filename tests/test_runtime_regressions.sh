#!/usr/bin/env bash
# Exercise real runtime argument construction and MCP merging with a Docker boundary stub.
# No Docker daemon or network access is needed. Requires jq, as does lib/docker.sh.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/claudebox-runtime.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
export ROOT_DIR SANDBOX
export HOME="$SANDBOX/home" TMPDIR="$SANDBOX/tmp"
export PROJECT_DIR="$SANDBOX/project with spaces"
export PROJECT_PARENT_DIR="$HOME/.claudebox/projects/test"
export PROJECT_SLOT_DIR="$PROJECT_PARENT_DIR/slot1"
export CLAUDEBOX_HOME="$HOME/.claudebox"
export DOCKER_USER=claude IMAGE_NAME=claudebox-test VERBOSE=false
export TMUX="$SANDBOX/socket/default,1,0"
mkdir -p "$HOME" "$TMPDIR" "$PROJECT_DIR/.claude" "$PROJECT_SLOT_DIR" "$SANDBOX/socket"
printf '%s\n' '{"mcpServers":{"user":{"command":"user-command"}}}' > "$HOME/.claude.json"
printf '%s\n' '{"mcpServers":{"project":{"command":"shared"},"shared":{"command":"keep"}}}' > "$PROJECT_DIR/.claude/settings.json"
printf '%s\n' '{"mcpServers":{"project":{"command":"local"}}}' > "$PROJECT_DIR/.claude/settings.local.json"

cat > "$SANDBOX/run.sh" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail
source "$ROOT_DIR/lib/docker.sh"
get_slot_index() { printf '1\n'; }
# Capture the arguments and read MCP bind sources while the real launcher runs.
docker() {
    case "${1:-}" in
        image) return 0 ;;
        commit)
            printf 'commit\n' >> "$SANDBOX/commits"
            test -f "$SANDBOX/container"
            return $? ;;
        rm) rm -f "$SANDBOX/container"; return 0 ;;
        run) touch "$SANDBOX/container" ;;
    esac
    printf '%s\n' "$@" > "$SANDBOX/args"
    local arg path
    for arg in "$@"; do
        case "$arg" in
            *:/tmp/user-mcp-config.json:ro)
                path="${arg%:/tmp/user-mcp-config.json:ro}"
                cp "$path" "$SANDBOX/user.json" ;;
            *:/tmp/project-mcp-config.json:ro)
                path="${arg%:/tmp/project-mcp-config.json:ro}"
                cp "$path" "$SANDBOX/project.json" ;;
        esac
    done
    return "${DOCKER_STATUS:-0}"
}
if [ "${TEST_ADMIN:-false}" = true ]; then
    source "$ROOT_DIR/lib/commands.core.sh"
    cecho() { :; }
    fillbar() { :; }
    success() { :; }
    YELLOW=''
    _cmd_shell admin
else
    trap 'printf done > "$SANDBOX/caller-cleanup"' EXIT
    run_claudebox_container "claudebox-test-slot" "pipe" --resume 'a session with spaces'
fi
CHILD

PASSED=0
FAILED=0
check() {
    local name="$1"
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$name"
        PASSED=$((PASSED + 1))
    else
        printf 'FAIL: %s\n' "$name"
        FAILED=$((FAILED + 1))
    fi
}
empty_tmp() { [ -z "$(find "$TMPDIR" -type f -print)" ]; }
no_broad_mount() { ! grep -Eq ':/home/claude/\.local/share(/uv(/tools)?)?(:ro)?$' "$SANDBOX/args"; }

status=0
"$BASH" "$SANDBOX/run.sh" || status=$?
check 'container success status is preserved' test "$status" -eq 0
check 'user MCP config is mounted' jq -e '.mcpServers.user.command == "user-command"' "$SANDBOX/user.json"
check 'local MCP overrides shared settings without discarding other servers' jq -e '.mcpServers.project.command == "local" and .mcpServers.shared.command == "keep"' "$SANDBOX/project.json"
check 'MCP temporary files are removed after normal return' empty_tmp
check 'caller EXIT cleanup is preserved' test -f "$SANDBOX/caller-cleanup"
check 'arguments containing spaces remain a single argument' grep -Fxq 'a session with spaces' "$SANDBOX/args"
check 'managed Python uses project-level storage' grep -Fxq "$PROJECT_PARENT_DIR/.local/share/uv/python:/home/claude/.local/share/uv/python" "$SANDBOX/args"
check 'image-provided uv tools are not hidden by a broad mount' no_broad_mount

# Clean up the baseline's leaked files so the failure-path assertion is independent.
find "$TMPDIR" -type f -exec rm -f {} \;
rm -f "$SANDBOX/caller-cleanup"
status=0
DOCKER_STATUS=17 "$BASH" "$SANDBOX/run.sh" || status=$?
check 'container failure status is preserved' test "$status" -eq 17
check 'MCP temporary files are removed when Docker fails' empty_tmp
check 'caller EXIT cleanup runs when Docker fails' test -f "$SANDBOX/caller-cleanup"

# The project venv is shared, so another slot must mount the same interpreter store.
find "$TMPDIR" -type f -exec rm -f {} \;
export PROJECT_SLOT_DIR="$PROJECT_PARENT_DIR/slot2"
"$BASH" "$SANDBOX/run.sh"
check 'a second slot uses the same managed-Python store' grep -Fxq "$PROJECT_PARENT_DIR/.local/share/uv/python:/home/claude/.local/share/uv/python" "$SANDBOX/args"

status=0
TEST_ADMIN=true "$BASH" "$SANDBOX/run.sh" || status=$?
check 'admin shell exits successfully after saving changes' test "$status" -eq 0
check 'admin shell commits exactly once' test "$(wc -l < "$SANDBOX/commits" | tr -d ' ')" -eq 1
check 'admin shell removes its stopped container' test ! -f "$SANDBOX/container"

# Optional host inputs must be passed as whole Docker arguments.
absent_arg() { ! grep -Fxq -- "$1" "$SANDBOX/args"; }
check 'missing gitconfig is not mounted' absent_arg "$HOME/.gitconfig:/home/claude/.gitconfig:ro"
check 'missing env file is not passed to Docker' absent_arg --env-file
printf '[user]\n    name = Test User\n' > "$HOME/.gitconfig"
printf 'GH_TOKEN=test-token\nANTHROPIC_BASE_URL=https://example.invalid\n' > "$PROJECT_DIR/.env"
"$BASH" "$SANDBOX/run.sh"
check 'existing gitconfig is mounted read-only' grep -Fxq "$HOME/.gitconfig:/home/claude/.gitconfig:ro" "$SANDBOX/args"
check 'env file is loaded by Docker' grep -Fxq -- '--env-file' "$SANDBOX/args"
check 'env file path with spaces remains a single argument' grep -Fxq "$PROJECT_DIR/.env" "$SANDBOX/args"
check 'env file remains mounted read-only' grep -Fxq "$PROJECT_DIR/.env:/workspace/.env:ro" "$SANDBOX/args"

# A dedicated SSH directory takes priority even before its first key is created.
mkdir -p "$HOME/.ssh"
printf 'host key fixture\n' > "$HOME/.ssh/id_test"
"$BASH" "$SANDBOX/run.sh"
check 'host SSH fallback remains read-only' grep -Fxq "$HOME/.ssh:/home/claude/.ssh:ro" "$SANDBOX/args"
mkdir -p "$CLAUDEBOX_HOME/ssh"
"$BASH" "$SANDBOX/run.sh"
check 'empty dedicated SSH directory is mounted read-write' grep -Fxq "$CLAUDEBOX_HOME/ssh:/home/claude/.ssh" "$SANDBOX/args"
check 'empty dedicated SSH directory does not fall back to host keys' absent_arg "$HOME/.ssh:/home/claude/.ssh:ro"
printf 'dedicated key fixture\n' > "$CLAUDEBOX_HOME/ssh/id_test"
"$BASH" "$SANDBOX/run.sh"
check 'populated dedicated SSH directory takes priority' grep -Fxq "$CLAUDEBOX_HOME/ssh:/home/claude/.ssh" "$SANDBOX/args"
rm -rf "$CLAUDEBOX_HOME/ssh" "$HOME/.ssh"
"$BASH" "$SANDBOX/run.sh"
check 'missing SSH directories do not create a host mount' absent_arg "$HOME/.ssh:/home/claude/.ssh:ro"

# A missing host API key must not erase the value from the env file.
unset ANTHROPIC_API_KEY
"$BASH" "$SANDBOX/run.sh"
check 'unset host API key does not override the env file' absent_arg 'ANTHROPIC_API_KEY='
ANTHROPIC_API_KEY=host-test-key "$BASH" "$SANDBOX/run.sh"
check 'explicit host API key is forwarded' grep -Fxq 'ANTHROPIC_API_KEY=host-test-key' "$SANDBOX/args"
ANTHROPIC_API_KEY='' "$BASH" "$SANDBOX/run.sh"
check 'explicitly empty host API key still overrides the env file' grep -Fxq 'ANTHROPIC_API_KEY=' "$SANDBOX/args"

source "$ROOT_DIR/lib/config.sh"
check 'DevOps profile retains AWS CLI' bash -c 'case " $(get_profile_packages devops) " in *" awscli "*) exit 0;; *) exit 1;; esac'
printf '\n%d passed; %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
