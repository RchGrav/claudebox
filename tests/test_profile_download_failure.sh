#!/usr/bin/env bash
# Execute the generated DevOps RUN instruction under /bin/sh, as Docker does.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/claudebox-profile.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
source "$ROOT_DIR/lib/config.sh"
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/curl" <<'STUB'
#!/bin/sh
case "$*" in
    *get-helm-3*) exit 22 ;;
    *stable.txt*) printf 'v1.31.0\n' ;;
esac
STUB
cat > "$SANDBOX/bin/dpkg" <<'STUB'
#!/bin/sh
printf 'amd64\n'
STUB
# These commands are outside the failed-download behavior under test.
for tool in chmod unzip rm; do
    printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/bin/$tool"
done
chmod +x "$SANDBOX/bin/"*
command_text="$(get_profile_devops | sed -n '/^RUN ARCH=/,$p' | sed '1s/^RUN //')"
status=0
PATH="$SANDBOX/bin:$PATH" /bin/sh -c "$command_text" || status=$?
if [ "$status" -ne 22 ]; then
    printf 'FAIL: Helm download failure returned %s instead of 22\n' "$status"
    exit 1
fi
printf 'PASS: Helm download failure stops the generated Docker RUN instruction\n'
