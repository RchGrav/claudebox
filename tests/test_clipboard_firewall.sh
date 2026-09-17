#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudebox-clipboard-firewall.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
# Load the production rule helper without executing privileged firewall setup.
eval "$(sed -n '/^allow_clipboard_bridge()/,/^}/p' "$ROOT_DIR/build/init-firewall")"
# shellcheck disable=SC2317,SC2329
getent() { printf '192.168.5.2 STREAM host.docker.internal\n192.168.5.2 DGRAM\n'; }
# shellcheck disable=SC2317,SC2329
iptables() {
    local args="$1"
    shift || true
    while [ "$#" -gt 0 ]; do
        args="$args $1"
        shift
    done
    printf '%s\n' "$args" >> "$TEST_ROOT/rules"
}
export CLAUDEBOX_CLIPBOARD_URL="" CLAUDEBOX_CLIPBOARD_TOKEN="" CLAUDEBOX_CLIPBOARD_PORT=""
allow_clipboard_bridge
[[ ! -e "$TEST_ROOT/rules" ]]
export CLAUDEBOX_CLIPBOARD_URL=http://host.docker.internal:30456 CLAUDEBOX_CLIPBOARD_PORT=30456 CLAUDEBOX_CLIPBOARD_TOKEN=fixture-token
allow_clipboard_bridge
[[ $(cat "$TEST_ROOT/rules") == '-A OUTPUT -p tcp -d 192.168.5.2 --dport 30456 -j ACCEPT' ]]
export CLAUDEBOX_CLIPBOARD_PORT='30456:65535'
if allow_clipboard_bridge; then
    printf 'FAIL: invalid clipboard port accepted\n'; exit 1
fi
[[ $(wc -l < "$TEST_ROOT/rules" | tr -d ' ') == 1 ]]
printf 'PASS: clipboard firewall access is limited to one host TCP port and opt-in\n'

# Run the full production script with privileged/network boundaries stubbed.
# A missing default-domain DNS record must not prevent restrictive policy setup.
export ROOT_DIR TEST_ROOT
# shellcheck disable=SC2016
"$BASH" -c '
    set -Eeuo pipefail
    IFS=$'"'"'\n\t'"'"'
    iptables() {
        local args="$1"
        shift || true
        while [ "$#" -gt 0 ]; do
            args="$args $1"
            shift
        done
        printf "%s\n" "$args" >> "$TEST_ROOT/full-rules"
    }
    ipset() { :; }
    getent() { return 2; }
    rm() { :; }
    export CLAUDEBOX_CLIPBOARD_URL="" DISABLE_FIREWALL=false
    source "$ROOT_DIR/build/init-firewall"
'
[[ $(sed -n '1p' "$TEST_ROOT/full-rules") == '-P OUTPUT DROP' ]]
[[ $(sed -n '2p' "$TEST_ROOT/full-rules") == '-P INPUT DROP' ]]
printf 'PASS: unavailable allowlist DNS cannot leave default policies open\n'

printf '#!/bin/bash\nexit 23\n' > "$TEST_ROOT/init-firewall"
chmod +x "$TEST_ROOT/init-firewall"
entrypoint_guard=$(sed -n '/^if \[ -f \/home\/DOCKERUSER\/init-firewall \]; then$/,/^fi$/p' "$ROOT_DIR/build/docker-entrypoint")
entrypoint_guard=${entrypoint_guard//\/home\/DOCKERUSER/$TEST_ROOT}
status=0
"$BASH" -c "$entrypoint_guard" > "$TEST_ROOT/entrypoint-output" 2>&1 || status=$?
[[ $status == 1 ]]
grep -q 'Firewall setup failed' "$TEST_ROOT/entrypoint-output"
printf 'PASS: entrypoint refuses to continue after firewall failure\n'
