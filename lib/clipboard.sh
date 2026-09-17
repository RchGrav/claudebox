#!/usr/bin/env bash
# Optional macOS clipboard bridge. The container launcher owns these processes.

clipboard_bridge_pid_listens_on_port() {
    local pid="$1"
    local port="$2"

    command -v lsof >/dev/null 2>&1 || return 1
    lsof -nP -a -p "$pid" -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

clipboard_bridge_start() {
    if [[ ${HOST_OS:-} != macOS ]]; then
        printf 'ERROR: --clipboard currently requires macOS.\n' >&2
        return 1
    fi
    if ! command -v python3 >/dev/null || ! command -v osascript >/dev/null; then
        printf 'ERROR: --clipboard requires Python 3 and macOS osascript.\n' >&2
        return 1
    fi
    local clipboard_root="${CLAUDEBOX_HOME}/clipboard"
    mkdir -p "$clipboard_root" || return 1
    clipboard_dir=$(mktemp -d "$clipboard_root/session.XXXXXX") || return 1
    CLAUDEBOX_CLIPBOARD_TOKEN=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))') || return 1
    export CLAUDEBOX_CLIPBOARD_TOKEN
    python3 "${CLAUDEBOX_SCRIPT_DIR}/tooling/clipboard/macos_server.py" \
        --host 127.0.0.1 \
        --ready-file "$clipboard_dir/ready.json" \
        > "$clipboard_dir/server.log" 2>&1 &
    clipboard_pid=$!

    local attempt
    for ((attempt=0; attempt<200; attempt++)); do
        [[ -s "$clipboard_dir/ready.json" ]] && break
        if ! kill -0 "$clipboard_pid" 2>/dev/null; then
            printf 'ERROR: macOS clipboard bridge could not start.\n' >&2
            cat "$clipboard_dir/server.log" >&2
            return 1
        fi
        sleep 0.05
    done
    if [[ ! -s "$clipboard_dir/ready.json" ]]; then
        printf 'ERROR: macOS clipboard bridge startup timed out.\n' >&2
        cat "$clipboard_dir/server.log" >&2
        return 1
    fi
    CLAUDEBOX_CLIPBOARD_PORT=$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["port"]; assert isinstance(p,int) and 0<p<65536; print(p)' "$clipboard_dir/ready.json") || return 1
    if ! clipboard_bridge_pid_listens_on_port "$clipboard_pid" "$CLAUDEBOX_CLIPBOARD_PORT"; then
        printf 'ERROR: macOS clipboard bridge ready file did not match the launched server.\n' >&2
        cat "$clipboard_dir/server.log" >&2
        return 1
    fi
    export CLAUDEBOX_CLIPBOARD_PORT
    export CLAUDEBOX_CLIPBOARD_URL="http://host.docker.internal:$CLAUDEBOX_CLIPBOARD_PORT"
}

clipboard_bridge_stop() {
    if [[ -n ${clipboard_pid:-} ]]; then
        kill "$clipboard_pid" 2>/dev/null || true
        wait "$clipboard_pid" 2>/dev/null || true
        clipboard_pid=""
    fi
    if [[ -n ${clipboard_dir:-} ]]; then
        rm -rf -- "$clipboard_dir"
        clipboard_dir=""
    fi
}

clipboard_bridge_probe() {
    local bridge_url
    local bridge_token

    if [[ $# -ge 1 ]]; then
        bridge_url="${1:-}"
    else
        bridge_url="${CLAUDEBOX_CLIPBOARD_URL:-}"
    fi
    if [[ $# -ge 2 ]]; then
        bridge_token="${2:-}"
    else
        bridge_token="${CLAUDEBOX_CLIPBOARD_TOKEN:-}"
    fi

    [[ "$bridge_url" == http://host.docker.internal:* ]] || return 1
    [[ -n "$bridge_token" ]] || return 1

    local bridge_port="${bridge_url#http://host.docker.internal:}"
    if [[ ! "$bridge_port" =~ ^[0-9]{1,5}$ ]] || (( 10#$bridge_port < 1 )) || (( 10#$bridge_port > 65535 )); then
        return 1
    fi
    command -v python3 >/dev/null || return 1

    CLAUDEBOX_CLIPBOARD_PROBE_PORT="$bridge_port" \
    CLAUDEBOX_CLIPBOARD_PROBE_TOKEN="$bridge_token" \
        python3 - <<'PY'
import os
import sys
import urllib.error
import urllib.request

port = os.environ.get("CLAUDEBOX_CLIPBOARD_PROBE_PORT", "")
token = os.environ.get("CLAUDEBOX_CLIPBOARD_PROBE_TOKEN", "")

try:
    if not port.isdigit() or not (0 < int(port) < 65536) or not token:
        sys.exit(1)

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        NoRedirect,
    )
    request = urllib.request.Request("http://127.0.0.1:%s/health" % port)
    request.add_header("Authorization", "Bearer " + token)
    with opener.open(request, timeout=2) as response:
        sys.exit(0 if response.status == 204 else 1)
except (OSError, urllib.error.URLError, ValueError):
    sys.exit(1)
PY
}

export -f clipboard_bridge_pid_listens_on_port clipboard_bridge_start clipboard_bridge_stop clipboard_bridge_probe
