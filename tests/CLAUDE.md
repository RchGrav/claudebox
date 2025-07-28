# tests/ Directory Documentation

This directory contains test scripts for ClaudeBox, focusing on compatibility and functionality verification.

## File Index and Key Information

### Test Scripts
- `test_bash32_compat.sh` - Tests for Bash 3.2 compatibility (crucial for macOS support)
- `test_in_bash32_docker.sh` - Runs compatibility tests in a Docker container with Bash 3.2
- `README.md` - Test documentation and running instructions

## Testing Philosophy

### Bash 3.2 Compatibility
The primary test focus is ensuring all scripts work with Bash 3.2 (default on macOS). Key checks:
- No associative arrays (`declare -A`)
- No uppercase expansion (`${var^^}`)
- No `-v` variable checks (`[[ -v var ]]`)
- Proper string comparison syntax
- Profile function compatibility

### Test Categories
1. **Syntax Compatibility** - Static checks for incompatible syntax
2. **Function Testing** - Dynamic tests of profile functions
3. **Strict Mode Testing** - Tests under `set -u` to catch undefined variables
4. **Docker Integration** - Tests that require Docker environment

## Running Tests

```bash
# Run compatibility tests locally
./tests/test_bash32_compat.sh

# Run in Bash 3.2 Docker environment
./tests/test_in_bash32_docker.sh
```

## Recent Test Additions

- Added checks for new profile system
- Updated paths after refactoring from monolithic to modular structure
- Added Docker environment tests

## Areas Needing Test Coverage

- Integration tests for multi-slot system
- Command syncing functionality
- Cross-platform compatibility beyond Bash version
- Error handling edge cases
- Performance regression tests