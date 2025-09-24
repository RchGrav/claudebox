#!/bin/bash
set -euo pipefail

# Check if info argument is provided
if [ "${1:-}" = "info" ]; then
    echo "Rust"
    echo "Rust Development (installed via rustup)"
    exit 0
fi

# Set Rust installation directories
export RUSTUP_HOME="$HOME/.claudebox/.rustup"
export CARGO_HOME="$HOME/.claudebox/.cargo"
export PATH="$CARGO_HOME/bin:$PATH"

# Install rustup if not already installed
if [ ! -f "$CARGO_HOME/bin/rustup" ]; then
    echo "Installing Rust toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi

# Source the environment
source "$CARGO_HOME/env"

# Install components
echo "Installing Rust components..."
rustup component add rust-src rust-analyzer clippy rustfmt llvm-tools-preview

# Install cargo extensions
echo "Installing cargo extensions..."
CARGO_TOOLS=(
    "cargo-edit"
    "cargo-watch"
    "cargo-expand"
    "cargo-outdated"
    "cargo-audit"
    "cargo-deny"
    "cargo-tree"
    "cargo-bloat"
    "cargo-flamegraph"
    "cargo-tarpaulin"
    "cargo-criterion"
    "cargo-release"
    "cargo-make"
    "sccache"
    "bacon"
    "just"
    "tokei"
    "hyperfine"
)

for tool in "${CARGO_TOOLS[@]:-}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Installing $tool..."
        cargo install "$tool"
    else
        echo "$tool already installed"
    fi
done

echo "Rust development environment installed in ~/.claudebox"