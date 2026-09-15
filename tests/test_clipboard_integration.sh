#!/usr/bin/env bash
# Real macOS clipboard bridge integration using a private named NSPasteboard.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$TEST_DIR")"

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'SKIP: native named NSPasteboard integration requires macOS\n'
    exit 0
fi

command -v osascript >/dev/null || { printf 'SKIP: osascript is required for native NSPasteboard integration\n'; exit 0; }
command -v python3 >/dev/null || { printf 'SKIP: python3 is required for clipboard bridge integration\n'; exit 0; }
command -v docker >/dev/null || { printf 'SKIP: Docker is required for clipboard bridge integration\n'; exit 0; }

SESSION_ID="claudebox-clipboard-it-$$-$(date +%s)"
TMP_ROOT="$ROOT_DIR/.omx/tmp"
mkdir -p "$TMP_ROOT"
SANDBOX="$(mktemp -d "$TMP_ROOT/clipboard-integration.XXXXXX")"
FIXTURE_CONTEXT="$SANDBOX/fixture-context"
WORKSPACE="$SANDBOX/workspace with spaces"
PROJECT_PARENT="$SANDBOX/project parent"
PROJECT_SLOT="$SANDBOX/slot one"
DOCKER_CONFIG_VALUE="$SANDBOX/docker-config"
IMAGE_NAME="$SESSION_ID-runtime"
PASTEBOARD_NAME="$SESSION_ID-pasteboard"
TOKEN="token-$SESSION_ID"
READY_FILE="$SANDBOX/ready.json"
SERVER_LOG="$SANDBOX/server.log"
SERVER_PID=""
EXPECTED_BRIDGE_URL=""
EXPECTED_BRIDGE_PORT=""
DOCKER_HOST_VALUE="$(docker context inspect --format '{{.Endpoints.docker.Host}}')"

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    CLAUDEBOX_TEST_PASTEBOARD="$PASTEBOARD_NAME" osascript -l JavaScript >/dev/null 2>&1 <<'JXA' || true
ObjC.import('AppKit');
ObjC.import('Foundation');
const env = $.NSProcessInfo.processInfo.environment;
const pbName = ObjC.unwrap(env.objectForKey('CLAUDEBOX_TEST_PASTEBOARD'));
$.NSPasteboard.pasteboardWithName(pbName).clearContents;
JXA
    docker rmi -f "$IMAGE_NAME" >/dev/null 2>&1 || true
    rm -rf -- "$SANDBOX"
}
trap cleanup EXIT

