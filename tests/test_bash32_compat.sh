#!/bin/bash
# Test script for Bash 3.2 compatibility
# Run this with: bash test_bash32_compat.sh

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_runner.sh"

# Print header
print_test_header "ClaudeBox Bash Compatibility Test"

# Extract just the profile functions from config.sh
ROOT_DIR="$(dirname "$TEST_DIR")"
CONFIG_SCRIPT="$ROOT_DIR/lib/config.sh"
# Extract the profile functions - they start at get_profile_packages and end at profile_exists
# Include the entire profile_exists function by searching for the next function after it
PROFILE_FUNCS=$(sed -n '/^get_profile_packages()/,/^expand_profile()/p' "$CONFIG_SCRIPT" | sed '$d')

print_section "1. Testing profile functions"

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

print_section "2. Testing usage patterns from main script"

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

print_section "3. Testing Bash 3.2 specific issues"

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

# Print summary and exit with appropriate code
print_test_summary
exit $?
