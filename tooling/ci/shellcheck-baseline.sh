#!/usr/bin/env bash
# Print the full ShellCheck report, fail on every ShellCheck error, and fail
# when non-error diagnostics exceed the checked-in baseline. This keeps existing
# debt visible without blocking CI on unrelated warning cleanup.
set -Eeuo pipefail
IFS=$'\n\t'

if [ "$#" -eq 0 ]; then
  printf 'usage: %s <shell files...>\n' "$0" >&2
  exit 2
fi

BASELINE_FILE="${SHELLCHECK_BASELINE:-tooling/ci/shellcheck-baseline.txt}"
if [ ! -f "$BASELINE_FILE" ]; then
  printf 'ShellCheck baseline not found: %s\n' "$BASELINE_FILE" >&2
  exit 2
fi

if [ "${SHELLCHECK_PRINT_FULL:-1}" != "0" ]; then
  shellcheck -x "$@" || true
fi

json_file="$(mktemp)"
trap 'rm -f "$json_file"' EXIT

status=0
shellcheck --format=json1 -x "$@" >"$json_file" || status=$?

python3 - "$BASELINE_FILE" "$json_file" <<'PY'
import collections
import json
import sys

baseline_path, json_path = sys.argv[1], sys.argv[2]

baseline = {}
with open(baseline_path, "r", encoding="utf-8") as handle:
    for line_number, line in enumerate(handle, 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) != 4:
            raise SystemExit(
                f"{baseline_path}:{line_number}: expected file|level|code|count"
            )
        file_name, level, code, count = parts
        baseline[(file_name, level, code)] = int(count)

with open(json_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

actual = collections.Counter(
    (comment["file"], comment["level"], f"SC{comment['code']}")
    for comment in data.get("comments", [])
)

errors = [
    (comment["file"], comment["line"], f"SC{comment['code']}", comment["message"])
    for comment in data.get("comments", [])
    if comment["level"] == "error"
]
if errors:
    print("\nShellCheck errors must be fixed:")
    for file_name, line, code, message in errors:
        print(f"  {file_name}:{line}: {code}: {message}")
    raise SystemExit(1)

violations = []
for key, count in sorted(actual.items()):
    if key[1] == "error":
        continue
    allowed = baseline.get(key, 0)
    if count > allowed:
        violations.append((key, allowed, count))

if violations:
    print("\nNew ShellCheck diagnostics above baseline:")
    for (file_name, level, code), allowed, count in violations:
        print(f"  {file_name}|{level}|{code}: allowed {allowed}, found {count}")
    raise SystemExit(1)

reduced = [
    (key, allowed, actual.get(key, 0))
    for key, allowed in sorted(baseline.items())
    if actual.get(key, 0) < allowed
]
print(
    f"\nShellCheck baseline OK: {sum(actual.values())} diagnostics, "
    "no counts above baseline."
)
if reduced:
    print("Baseline can be reduced for:")
    for (file_name, level, code), allowed, count in reduced:
        print(f"  {file_name}|{level}|{code}: baseline {allowed}, found {count}")
PY

if [ "$status" -gt 1 ]; then
  exit "$status"
fi
