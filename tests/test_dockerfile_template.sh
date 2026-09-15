#!/usr/bin/env bash
# Test the real project Dockerfile generator without invoking a Docker daemon.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/claudebox-template.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home" TMPDIR="$SANDBOX/tmp"
mkdir -p "$HOME" "$TMPDIR" "$SANDBOX/project" "$SANDBOX/source/build"
cp -R "$ROOT_DIR/build/." "$SANDBOX/source/build/"
cp -R "$ROOT_DIR/lib" "$SANDBOX/source/lib"
SCRIPT_DIR="$SANDBOX/source"
PROJECT_DIR="$SANDBOX/project"
PROJECT_PARENT_DIR="$HOME/.claudebox/projects/test"
mkdir -p "$PROJECT_PARENT_DIR"
source "$ROOT_DIR/lib/config.sh"
# Load only the generator definition, not the CLI entrypoint.
eval "$(sed -n '/^build_docker_image() {/,/^}$/p' "$ROOT_DIR/main.sh")"
crc32_file() { cksum "$1" | cut -d ' ' -f1; }
generate_parent_folder_name() { printf 'test-project\n'; }
run_docker_build() { cp "$1" "$SANDBOX/generated"; }
save_docker_layer_checksums() { :; }
error() { printf '%s\n' "$*" >&2; exit 1; }

printf '[profiles]\ncore\ndevops\njava\nshell\n' > "$PROJECT_PARENT_DIR/profiles.ini"
(build_docker_image)
grep -Fq 'RUN apt-get update && apt-get install -y gcc' "$SANDBOX/generated"
grep -Fq "source \$HOME/.sdkman/bin/sdkman-init.sh && sdk install java" "$SANDBOX/generated"
grep -Fq "ARCH=\$(dpkg --print-architecture) && \\" "$SANDBOX/generated"
if grep -Eq '\{\{[[:space:]]*(PROFILE_INSTALLATIONS|LABELS)[[:space:]]*\}\}' "$SANDBOX/generated"; then
    printf 'FAIL: unexpected unresolved placeholder or installation in generated Dockerfile\n' >&2
    exit 1
fi
printf 'PASS: multiline profiles preserve ampersands, dollar signs and backslashes\n'
grep -Fxq 'LABEL claudebox.project="test-project"' "$SANDBOX/generated"
printf 'PASS: generated labels are inserted literally\n'

printf 'FROM claudebox-core\n  {{ PROFILE_INSTALLATIONS }}  \n  {{ LABELS }}  \n' > "$SCRIPT_DIR/build/Dockerfile.project"
(build_docker_image)
grep -Fq 'sdk install java' "$SANDBOX/generated"
if grep -Fq '{{' "$SANDBOX/generated"; then
    printf 'FAIL: unexpected unresolved placeholder or installation in generated Dockerfile\n' >&2
    exit 1
fi
printf 'PASS: whitespace around placeholders is supported\n'

printf '[profiles]\n' > "$PROJECT_PARENT_DIR/profiles.ini"
(build_docker_image)
if grep -Eq '^RUN |\{\{' "$SANDBOX/generated"; then
    printf 'FAIL: unexpected unresolved placeholder or installation in generated Dockerfile\n' >&2
    exit 1
fi
grep -Fxq 'LABEL claudebox.project="test-project"' "$SANDBOX/generated"
printf 'PASS: empty profiles render without an empty-array error\n'
