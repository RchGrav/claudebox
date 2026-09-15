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

## macOS Testing

These tests are particularly important for macOS users, as macOS ships with Bash 3.2 by default. The Docker test ensures compatibility without needing access to a Mac.