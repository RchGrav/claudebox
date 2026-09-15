# ClaudeBox Tests

This directory contains test scripts to verify ClaudeBox compatibility across different Bash versions.

## Test Scripts

### test_bash32_compat.sh
A comprehensive test suite that verifies Bash 3.2 compatibility by checking:
- All profile functions work correctly
- Usage patterns from the main script
- No Bash 4+ specific syntax is used
- Everything works with `set -u` (strict mode)

**Usage:**
```bash
cd tests
./test_bash32_compat.sh
```

### test_cli_bash32.sh
Drives `main.sh` end to end with an empty HOME, the way a fresh install is used:
no arguments, `help`, `profiles`, `--verbose profiles`, `slots`, `projects`,
`create`, `add python`, `remove python`, and checks the project's profiles.ini
after add and remove. It also starts with saved flags and no arguments. Any
`unbound variable` in the output fails the case. Guards issues #71 and #90
(empty arrays under `set -u` on Bash 3.2). Child CLI processes use the same
Bash executable as the test runner.

**Usage:**
```bash
cd tests
./test_cli_bash32.sh
```

### test_in_bash32_docker.sh
Runs both test scripts in actual Bash 3.2 using Docker, then again with your local Bash version. Exits non-zero if any run fails.

**Requirements:** Docker must be installed

**Usage:**
```bash
cd tests
./test_in_bash32_docker.sh
```

## Test Coverage

The test suite covers:

1. **Profile Functions**
   - `get_profile_packages()`
   - `get_profile_description()`
   - `get_all_profile_names()`
   - `profile_exists()`

2. **Usage Patterns**
   - Profile listing (as used in `claudebox profiles`)
   - Dockerfile generation patterns
   - Empty profile handling
   - Invalid profile handling

3. **Bash 3.2 Compatibility**
   - No associative arrays (`declare -A`)
   - No `${var^^}` uppercase expansion
   - No `[[ -v` variable checking
   - Works with `set -u` (strict mode)

## Expected Results

All tests in both scripts should pass in both Bash 3.2 and modern Bash versions.

## Runtime and portability regressions

Run these from the repository root with `/bin/bash` to use macOS's system Bash:

```bash
/bin/bash tests/test_command_sync.sh
/bin/bash tests/test_docker_runtime.sh
/bin/bash tests/test_dockerfile_generation.sh
/bin/bash tests/test_runtime_regressions.sh
/bin/bash tests/test_profile_download_failure.sh
/bin/bash tests/test_dockerfile_template.sh
```

These tests use temporary directories and do not need a Docker daemon. Runtime
tests require `jq`. They exercise real CLI helpers, file generation, and cleanup
while replacing the Docker command at the process boundary. The command-sync
test excludes `sha256sum` from its test PATH to verify the macOS `shasum` fallback,
including changed content and filenames with spaces.

CI runs the portable suites on Linux and macOS, including the installed artifact.
ShellCheck errors fail CI. Existing non-error diagnostics remain visible and are
limited by `tooling/ci/shellcheck-baseline.txt`; newly added diagnostics fail CI.

The clipboard protocol tests use only Python and Node standard libraries:

```bash
python3 -m unittest discover -s tests -p test_clipboard_server.py
node --test tests/test_clipboard_client.js
/bin/bash tests/test_clipboard_lifecycle.sh
/bin/bash tests/test_clipboard_firewall.sh
/bin/bash tests/test_slot_selection.sh
```

`test_container_integration.sh` runs the production entrypoint and host mount
builder against real Docker containers, checking Python persistence across runs
and slots. It downloads a Debian/uv fixture and needs a working Docker daemon.
Its Claude command is a fixture; it does not authenticate with Anthropic.

## macOS Testing

These tests are particularly important for macOS users, as macOS ships with Bash 3.2 by default. The Docker test ensures compatibility without needing access to a Mac.
