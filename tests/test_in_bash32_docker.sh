#!/bin/bash
# Run ClaudeBox compatibility tests in actual Bash 3.2 using Docker
# Usage: ./test_in_bash32_docker.sh

echo "=========================================="
echo "Testing ClaudeBox in real Bash 3.2 Docker"
echo "=========================================="

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is required to run this test"
    exit 1
fi

# Pull Bash 3.2 image if needed
echo "Pulling Bash 3.2 Docker image..."
docker pull bash:3.2 >/dev/null 2>&1

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Run the test script in Bash 3.2
echo "Running tests in Bash 3.2..."
echo
docker run --rm \
    -v "$PARENT_DIR":/workspace \
    bash:3.2 \
    bash /workspace/tests/test_bash32_compat.sh

# Clean up the Bash 3.2 image
echo
echo "Cleaning up bash:3.2 image..."
docker rmi bash:3.2 >/dev/null 2>&1 || true
echo "Test complete."

# Also test with Bash 4+ for comparison
echo
echo "=========================================="
echo "Running same tests in Bash 4+ for comparison..."
echo "=========================================="
echo
echo "Running tests in Bash 4.0..."
echo
docker run --rm \
    -v "$PARENT_DIR":/workspace \
    bash:4.0 \
    bash /workspace/tests/test_bash32_compat.sh

echo
echo "Cleaning up bash:4.0 image..."
docker rmi bash:4.0 >/dev/null 2>&1 || true
echo "Test complete."
