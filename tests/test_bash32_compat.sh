#!/bin/bash
# Test script for Bash 3.2 compatibility
# Run this with: bash test_bash32_compat.sh

echo "======================================"
echo "ClaudeBox Bash 3.2 Compatibility Test"
echo "======================================"
echo "Current Bash version: $BASH_VERSION"
echo

# Colors (these should work in Bash 3.2)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

# Test function
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test $TESTS_RUN: $test_name... "
    
    if eval "$test_cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Error output:"
        eval "$test_cmd" 2>&1 | sed 's/^/    /'
        return 1
    fi
}

# Extract just the profile functions from config.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$TEST_DIR")"
CONFIG_SCRIPT="$ROOT_DIR/lib/config.sh"
# Extract the profile functions - they start at get_profile_packages and end at profile_exists
# Include the entire profile_exists function by searching for the next function after it
PROFILE_FUNCS=$(sed -n '/^get_profile_packages()/,/^expand_profile()/p' "$CONFIG_SCRIPT" | sed '$d')

echo "1. Testing profile functions"
echo "----------------------------"

# Test 1: Basic function sourcing
test_basic_sourcing() {
    eval "$PROFILE_FUNCS"
    type get_profile_packages >/dev/null 2>&1
}
run_test "Source profile functions" test_basic_sourcing

# Test 2: get_profile_packages
test_get_packages() {
    eval "$PROFILE_FUNCS"
    local result=$(get_profile_packages "core")
    [[ -n "$result" ]] && [[ "$result" == *"gcc"* ]]
}
run_test "get_profile_packages()" test_get_packages

# Test 3: get_profile_description
test_get_description() {
    eval "$PROFILE_FUNCS"
    local result=$(get_profile_description "python")
    [[ "$result" == "Python Development (managed via uv)" ]]
}
run_test "get_profile_description()" test_get_description

# Test 4: get_all_profile_names
test_get_all_names() {
    eval "$PROFILE_FUNCS"
    local result=$(get_all_profile_names)
    local count=$(echo "$result" | wc -w)
    [[ $count -eq 21 ]]
}
run_test "get_all_profile_names()" test_get_all_names

# Test 5: profile_exists
test_profile_exists() {
    eval "$PROFILE_FUNCS"
    profile_exists "core" && ! profile_exists "invalid"
}
run_test "profile_exists()" test_profile_exists

echo
echo "2. Testing usage patterns from main script"
echo "------------------------------------------"

# Test 6: Pattern used in profiles command
test_profiles_pattern() {
    eval "$PROFILE_FUNCS"
    local output=""
    for profile in $(get_all_profile_names | tr ' ' '\n' | sort); do
        local desc=$(get_profile_description "$profile")
        output="${output}${profile} - ${desc}\n"
    done
    [[ -n "$output" ]]
}
run_test "Profiles listing pattern" test_profiles_pattern

# Test 7: Pattern used in dockerfile generation
test_dockerfile_pattern() {
    eval "$PROFILE_FUNCS"
    local profile="core"
    local packages=$(get_profile_packages "$profile")
    local pkg_list
    IFS=' ' read -ra pkg_list <<< "$packages"
    [[ ${#pkg_list[@]} -gt 0 ]]
}
run_test "Dockerfile generation pattern" test_dockerfile_pattern

# Test 8: Empty profile handling
test_empty_profile() {
    eval "$PROFILE_FUNCS"
    local packages=$(get_profile_packages "python")
    [[ -z "$packages" ]]
}
run_test "Empty profile handling" test_empty_profile

# Test 9: Invalid profile handling
test_invalid_profile() {
    eval "$PROFILE_FUNCS"
    local packages=$(get_profile_packages "nonexistent")
    [[ -z "$packages" ]]
}
run_test "Invalid profile handling" test_invalid_profile

echo
echo "3. Testing Bash 3.2 specific issues"
echo "-----------------------------------"

# Test 10: No associative arrays
test_no_associative_arrays() {
    ! grep -q "declare -A" "$CONFIG_SCRIPT"
}
run_test "No associative arrays" test_no_associative_arrays

# Test 11: No ${var^^} uppercase
test_no_uppercase_expansion() {
    ! grep -q '\${[^}]*\^\^}' "$CONFIG_SCRIPT"
}
run_test "No \${var^^} syntax" test_no_uppercase_expansion

# Test 12: No [[ -v syntax
test_no_v_syntax() {
    ! grep -q '\[\[ -v ' "$CONFIG_SCRIPT"
}
run_test "No [[ -v syntax" test_no_v_syntax

echo
echo "4. Testing with set -u (strict mode)"
echo "------------------------------------"

# Test 13: Functions work with set -u
test_with_set_u() {
    (
        set -u
        eval "$PROFILE_FUNCS"
        get_profile_packages "core" >/dev/null
        get_profile_description "python" >/dev/null
        profile_exists "rust"
    )
}
run_test "Functions work with set -u" test_with_set_u

echo
echo "======================================"
echo "Test Summary"
echo "======================================"
echo "Tests run: $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${NC}"
echo

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
    echo "The script should work with Bash 3.2"
    exit 0
else
    echo -e "${RED}Some tests failed ✗${NC}"
    echo "There may be compatibility issues"
    exit 1
fi