log() {
    printf '\n==> %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    if [[ -f "$SERVER_LOG" ]]; then
        printf '\nServer log:\n' >&2
        sed -n '1,120p' "$SERVER_LOG" >&2
    fi
    if [[ -d "$SANDBOX" ]]; then
        printf '\nSandbox state under %s:\n' "$SANDBOX" >&2
        find "$SANDBOX" -maxdepth 4 -print 2>/dev/null | sed 's/^/  /' >&2 || true
    fi
    exit 1
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

write_png_fixture() {
    local path="$1"

    python3 - "$path" <<'PY'
import base64
import sys

png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
with open(sys.argv[1], "wb") as file:
    file.write(base64.b64decode(png))
PY
}

write_private_pasteboard_png() {
    local png_file="$1"

    CLAUDEBOX_TEST_PASTEBOARD="$PASTEBOARD_NAME" CLAUDEBOX_TEST_PNG="$png_file" \
        osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
ObjC.import('Foundation');

const env = $.NSProcessInfo.processInfo.environment;
const pbName = ObjC.unwrap(env.objectForKey('CLAUDEBOX_TEST_PASTEBOARD'));
const pngPath = ObjC.unwrap(env.objectForKey('CLAUDEBOX_TEST_PNG'));
const data = $.NSData.dataWithContentsOfFile(pngPath);
if (!data) {
  $.exit(1);
}
const pasteboard = $.NSPasteboard.pasteboardWithName(pbName);
pasteboard.clearContents;
if (!pasteboard.setDataForType(data, $.NSPasteboardTypePNG)) {
  $.exit(2);
}
JXA
}

read_private_pasteboard_text() {
    CLAUDEBOX_TEST_PASTEBOARD="$PASTEBOARD_NAME" osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
ObjC.import('Foundation');

const env = $.NSProcessInfo.processInfo.environment;
const pbName = ObjC.unwrap(env.objectForKey('CLAUDEBOX_TEST_PASTEBOARD'));
const pasteboard = $.NSPasteboard.pasteboardWithName(pbName);
const value = pasteboard.stringForType($.NSPasteboardTypeString);
if (!value) {
  $.exit(1);
}
ObjC.unwrap(value);
JXA
}

start_clipboard_server() {
    log "Starting native clipboard bridge for private pasteboard $PASTEBOARD_NAME"
    CLAUDEBOX_CLIPBOARD_TOKEN="$TOKEN" \
        python3 "$ROOT_DIR/tooling/clipboard/macos_server.py" \
        --ready-file "$READY_FILE" \
        --pasteboard "$PASTEBOARD_NAME" \
        --host 127.0.0.1 \
        --port 0 \
        > "$SERVER_LOG" 2>&1 &
    SERVER_PID=$!

    local waited=0
    while [[ "$waited" -lt 100 ]]; do
        [[ -s "$READY_FILE" ]] && break
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            fail "clipboard server exited before writing ready file"
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    [[ -s "$READY_FILE" ]] || fail "clipboard server did not write ready file"

    CLAUDEBOX_CLIPBOARD_PORT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["port"])' "$READY_FILE")"
    export CLAUDEBOX_CLIPBOARD_PORT
    export CLAUDEBOX_CLIPBOARD_URL="http://host.docker.internal:$CLAUDEBOX_CLIPBOARD_PORT"
    export CLAUDEBOX_CLIPBOARD_TOKEN="$TOKEN"
    printf 'Clipboard bridge ready on private port %s with PID %s\n' "$CLAUDEBOX_CLIPBOARD_PORT" "$SERVER_PID"
}

write_fixture_image() {
    log "Building clipboard Docker fixture with production entrypoint and firewall"
    mkdir -p "$FIXTURE_CONTEXT"
    cp "$ROOT_DIR/build/docker-entrypoint" "$FIXTURE_CONTEXT/docker-entrypoint"
    cp "$ROOT_DIR/build/init-firewall" "$FIXTURE_CONTEXT/init-firewall"

    cat > "$FIXTURE_CONTEXT/init-firewall-wrapper" <<'STUB'
#!/usr/bin/env bash
set +e

bash -x /home/claude/init-firewall.real > /tmp/claudebox-init-firewall.log 2>&1
status=$?
printf '%s\n' "$status" > /workspace/firewall-status.txt
if [[ -f /tmp/claudebox-init-firewall.log ]]; then
    cp /tmp/claudebox-init-firewall.log /workspace/firewall-init.log
fi
iptables -S OUTPUT > /workspace/firewall-output-rules.txt 2>&1
iptables -S INPUT > /workspace/firewall-input-rules.txt 2>&1
getent ahostsv4 host.docker.internal | awk '{print $1}' | sort -u > /workspace/firewall-host-ips.txt 2>&1
exit "$status"
STUB
    chmod +x "$FIXTURE_CONTEXT/init-firewall-wrapper"

    cat > "$FIXTURE_CONTEXT/generate-tools-readme" <<'STUB'
#!/usr/bin/env bash
printf 'fixture tooling\n'
STUB
    chmod +x "$FIXTURE_CONTEXT/generate-tools-readme"

    cat > "$FIXTURE_CONTEXT/claude" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    clipboard-smoke)
        command -v xclip > /workspace/xclip-path.txt
        command -v wl-paste > /workspace/wl-paste-path.txt
        command -v wl-copy > /workspace/wl-copy-path.txt
        printf '%s\n' "${CLAUDEBOX_CLIPBOARD_URL:-}" > /workspace/bridge-url.txt
        printf '%s\n' "${CLAUDEBOX_CLIPBOARD_PORT:-}" > /workspace/bridge-port.txt
        printf '%s\n' "${DISPLAY:-}" > /workspace/display.txt
        xclip -selection clipboard -t TARGETS -o > /workspace/targets.txt
        wl-paste --type image/png > /workspace/from-clipboard.png
        printf 'bounded text from clipboard integration' | wl-copy
        ;;
    --version)
        printf 'claude clipboard fixture 1.0.0\n'
        ;;
    *)
        printf 'unsupported fixture args: %s\n' "$*" >&2
        exit 64
        ;;
