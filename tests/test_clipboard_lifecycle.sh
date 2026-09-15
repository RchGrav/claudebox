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

status=0
# shellcheck disable=SC2016
env HOME="$TEST_ROOT/home" ROOT_DIR="$ROOT_DIR" TEST_ROOT="$TEST_ROOT" \
    "$BASH" -c '
    set -euo pipefail
    source "$ROOT_DIR/lib/clipboard.sh"
    export CLAUDEBOX_SCRIPT_DIR="$ROOT_DIR" CLAUDEBOX_HOME="$TEST_ROOT/home/.claudebox" HOST_OS=macOS
    redirect_pid=""
    trap '\''[[ -n ${redirect_pid:-} ]] && kill "$redirect_pid" 2>/dev/null || true; clipboard_bridge_stop'\'' EXIT
    clipboard_bridge_start
    bridge_url="$CLAUDEBOX_CLIPBOARD_URL"
    bridge_token="$CLAUDEBOX_CLIPBOARD_TOKEN"
    HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 \
        clipboard_bridge_probe "$bridge_url" "$bridge_token"
    export CLAUDEBOX_CLIPBOARD_URL="$bridge_url" CLAUDEBOX_CLIPBOARD_TOKEN="$bridge_token"
    ! clipboard_bridge_probe "" "$bridge_token"
    ! clipboard_bridge_probe "$bridge_url" ""
    ! clipboard_bridge_probe "http://127.0.0.1:${CLAUDEBOX_CLIPBOARD_PORT}" "$bridge_token"
    ! clipboard_bridge_probe "http://host.docker.internal:999999" "$bridge_token"

    redirect_port_file="$TEST_ROOT/redirect-port"
    redirect_token="redirect-token"
    REDIRECT_TOKEN="$redirect_token" python3 - "$redirect_port_file" <<'\''PY'\'' &
import http.server
import os
import sys

ready = sys.argv[1]
token = os.environ["REDIRECT_TOKEN"]

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format, *_args):
        return

    def do_GET(self):
        if self.headers.get("Authorization", "") != "Bearer " + token:
            self.send_response(401)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/health":
            self.send_response(302)
            self.send_header("Location", "/ok")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/ok":
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(ready, "w", encoding="utf-8") as handle:
    handle.write(str(server.server_address[1]))
server.serve_forever()
PY
    redirect_pid=$!
    for _attempt in 1 2 3 4 5 6 7 8 9 10; do
        [[ -s "$redirect_port_file" ]] && break
        sleep 0.05
    done
    redirect_port=$(cat "$redirect_port_file")
    ! clipboard_bridge_probe "http://host.docker.internal:$redirect_port" "$redirect_token"
    kill "$redirect_pid" 2>/dev/null || true
    wait "$redirect_pid" 2>/dev/null || true
    redirect_pid=""

    clipboard_bridge_stop
    ! clipboard_bridge_probe "$bridge_url" "$bridge_token"
    ' > "$TEST_ROOT/probe-output" 2>&1 || status=$?
if [[ $status != 0 ]]; then
    cat "$TEST_ROOT/probe-output"
    printf 'FAIL: clipboard health probe did not distinguish live and dead bridge\n'
    exit 1
fi
printf 'PASS: clipboard health probe distinguishes live and dead bridge\n'

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
