#!/usr/bin/env bash
# Rust profile for ClaudeBox
set -euo pipefail

case "${1:-}" in
    info)
        printf '%s|%s\n' "rust" "Rust Development (installed via rustup)"
        ;;
    packages)
        # Rust doesn't need apt packages, installed via rustup
        printf '%s\n' ""
        ;;
    dockerfile)
        cat << 'EOF'
# Install Rust via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
ENV PATH="/home/claude/.cargo/bin:$PATH"
ENV RUSTUP_HOME="/home/claude/.rustup"
ENV CARGO_HOME="/home/claude/.cargo"

# Install Rust components
RUN /home/claude/.cargo/bin/rustup component add rust-src rust-analyzer clippy rustfmt llvm-tools-preview

# Install essential cargo tools
RUN /home/claude/.cargo/bin/cargo install \
    cargo-edit \
    cargo-watch \
    cargo-expand \
    cargo-outdated \
    cargo-audit \
    cargo-deny \
    cargo-tree \
    cargo-bloat \
    cargo-flamegraph \
    cargo-tarpaulin \
    cargo-criterion \
    cargo-release \
    cargo-make \
    sccache \
    bacon \
    just \
    tokei \
    hyperfine
EOF
        ;;
    depends)
        # Rust benefits from core utilities
        printf '%s\n' "core"
        ;;
    *)
        printf 'Usage: %s {info|packages|dockerfile|depends}\n' "$0" >&2
        exit 1
        ;;
esac