esac
STUB
    chmod +x "$FIXTURE_CONTEXT/claude"

    cat > "$FIXTURE_CONTEXT/Dockerfile" <<'DOCKERFILE'
FROM debian:bookworm
ARG USER_ID
ARG GROUP_ID
RUN apt-get update && \
    apt-get install -y --no-install-recommends bash ca-certificates nodejs passwd util-linux iptables ipset && \
    rm -rf /var/lib/apt/lists/*
RUN groupadd -g ${GROUP_ID} claude 2>/dev/null || true && \
    useradd -m -u ${USER_ID} -g ${GROUP_ID} -s /bin/bash claude
COPY claude /usr/local/bin/claude
COPY generate-tools-readme /usr/local/bin/generate-tools-readme
COPY init-firewall /home/claude/init-firewall.real
COPY init-firewall-wrapper /home/claude/init-firewall
COPY docker-entrypoint /usr/local/bin/docker-entrypoint
RUN sed -i 's|DOCKERUSER|claude|g' /usr/local/bin/docker-entrypoint /home/claude/init-firewall /home/claude/init-firewall.real && \
    chmod +x /usr/local/bin/claude /usr/local/bin/generate-tools-readme /usr/local/bin/docker-entrypoint /home/claude/init-firewall /home/claude/init-firewall.real && \
    chown ${USER_ID}:${GROUP_ID} /home/claude/init-firewall /home/claude/init-firewall.real
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
DOCKERFILE

    docker build \
        --progress=plain \
        --build-arg USER_ID="$(id -u)" \
        --build-arg GROUP_ID="$(id -g)" \
        -f "$FIXTURE_CONTEXT/Dockerfile" \
        -t "$IMAGE_NAME" \
        "$FIXTURE_CONTEXT"
}

prepare_mounts() {
    mkdir -p "$WORKSPACE" "$PROJECT_PARENT" \
        "$PROJECT_SLOT/.claude" "$PROJECT_SLOT/.config" "$PROJECT_SLOT/.cache" \
        "$PROJECT_PARENT/.local/share/uv/python"
    printf '[profiles]\n' > "$PROJECT_PARENT/profiles.ini"
    printf '2' > "$PROJECT_PARENT/.project_container_counter"
}

run_clipboard_smoke() {
    local output_file="$SANDBOX/container.out"

    log "Running production launcher with controlled clipboard bridge"
    if ! (
        cd "$WORKSPACE"
        export HOME="$SANDBOX/home"
        export PROJECT_DIR="$WORKSPACE"
        export PROJECT_PARENT_DIR="$PROJECT_PARENT"
        export PROJECT_SLOT_DIR="$PROJECT_SLOT"
        export CLAUDEBOX_SCRIPT_DIR="$ROOT_DIR"
        export IMAGE_NAME
        export VERBOSE=false
        export CLAUDEBOX_WRAP_TMUX=false
        export CLAUDEBOX_CLIPBOARD=true
        export DISPLAY=:0
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
        source "$ROOT_DIR/lib/clipboard.sh"
        # shellcheck disable=SC1090,SC1091
        source "$ROOT_DIR/lib/docker.sh"
        run_claudebox_container "" "interactive" clipboard-smoke
    ) > "$output_file" 2>&1; then
        sed -n '1,180p' "$output_file" >&2
        fail "production launcher clipboard smoke failed"
    fi

    sed -n '1,180p' "$output_file"
}

assert_file_equals() {
    local path="$1"
    local expected="$2"
    local label="$3"

    [[ -f "$path" ]] || fail "$label was not written"
    if [[ "$(cat "$path")" != "$expected" ]]; then
        printf 'Expected %s: %s\n' "$label" "$expected" >&2
        printf 'Actual %s: %s\n' "$label" "$(cat "$path")" >&2
        fail "$label mismatch"
    fi
}

assert_firewall_state() {
    local rules_file="$WORKSPACE/firewall-output-rules.txt"
    local ips_file="$WORKSPACE/firewall-host-ips.txt"
    local ip

    [[ -f "$WORKSPACE/firewall-status.txt" ]] || fail "firewall init status was not recorded"
    if [[ "$(cat "$WORKSPACE/firewall-status.txt")" != "0" ]]; then
        printf 'Expected firewall init exit status: 0\n' >&2
        printf 'Actual firewall init exit status: %s\n' "$(cat "$WORKSPACE/firewall-status.txt")" >&2
        if [[ -f "$WORKSPACE/firewall-init.log" ]]; then
            printf '\nFirewall init log:\n' >&2
            sed -n '1,160p' "$WORKSPACE/firewall-init.log" >&2
        fi
        if [[ -f "$rules_file" ]]; then
            printf '\nRecorded OUTPUT rules:\n' >&2
            sed -n '1,160p' "$rules_file" >&2
        fi
        if [[ -f "$WORKSPACE/firewall-input-rules.txt" ]]; then
            printf '\nRecorded INPUT rules:\n' >&2
            sed -n '1,160p' "$WORKSPACE/firewall-input-rules.txt" >&2
        fi
        fail "firewall init did not complete successfully"
    fi
    [[ -f "$rules_file" ]] || fail "firewall OUTPUT rules were not recorded"
    [[ -f "$ips_file" ]] || fail "clipboard bridge host IPs were not recorded"
    grep -qx -- '-P OUTPUT DROP' "$rules_file" || fail "firewall OUTPUT policy is not DROP"
    if grep -qx -- '-P OUTPUT ACCEPT' "$rules_file"; then
        fail "firewall OUTPUT policy remained ACCEPT"
    fi
    [[ -s "$ips_file" ]] || fail "host.docker.internal did not resolve inside container"

    while IFS= read -r ip; do
        [[ -n "$ip" ]] || continue
        if ! grep -Eq -- "^-A OUTPUT -d ${ip}(/32)? -p tcp .* --dport ${EXPECTED_BRIDGE_PORT} -j ACCEPT$" "$rules_file"; then
            printf 'Expected firewall rule for %s TCP port %s\n' "$ip" "$EXPECTED_BRIDGE_PORT" >&2
            printf '\nRecorded OUTPUT rules:\n' >&2
            sed -n '1,120p' "$rules_file" >&2
            fail "clipboard firewall host/port allow rule is missing"
        fi
    done < "$ips_file"
}

log "Clipboard integration handle: $SESSION_ID"
configure_docker_access
docker info >/dev/null

EXPECTED_PNG="$SANDBOX/expected.png"
write_png_fixture "$EXPECTED_PNG"
write_private_pasteboard_png "$EXPECTED_PNG"
start_clipboard_server
EXPECTED_BRIDGE_PORT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["port"])' "$READY_FILE")"
EXPECTED_BRIDGE_URL="http://host.docker.internal:$EXPECTED_BRIDGE_PORT"
write_fixture_image
prepare_mounts
run_clipboard_smoke

cmp "$EXPECTED_PNG" "$WORKSPACE/from-clipboard.png" || fail "container did not retrieve exact private pasteboard PNG"
assert_file_equals "$WORKSPACE/xclip-path.txt" "/opt/claudebox-clipboard/xclip" "xclip shim path"
assert_file_equals "$WORKSPACE/wl-paste-path.txt" "/opt/claudebox-clipboard/wl-paste" "wl-paste shim path"
assert_file_equals "$WORKSPACE/wl-copy-path.txt" "/opt/claudebox-clipboard/wl-copy" "wl-copy shim path"
assert_file_equals "$WORKSPACE/targets.txt" "image/png" "clipboard target list"
assert_file_equals "$WORKSPACE/bridge-url.txt" "$EXPECTED_BRIDGE_URL" "clipboard bridge URL"
assert_file_equals "$WORKSPACE/bridge-port.txt" "$EXPECTED_BRIDGE_PORT" "clipboard bridge port"
assert_file_equals "$WORKSPACE/display.txt" ":0" "DISPLAY forwarding"
assert_firewall_state

copied_text="$(read_private_pasteboard_text)"
[[ "$copied_text" == "bounded text from clipboard integration" ]] ||
    fail "container wl-copy did not update private pasteboard text"

log "Clipboard integration checks passed"
