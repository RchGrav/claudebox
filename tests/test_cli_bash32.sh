#!/usr/bin/env bash
# Drives main.sh end to end with an empty HOME and no arguments, the way a
# fresh install is used. Run it under real Bash 3.2 via test_in_bash32_docker.sh.
# Guards issues #71 and #90: empty arrays under set -u aborted the CLI parser.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$TEST_DIR")"
MAIN="$ROOT_DIR/main.sh"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/claudebox-cli-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
mkdir -p "$HOME/.local/bin" "$SANDBOX/project"
export PATH="$HOME/.local/bin:$PATH"
cd "$SANDBOX/project"

# add/remove run the Docker preflight before touching the profile file.
# A stub that answers "info" and "--version" lets them reach that code
# without a daemon; every other docker call fails as it would offline.
cat > "$HOME/.local/bin/docker" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
    info|ps|image|--version|version) exit 0 ;;
    *) exit 1 ;;
esac
STUB
chmod +x "$HOME/.local/bin/docker"

TESTS_RUN=0
TESTS_PASSED=0

printf 'ClaudeBox CLI test under Bash %s\n\n' "$BASH_VERSION"

# run_case <name> <expect_exit_zero:yes|no> [args...]
# Every case fails on "unbound variable" in the output. Cases marked "yes"
# also require exit status 0.
run_case() {
    local name="$1"
    local expect_zero="$2"
    shift 2
    local output=""
    local status=0

    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'Test %d: %s... ' "$TESTS_RUN" "$name"

    output="$(bash "$MAIN" "$@" 2>&1 </dev/null)"
    status=$?

    if printf '%s' "$output" | grep -q 'unbound variable'; then
        printf 'FAIL (unbound variable)\n'
        printf '%s\n' "$output" | grep 'unbound variable' | sed 's/^/    /'
        return 0
    fi
    if [ "$expect_zero" = "yes" ] && [ "$status" -ne 0 ]; then
        printf 'FAIL (exit %d)\n' "$status"
        printf '%s\n' "$output" | tail -5 | sed 's/^/    /'
        return 0
    fi
    printf 'PASS\n'
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

# check_profile_file <name> grep|not_grep <pattern>
# Asserts on the project's profiles.ini that add/remove write.
check_profile_file() {
    local name="$1"
    local mode="$2"
    local pattern="$3"
    local file=""

    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'Test %d: %s... ' "$TESTS_RUN" "$name"

    file="$(find "$HOME/.claudebox/projects" -name profiles.ini 2>/dev/null | head -1)"
    if [ -z "$file" ]; then
        printf 'FAIL (no profiles.ini under %s)\n' "$HOME/.claudebox/projects"
        return 0
    fi
    if [ "$mode" = "grep" ]; then
        if grep -q "$pattern" "$file"; then
            printf 'PASS\n'
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            printf 'FAIL (%s not in %s)\n' "$pattern" "$file"
        fi
    else
        if grep -q "$pattern" "$file"; then
            printf 'FAIL (%s still in %s)\n' "$pattern" "$file"
        else
            printf 'PASS\n'
            TESTS_PASSED=$((TESTS_PASSED + 1))
        fi
    fi
}

# First run only updates the symlink and prints PATH advice; do it once so
# the cases below reach the CLI parser.
bash "$MAIN" help >/dev/null 2>&1 </dev/null || true

run_case "no arguments"        no
run_case "help"                yes help
run_case "profiles"            yes profiles
run_case "--verbose profiles"  yes --verbose profiles
run_case "slots"               yes slots
run_case "projects"            yes projects
run_case "create"              yes create
run_case "add python"          yes add python
run_case "profiles after add"  yes profiles
check_profile_file "python listed after add" grep '^python$'
run_case "remove python"       yes remove python
check_profile_file "python gone after remove" not_grep '^python$'

printf '\n%d/%d passed\n' "$TESTS_PASSED" "$TESTS_RUN"
if [ "$TESTS_PASSED" -ne "$TESTS_RUN" ]; then
    exit 1
fi
