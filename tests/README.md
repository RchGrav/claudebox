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
after add and remove. Any `unbound variable` in the output fails the case. Guards issues #71 and #90 (empty arrays under `set -u` on Bash 3.2).

**Usage:**
```bash
cd tests
./test_cli_bash32.sh
```

### test_in_bash32_docker.sh
Runs the compatibility, CLI, shell failure-status, Python deployment-status, console-output, and installer-checksum tests in actual Bash 3.2 using Docker, then again with your local Bash version. Exits non-zero if any run fails.

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

## macOS Testing

These tests are particularly important for macOS users, as macOS ships with Bash 3.2 by default. The Docker test ensures compatibility without needing access to a Mac.

## ShellCheck

From the repository root, run the same command as CI:

```bash
shellcheck -x main.sh lib/*.sh .builder/*.sh \
  build/docker-entrypoint build/init-firewall build/generate-tools-readme \
  tests/*.sh tooling/profiles/*.sh
```

The command checks every shell script, including builder templates and test scripts,
without lowering severity or excluding diagnostic codes globally. Source directives
identify dynamically loaded libraries. Narrow annotations identify cross-module
constants, nested EXIT callbacks, child-shell expressions, and installer archive markers.

## Regression suites

Run the non-Docker suites from the repository root:

```bash
for script in test_bash32_compat test_cli_bash32 test_runtime_regressions \
  test_profile_download_failure test_dockerfile_template test_shell_robustness \
  test_python_install_status test_shell_output test_installer_checksum; do
  bash "tests/$script.sh" || exit "$?"
done
```

The additional suites cover failed command substitutions, Python installation completion
flags, rendered multi-profile output, and both `sha256sum` and `shasum -a 256` installer
backends. Dockerfile assertions fail explicitly on unresolved placeholders. Runtime tests
use a Docker boundary stub; they do not replace full image integration testing.

`test_installer_checksum.sh` accepts an installer path as its first argument. From a
packaged source archive, pass the corresponding `claudebox.run`, since builder templates
are not included in that archive.
