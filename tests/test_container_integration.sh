#!/usr/bin/env bash
# Real Docker integration coverage for production entrypoint mount behavior.
set -Eeuo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$TEST_DIR")"
SESSION_ID="claudebox-it-$$-$(date +%s)"
TMP_ROOT="$ROOT_DIR/.omx/tmp"
mkdir -p "$TMP_ROOT"
SANDBOX="$(mktemp -d "$TMP_ROOT/container-integration.XXXXXX")"
FIXTURE_CONTEXT="$SANDBOX/fixture-context"
WORKSPACE="$SANDBOX/workspace with spaces"
PROJECT_PARENT="$SANDBOX/project parent"
IMAGE_NAME="$SESSION_ID-runtime"
DOCKER_HOST_VALUE="$(docker context inspect --format '{{.Endpoints.docker.Host}}')"
DOCKER_CONFIG_VALUE="$SANDBOX/docker-config"

cleanup() {
    docker rmi -f "$IMAGE_NAME" >/dev/null 2>&1 || true
    rm -rf "$SANDBOX"
}
trap cleanup EXIT

log() {
    printf '\n==> %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    if [[ -d "$SANDBOX" ]]; then
        printf '\nSandbox state under %s:\n' "$SANDBOX" >&2
        find "$SANDBOX" -maxdepth 5 -print 2>/dev/null | sed 's/^/  /' >&2 || true
    fi
    exit 1
}

record_full_build_handle() {
    log "Full build handle: $SESSION_ID"

    if docker buildx version >/dev/null 2>&1; then
        printf 'Full build capability: docker buildx plugin discovered with isolated Docker config\n'
    else
        printf 'Full build capability: blocked before downloads; docker buildx plugin is not discoverable\n'
    fi

    if docker build --help 2>&1 | grep -q -- '--progress'; then
        printf 'Full build capability: docker build supports --progress\n'
    else
        printf 'Full build capability: blocked before downloads; current Docker legacy builder rejects --progress used by main.sh/lib/docker.sh\n'
    fi

    if docker image inspect claudebox-core >/dev/null 2>&1; then
        printf 'Full build state: existing claudebox-core image is available\n'
    else
        printf 'Full build state: claudebox-core is absent; fixture build/run below exercises production container startup and mount construction\n'
    fi
}

configure_docker_access() {
    mkdir -p "$DOCKER_CONFIG_VALUE"
    if [[ -d /opt/homebrew/lib/docker/cli-plugins ]]; then
        printf '{"cliPluginsExtraDirs":["/opt/homebrew/lib/docker/cli-plugins"]}\n' > "$DOCKER_CONFIG_VALUE/config.json"
    else
        printf '{}\n' > "$DOCKER_CONFIG_VALUE/config.json"
    fi
    export DOCKER_HOST="$DOCKER_HOST_VALUE"
    export DOCKER_CONFIG="$DOCKER_CONFIG_VALUE"
    export DOCKER_BUILDKIT=1
}

