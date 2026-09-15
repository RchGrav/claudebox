#!/usr/bin/env bash
# Optional macOS clipboard bridge. The container launcher owns these processes.

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
    export CLAUDEBOX_CLIPBOARD_PORT
    export CLAUDEBOX_CLIPBOARD_URL="http://host.docker.internal:$CLAUDEBOX_CLIPBOARD_PORT"
}

clipboard_bridge_stop() {
    if [[ -n ${clipboard_pid:-} ]]; then
        kill "$clipboard_pid" 2>/dev/null || true
        wait "$clipboard_pid" 2>/dev/null || true
    fi
    if [[ -n ${clipboard_dir:-} ]]; then
        rm -rf -- "$clipboard_dir"
    fi
}

export -f clipboard_bridge_start clipboard_bridge_stop
