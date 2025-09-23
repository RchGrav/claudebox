#!/bin/bash
# Run ClaudeBox installation tests using Docker
# Usage: ./test_install.sh

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_runner.sh"
PARENT_DIR="$(dirname "$TEST_DIR")"

print_test_header "ClaudeBox Docker Build/Install - 3.2"
test_docker_build_install_bash32() {
    docker run --rm \
        -v "$PARENT_DIR":/workspace \
        -w /workspace \
        bash:3.2 \
        bash tests/docker_test_build.sh
}
run_test "Build and install in Bash 3.2" test_docker_build_install_bash32

print_test_header "ClaudeBox Docker Build/Install - 4.0"
test_docker_build_install_bash4() {
    docker run --rm \
        -v "$PARENT_DIR":/workspace \
        -w /workspace \
        bash:4.0 \
        bash tests/docker_test_build.sh
}
run_test "Build and install in Bash 4.0" test_docker_build_install_bash4

print_test_header "ClaudeBox Docker Build/Install - 5.0"
test_docker_build_install_bash5() {
    docker run --rm \
        -v "$PARENT_DIR":/workspace \
        -w /workspace \
        bash:5.0 \
        bash tests/docker_test_build.sh
}
run_test "Build and install in Bash 5.0" test_docker_build_install_bash5

docker rmi bash:3.2 >/dev/null 2>&1 || true
docker rmi bash:4.0 >/dev/null 2>&1 || true
docker rmi bash:5.0 >/dev/null 2>&1 || true

print_test_summary
exit $?
