#!/usr/bin/env bash
# Regression coverage for portable command sync checksums.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$TEST_DIR")"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/claudebox command sync.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

BIN_DIR="$SANDBOX/bin"
HOME_DIR="$SANDBOX/home dir"
SOURCE_ROOT="$SANDBOX/source root"
PROJECT_PARENT="$SANDBOX/project parent"
CALLER_CWD="$SANDBOX/caller cwd"

mkdir -p "$BIN_DIR" "$HOME_DIR/.claude/commands" "$SOURCE_ROOT/commands/nested dir" "$PROJECT_PARENT" "$CALLER_CWD"
CALLER_CWD="$(cd "$CALLER_CWD" && pwd)"

link_tool() {
    local name="$1"
    local path

    path="$(command -v "$name" 2>/dev/null || true)"
    if [[ -z "$path" ]]; then
        printf 'Required test command not found: %s\n' "$name" >&2
        exit 1
    fi
    ln -s "$path" "$BIN_DIR/$name"
}

# Build a closed PATH fixture from known-safe tool symlinks. This keeps
# Linux CI's /usr/bin/sha256sum and /bin/sha256sum invisible while preserving
# the macOS/Linux shasum fallback path the production code is meant to use.
for tool in bash cat cp cut dirname find grep mkdir mktemp rm sort touch tr uname; do
    link_tool "$tool"
done

SHASUM_REAL="$(command -v shasum 2>/dev/null || true)"
if [[ -z "$SHASUM_REAL" ]]; then
    printf 'Required test command not found: shasum\n' >&2
    exit 1
fi
SHASUM_CALL_LOG="$SANDBOX/shasum calls"
printf '#!/usr/bin/env bash\nprintf "shasum %%s\\n" "$*" >> "$SHASUM_CALL_LOG"\nexec "$SHASUM_REAL" "$@"\n' > "$BIN_DIR/shasum"
chmod +x "$BIN_DIR/shasum"

if command -v md5sum >/dev/null 2>&1; then
    link_tool md5sum
elif command -v md5 >/dev/null 2>&1; then
    link_tool md5
else
    printf 'Required test command not found: md5sum or md5\n' >&2
    exit 1
fi

FIXTURE_PATH="$BIN_DIR"
BASH_BIN="$BIN_DIR/bash"

printf 'bundled v1\n' > "$SOURCE_ROOT/commands/nested dir/cbox command.md"
printf 'user v1\n' > "$HOME_DIR/.claude/commands/user command.md"

assert_file_contains() {
    local file="$1"
    local expected="$2"

    if ! grep -q "$expected" "$file"; then
        printf 'Expected %s to contain %s\n' "$file" "$expected" >&2
        exit 1
    fi
}

run_sync_child() {
    (
        cd "$CALLER_CWD"
        env \
            HOME="$HOME_DIR" \
            PATH="$FIXTURE_PATH" \
            ROOT_DIR="$ROOT_DIR" \
            SCRIPT_DIR="$SOURCE_ROOT" \
            CLAUDEBOX_SCRIPT_DIR="$SOURCE_ROOT" \
            PROJECT_PARENT="$PROJECT_PARENT" \
            SHASUM_CALL_LOG="$SHASUM_CALL_LOG" \
            SHASUM_REAL="$SHASUM_REAL" \
            VERBOSE=false \
            "$BASH_BIN" -c '
                set -euo pipefail
                source "$ROOT_DIR/lib/common.sh"
                source "$ROOT_DIR/lib/os.sh"
                source "$ROOT_DIR/lib/project.sh"

                if command -v sha256sum >/dev/null 2>&1; then
                    printf "sha256sum unexpectedly visible at %s\n" "$(command -v sha256sum)" >&2
                    exit 1
                fi
                command -v shasum >/dev/null 2>&1

                printf "abc_digest=%s\n" "$(sha256_string abc)"
                printf "pwd_before=%s\n" "$(pwd)"
                sync_commands_to_project "$PROJECT_PARENT"
                printf "pwd_after=%s\n" "$(pwd)"
            '
    )
}

assert_output_contains() {
    local output="$1"
    local expected="$2"

    if [[ "$output" != *"$expected"* ]]; then
        printf 'Expected output to contain %s\nOutput was:\n%s\n' "$expected" "$output" >&2
        exit 1
    fi
}

first_output="$(run_sync_child)"
assert_output_contains "$first_output" 'abc_digest=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
assert_output_contains "$first_output" "pwd_before=$CALLER_CWD"
assert_output_contains "$first_output" "pwd_after=$CALLER_CWD"

assert_file_contains "$PROJECT_PARENT/commands/cbox/nested dir/cbox command.md" 'bundled v1'
assert_file_contains "$PROJECT_PARENT/commands/user/user command.md" 'user v1'
test -s "$PROJECT_PARENT/.commands_cbox_checksum"
test -s "$PROJECT_PARENT/.commands_user_checksum"

first_cbox_checksum="$(cat "$PROJECT_PARENT/.commands_cbox_checksum")"
first_user_checksum="$(cat "$PROJECT_PARENT/.commands_user_checksum")"

printf 'bundled v2\n' > "$SOURCE_ROOT/commands/nested dir/cbox command.md"
printf 'user v2\n' > "$HOME_DIR/.claude/commands/user command.md"

second_output="$(run_sync_child)"
assert_output_contains "$second_output" "pwd_before=$CALLER_CWD"
assert_output_contains "$second_output" "pwd_after=$CALLER_CWD"

assert_file_contains "$PROJECT_PARENT/commands/cbox/nested dir/cbox command.md" 'bundled v2'
assert_file_contains "$PROJECT_PARENT/commands/user/user command.md" 'user v2'

if [[ "$first_cbox_checksum" == "$(cat "$PROJECT_PARENT/.commands_cbox_checksum")" ]]; then
    printf 'Expected bundled command checksum to change after content update\n' >&2
    exit 1
fi

if [[ "$first_user_checksum" == "$(cat "$PROJECT_PARENT/.commands_user_checksum")" ]]; then
    printf 'Expected user command checksum to change after content update\n' >&2
    exit 1
fi

if ! grep -q 'shasum -a 256' "$SHASUM_CALL_LOG"; then
    printf 'Expected portable SHA256 fallback to call shasum -a 256\n' >&2
    exit 1
fi

printf 'Command sync portable checksum test passed\n'
