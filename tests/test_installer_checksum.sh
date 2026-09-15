#!/usr/bin/env bash
# Check both checksum backends against the actual installer header.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${1:-$ROOT_DIR/.builder/script_template_root.sh}"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/claudebox-checksum.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin" "$SANDBOX/home/.claudebox/source"
for tool in bash mkdir awk; do
    ln -s "$(command -v "$tool")" "$SANDBOX/bin/$tool"
done
awk '/^__ARCHIVE_BELOW__$/ {exit} {print}' "$TEMPLATE" > "$SANDBOX/installer"
printf 'printf "launched\\n"\n' > "$SANDBOX/home/.claudebox/source/main.sh"
printf 'cached archive\n' > "$SANDBOX/home/.claudebox/archive.tar.gz"
HASH="$(awk -F '"' '/^ARCHIVE_SHA256=/ {print $2}' "$SANDBOX/installer")"
export HASH
for backend in sha256sum shasum; do
    cat > "$SANDBOX/bin/$backend" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "${0##*/}" in
    sha256sum) test "$#" -eq 1 ;;
    shasum) test "$#" -eq 3; test "$1" = -a; test "$2" = 256; shift 2 ;;
esac
if [[ "$#" -ne 1 ]] || [[ ! -f "$1" ]]; then
    printf 'Invalid checksum arguments\n' >&2
    exit 1
fi
printf '%s  %s\n' "$HASH" "$1"
STUB
    chmod +x "$SANDBOX/bin/$backend"
    output="$(HOME="$SANDBOX/home" PATH="$SANDBOX/bin" "$BASH" "$SANDBOX/installer")"
    test "$output" = launched
    printf 'PASS: %s reuses a matching cached archive with correct arguments\n' "$backend"
    rm "$SANDBOX/bin/$backend"
done