write_fixture_image() {
    log "Building constrained Debian/uv fixture with production entrypoint"
    mkdir -p "$FIXTURE_CONTEXT"
    cp "$ROOT_DIR/build/docker-entrypoint" "$FIXTURE_CONTEXT/docker-entrypoint"

    cat > "$FIXTURE_CONTEXT/generate-tools-readme" <<'STUB'
#!/usr/bin/env bash
printf 'fixture tooling\n'
STUB
    chmod +x "$FIXTURE_CONTEXT/generate-tools-readme"

    cat > "$FIXTURE_CONTEXT/claude" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    printf 'claude fixture 1.0.0\n'
    exit 0
fi
printf 'claude fixture args: %s\n' "$*"
STUB
    chmod +x "$FIXTURE_CONTEXT/claude"

    cat > "$FIXTURE_CONTEXT/Dockerfile" <<'DOCKERFILE'
FROM debian:bookworm
ARG USER_ID
ARG GROUP_ID
RUN apt-get update && \
    apt-get install -y --no-install-recommends bash ca-certificates curl passwd util-linux && \
    rm -rf /var/lib/apt/lists/*
RUN groupadd -g ${GROUP_ID} claude 2>/dev/null || true && \
    useradd -m -u ${USER_ID} -g ${GROUP_ID} -s /bin/bash claude
USER claude
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
USER root
COPY claude /usr/local/bin/claude
COPY generate-tools-readme /usr/local/bin/generate-tools-readme
COPY docker-entrypoint /usr/local/bin/docker-entrypoint
RUN sed -i 's|DOCKERUSER|claude|g' /usr/local/bin/docker-entrypoint && \
    chmod +x /usr/local/bin/claude /usr/local/bin/generate-tools-readme /usr/local/bin/docker-entrypoint
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
DOCKERFILE

    docker build \
        --build-arg USER_ID="$(id -u)" \
        --build-arg GROUP_ID="$(id -g)" \
        -f "$FIXTURE_CONTEXT/Dockerfile" \
        -t "$IMAGE_NAME" \
        "$FIXTURE_CONTEXT"
}

prepare_mounts() {
    local slot="$1"
    mkdir -p "$WORKSPACE" "$PROJECT_PARENT" \
        "$slot/.claude" "$slot/.config" "$slot/.cache" \
        "$PROJECT_PARENT/.local/share/uv/python"
    printf '[profiles]\n' > "$PROJECT_PARENT/profiles.ini"
    printf '2' > "$PROJECT_PARENT/.project_container_counter"
}

run_entrypoint() {
    local slot="$1"
    local case_name="$2"
    local output_file="$SANDBOX/$case_name.out"

    log "Running production entrypoint mount layout: $case_name"
    if ! (
        cd "$WORKSPACE"
        export HOME="$SANDBOX/home"
        export PROJECT_DIR="$WORKSPACE"
        export PROJECT_PARENT_DIR="$PROJECT_PARENT"
        export PROJECT_SLOT_DIR="$slot"
        export IMAGE_NAME
        export VERBOSE=false
        export CLAUDEBOX_WRAP_TMUX=false
        export DOCKER_HOST="$DOCKER_HOST_VALUE"
        export DOCKER_CONFIG="$DOCKER_CONFIG_VALUE"
        export DOCKER_BUILDKIT=1
        # shellcheck disable=SC1090,SC1091
        source "$ROOT_DIR/lib/common.sh"
        # shellcheck disable=SC1090,SC1091
        source "$ROOT_DIR/lib/env.sh"
        # shellcheck disable=SC1090,SC1091
        source "$ROOT_DIR/lib/os.sh"
        # shellcheck disable=SC1090,SC1091
        source "$ROOT_DIR/lib/project.sh"
        # shellcheck disable=SC1090,SC1091
        source "$ROOT_DIR/lib/docker.sh"
        run_claudebox_container "" "interactive" --version
    ) > "$output_file" 2>&1; then
        sed -n '1,180p' "$output_file" >&2
        fail "entrypoint run failed: $case_name"
    fi

    sed -n '1,180p' "$output_file"

    if grep -q 'local: can only be used in a function' "$output_file"; then
        sed -n '1,180p' "$output_file" >&2
        fail "entrypoint hit top-level local failure: $case_name"
    fi
    grep -q 'claude fixture 1.0.0' "$output_file" || fail "entrypoint did not reach claude command: $case_name"
}

assert_project_venv_created() {
    local label="$1"

    [[ -d "$PROJECT_PARENT/.venv" ]] || fail "$label: shared project venv was not created"
    [[ -f "$PROJECT_PARENT/.venv_flag" ]] || fail "$label: venv completion flag was not created"
}

docker_probe() {
    local slot="$1"
    local name="$2"
    local command="$3"
    local container
    local status
    local exit_code
    local waited=0

    container="$(docker create \
        --name "$SESSION_ID-$name" \
        --entrypoint /bin/bash \
        -v "$PROJECT_PARENT":/home/claude/.claudebox \
        -v "$slot/.cache":/home/claude/.cache \
        -v "$PROJECT_PARENT/.local/share/uv/python":/home/claude/.local/share/uv/python \
        "$IMAGE_NAME" -lc "$command")"

    docker start "$container" >/dev/null

    while [[ "$waited" -lt 60 ]]; do
        status="$(docker inspect --format '{{.State.Status}} {{.State.ExitCode}}' "$container" 2>/dev/null || true)"
        case "$status" in
            exited\ *) break ;;
        esac
        sleep 1
        waited=$((waited + 1))
    done

    if [[ "$status" != exited\ * ]]; then
        docker logs "$container" 2>&1 || true
        docker rm -f "$container" >/dev/null 2>&1 || true
        return 124
    fi

    exit_code="${status#exited }"
    docker logs "$container" 2>&1 || true
    docker rm -f "$container" >/dev/null 2>&1 || true
    return "$exit_code"
}

venv_python_target() {
    local slot="$1"

    docker_probe "$slot" "target-$RANDOM" '/home/claude/.claudebox/.venv/bin/python -c "import os, sys; print(os.path.realpath(sys.executable))"'
}

assert_venv_works_with_slot() {
    local slot="$1"
    local label="$2"

    if ! docker_probe "$slot" "version-$RANDOM" '/home/claude/.claudebox/.venv/bin/python --version' >/dev/null 2>&1; then
        printf '%s venv python target: %s\n' "$label" "$(venv_python_target "$slot" 2>/dev/null || printf 'unresolved')" >&2
        fail "$label: shared venv does not resolve with this slot's .local/share mount"
    fi
}

assert_venv_uses_shared_python_store() {
    local slot="$1"
    local label="$2"
    local target

    target="$(venv_python_target "$slot")"
    printf '%s venv python target: %s\n' "$label" "$target"
    case "$target" in
        /home/claude/.local/share/uv/python/*) ;;
        *) fail "$label: venv points at non-shared interpreter path" ;;
    esac
}

configure_docker_access
record_full_build_handle
docker info >/dev/null
write_fixture_image

SLOT_ONE="$SANDBOX/slot one"
SLOT_TWO="$SANDBOX/slot two"

prepare_mounts "$SLOT_ONE"
run_entrypoint "$SLOT_ONE" "slot-one-first"
assert_project_venv_created "slot one first run"
assert_venv_works_with_slot "$SLOT_ONE" "slot one first run"
printf 'slot one first run venv python target: %s\n' "$(venv_python_target "$SLOT_ONE")"

run_entrypoint "$SLOT_ONE" "slot-one-second"
assert_project_venv_created "slot one second run"
assert_venv_works_with_slot "$SLOT_ONE" "slot one second run"

prepare_mounts "$SLOT_TWO"
run_entrypoint "$SLOT_TWO" "slot-two-first"
assert_project_venv_created "slot two first run"
assert_venv_works_with_slot "$SLOT_TWO" "slot two first run"
assert_venv_uses_shared_python_store "$SLOT_TWO" "slot two first run"

log "Container integration checks passed"
