#!/usr/bin/env bash
# Exercise the entrypoint's real Python-tool installation block without a container.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/claudebox-python-status.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
export VENV_DIR="$SANDBOX/venv" PYDEV_FLAG="$SANDBOX/deployed"
export python_packages='fixture-package'
mkdir -p "$VENV_DIR/bin" "$SANDBOX/bin"
printf ':\n' > "$VENV_DIR/bin/activate"
cat > "$SANDBOX/bin/runuser" <<'STUB'
#!/usr/bin/env bash
shift 3
exec "$@"
STUB
cat > "$SANDBOX/bin/uv" <<'STUB'
#!/usr/bin/env bash
exit "${UV_STATUS:-0}"
STUB
chmod +x "$SANDBOX/bin/runuser" "$SANDBOX/bin/uv"
export PATH="$SANDBOX/bin:$PATH"
{
    printf 'set -euo pipefail\n'
    awk '
        /^                # Remove duplicates and install/ {capture=1}
        capture {print}
        capture && /^                fi$/ {exit}
    ' "$ROOT_DIR/build/docker-entrypoint"
} > "$SANDBOX/install.sh"

UV_STATUS=17 "$BASH" "$SANDBOX/install.sh"
if [[ -e "$PYDEV_FLAG" ]]; then
    printf 'FAIL: failed Python-tool installation wrote its completion flag\n' >&2
    exit 1
fi
printf 'PASS: failed Python-tool installation leaves completion flag absent\n'
UV_STATUS=0 "$BASH" "$SANDBOX/install.sh"
test -f "$PYDEV_FLAG"
printf 'PASS: successful Python-tool installation writes completion flag\n'
