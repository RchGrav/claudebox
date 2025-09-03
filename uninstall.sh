#!/bin/bash
#
# ClaudeBox Uninstaller Script
# Completely removes ClaudeBox and all associated files from your system
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "       ClaudeBox Uninstaller"
echo "========================================="
echo ""

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "  $1"
}

# Track if anything was removed
REMOVED_SOMETHING=false

# 1. Remove symlink
echo "Checking for ClaudeBox symlink..."
if [ -L "$HOME/.local/bin/claudebox" ]; then
    rm -f "$HOME/.local/bin/claudebox"
    print_success "Removed symlink from ~/.local/bin/claudebox"
    REMOVED_SOMETHING=true
else
    print_info "No symlink found at ~/.local/bin/claudebox"
fi

# 2. Remove main installation directory
echo ""
echo "Checking for ClaudeBox installation directory..."
if [ -d "$HOME/.claudebox" ]; then
    rm -rf "$HOME/.claudebox"
    print_success "Removed installation directory ~/.claudebox"
    REMOVED_SOMETHING=true
else
    print_info "No installation directory found at ~/.claudebox"
fi

# 3. Check for project-specific directories
echo ""
echo "Checking for project-specific ClaudeBox directories..."
PROJECT_DIRS=$(find "$HOME" -maxdepth 1 -type d -name ".claudebox-*" 2>/dev/null || true)
if [ -n "$PROJECT_DIRS" ]; then
    echo "$PROJECT_DIRS" | while read -r dir; do
        rm -rf "$dir"
        print_success "Removed project directory: $dir"
        REMOVED_SOMETHING=true
    done
else
    print_info "No project-specific directories found"
fi

# 4. Check for Docker containers and images
echo ""
echo "Checking for ClaudeBox Docker resources..."

# Check if Docker is installed and running
if command -v docker &> /dev/null && docker info &> /dev/null; then
    # Check for containers
    CONTAINERS=$(docker ps -a --format "{{.ID}} {{.Names}}" | grep -i claudebox | awk '{print $1}' 2>/dev/null || true)
    if [ -n "$CONTAINERS" ]; then
        print_warning "Found ClaudeBox Docker containers. Removing..."
        echo "$CONTAINERS" | while read -r container; do
            docker rm -f "$container" &>/dev/null
            print_success "Removed container: $container"
            REMOVED_SOMETHING=true
        done
    else
        print_info "No ClaudeBox Docker containers found"
    fi
    
    # Check for images
    IMAGES=$(docker images --format "{{.ID}} {{.Repository}}" | grep -i claudebox | awk '{print $1}' 2>/dev/null || true)
    if [ -n "$IMAGES" ]; then
        print_warning "Found ClaudeBox Docker images. Removing..."
        echo "$IMAGES" | while read -r image; do
            docker rmi -f "$image" &>/dev/null
            print_success "Removed image: $image"
            REMOVED_SOMETHING=true
        done
    else
        print_info "No ClaudeBox Docker images found"
    fi
else
    print_info "Docker not running or not installed - skipping Docker cleanup"
fi

# 5. Check PATH configuration
echo ""
echo "Checking PATH configuration..."
if echo "$PATH" | grep -q "$HOME/.local/bin"; then
    print_warning "~/.local/bin is in your PATH"
    print_info "If you added this only for ClaudeBox, you may want to remove it from:"
    print_info "  ~/.bashrc, ~/.zshrc, or ~/.bash_profile"
else
    print_info "~/.local/bin is not in your PATH"
fi

# 6. Final summary
echo ""
echo "========================================="
if [ "$REMOVED_SOMETHING" = true ]; then
    print_success "ClaudeBox has been uninstalled successfully!"
else
    print_info "ClaudeBox was not installed or already removed."
fi
echo "========================================="

# Optional: Ask about removing the installer file
if [ -f "claudebox.run" ]; then
    echo ""
    read -p "Remove the claudebox.run installer file? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f claudebox.run
        print_success "Removed claudebox.run installer"
    fi
fi

echo ""
echo "Uninstall complete!"