#!/bin/bash
# Reusable test runner for ClaudeBox tests
# Source this file to use the test framework

# Colors (Bash 3.2 compatible)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0

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

print_test_summary() {
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
        return 0
    else
        echo -e "${RED}Some tests failed ✗${NC}"
        return 1
    fi
}

print_test_header() {
    local title="$1"
    echo "======================================"
    echo "$title"
    echo "======================================"
    echo
}

print_section() {
    local section="$1"
    echo
    echo "$section"
    echo "$(echo "$section" | sed 's/./-/g')"
}
