#!/usr/bin/env bash
# Run the production generator with BSD/GNU awk and inspect Docker's input.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ${1:-} == --child ]]; then
    # shellcheck source=lib/config.sh
    source "$ROOT_DIR/lib/config.sh"
    # Load the actual generator without running the interactive CLI.
    eval "$(sed -n '/^build_docker_image()/,/^}/p' "$ROOT_DIR/main.sh")"
    export SCRIPT_DIR="$ROOT_DIR"
    export PROJECT_DIR="$TEST_ROOT/project"
    export PROJECT_PARENT_DIR="$TEST_ROOT/state"
    # These boundary functions are invoked by the dynamically loaded generator.
    # shellcheck disable=SC2317,SC2329
    crc32_file() { cksum "$1" | cut -d ' ' -f1; }
    # shellcheck disable=SC2317,SC2329
    generate_parent_folder_name() { printf 'test-project\n'; }
    # shellcheck disable=SC2317,SC2329
    save_docker_layer_checksums() { :; }
    # shellcheck disable=SC2317,SC2329
    error() { printf '%s\n' "$*" >&2; exit 1; }
    # shellcheck disable=SC2317,SC2329
    run_docker_build() {
        cp "$1" "$TEST_ROOT/generated.Dockerfile"
        [[ "$TEST_FAIL" == false ]] || return 17
    }
    trap 'touch "$TEST_ROOT/exit-trap"' EXIT
    trap 'printf "caller INT trap\n"' INT
    trap 'printf "caller TERM trap\n"' TERM
    trap -p INT TERM > "$TEST_ROOT/traps-before"
    build_docker_image
    trap -p INT TERM > "$TEST_ROOT/traps-after"
    cmp "$TEST_ROOT/traps-before" "$TEST_ROOT/traps-after"
    exit 0
fi
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudebox-dockerfile.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/project" "$TEST_ROOT/state" "$TEST_ROOT/home" "$TEST_ROOT/tmp"
printf '[profiles]\ncore\njava\n' > "$TEST_ROOT/state/profiles.ini"
env HOME="$TEST_ROOT/home" TMPDIR="$TEST_ROOT/tmp" TEST_ROOT="$TEST_ROOT" TEST_FAIL=false \
    "$BASH" "$0" --child
test -f "$TEST_ROOT/exit-trap"
if grep -q '{{' "$TEST_ROOT/generated.Dockerfile"; then
    printf 'FAIL: unreplaced Dockerfile placeholder\n' >&2
    exit 1
fi
grep -q 'apt-get update && apt-get install' "$TEST_ROOT/generated.Dockerfile"
grep -q 'sdkman' "$TEST_ROOT/generated.Dockerfile"
grep -q 'LABEL claudebox.project="test-project"' "$TEST_ROOT/generated.Dockerfile"
[[ -z $(find "$TEST_ROOT/tmp" -type f -print) ]]
status=0
env HOME="$TEST_ROOT/home" TMPDIR="$TEST_ROOT/tmp" TEST_ROOT="$TEST_ROOT" TEST_FAIL=true \
    "$BASH" "$0" --child || status=$?
[[ $status == 17 ]]
[[ -z $(find "$TEST_ROOT/tmp" -type f -print) ]]
printf 'PASS: multiline Dockerfile content, caller traps, cleanup and build failure status\n'
