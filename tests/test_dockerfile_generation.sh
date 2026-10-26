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
printf '[profiles]\ncore\njava\n\n[packages]\npkg-config\nlibasound2-dev\nlibudev-dev\n' > "$TEST_ROOT/state/profiles.ini"
env HOME="$TEST_ROOT/home" TMPDIR="$TEST_ROOT/tmp" TEST_ROOT="$TEST_ROOT" TEST_FAIL=false \
    "$BASH" "$0" --child
test -f "$TEST_ROOT/exit-trap"
if grep -q '{{' "$TEST_ROOT/generated.Dockerfile"; then
    printf 'FAIL: unreplaced Dockerfile placeholder\n' >&2
    exit 1
fi
grep -q 'apt-get update && apt-get install' "$TEST_ROOT/generated.Dockerfile"
grep -q 'sdkman' "$TEST_ROOT/generated.Dockerfile"
# Packages added with `claudebox install` must be apt-installed as root.
packages_user=$(awk '/^USER /{u=$2} /apt-get install.*pkg-config libasound2-dev libudev-dev/{print u; exit}' "$TEST_ROOT/generated.Dockerfile")
if [[ "$packages_user" != "root" ]]; then
    printf 'FAIL: [packages] not installed as root (got %s)\n' "${packages_user:-<missing>}" >&2
    exit 1
fi
grep -q 'LABEL claudebox.project="test-project"' "$TEST_ROOT/generated.Dockerfile"
[[ -z $(find "$TEST_ROOT/tmp" -type f -print) ]]
status=0
env HOME="$TEST_ROOT/home" TMPDIR="$TEST_ROOT/tmp" TEST_ROOT="$TEST_ROOT" TEST_FAIL=true \
    "$BASH" "$0" --child || status=$?
[[ $status == 17 ]]
[[ -z $(find "$TEST_ROOT/tmp" -type f -print) ]]
# [packages] entries are interpolated into a root RUN line, so anything that
# is not an apt package spec must stop the build before Docker sees it.
for bad_entry in 'curl;touch${IFS}/pwned' 'curl|sh' 'curl&&id' '$(id)' '`id`' '-oAPT::Foo=1' 'pkg=$(id)'; do
    rm -f "$TEST_ROOT/generated.Dockerfile"
    printf '[profiles]\ncore\n\n[packages]\ncurl\n%s\n' "$bad_entry" > "$TEST_ROOT/state/profiles.ini"
    status=0
    env HOME="$TEST_ROOT/home" TMPDIR="$TEST_ROOT/tmp" TEST_ROOT="$TEST_ROOT" TEST_FAIL=false \
        "$BASH" "$0" --child 2>/dev/null || status=$?
    if [[ $status == 0 ]] || [[ -f "$TEST_ROOT/generated.Dockerfile" ]]; then
        printf 'FAIL: unsafe [packages] entry accepted: %s\n' "$bad_entry" >&2
        exit 1
    fi
done
# Valid apt specs (arch qualifier, version pin, target release) still work.
printf '[profiles]\ncore\n\n[packages]\nlibc6:amd64\nnodejs=18.19.0+dfsg-6~deb12u1\ng++/bookworm\n' > "$TEST_ROOT/state/profiles.ini"
env HOME="$TEST_ROOT/home" TMPDIR="$TEST_ROOT/tmp" TEST_ROOT="$TEST_ROOT" TEST_FAIL=false \
    "$BASH" "$0" --child
grep -q 'apt-get install -y libc6:amd64 nodejs=18.19.0+dfsg-6~deb12u1 g++/bookworm ' "$TEST_ROOT/generated.Dockerfile"
printf 'PASS: multiline Dockerfile content, extra packages, package validation, caller traps, cleanup and build failure status\n'
