# build/ Directory Documentation

This directory contains Docker build files and related utilities for creating ClaudeBox container images.

## File Index and Key Information

### Docker Files
- `Dockerfile` - Main Dockerfile for building ClaudeBox containers with all development profiles
- `Dockerfile.project` - Simplified Dockerfile for project-specific builds
- `dockerignore` - Template for .dockerignore files to exclude unnecessary files from build context

### Runtime Files
- `docker-entrypoint` - Container entrypoint script that handles initialization, user setup, and command execution
- `init-firewall` - Firewall initialization script for network isolation
- `allowlist` - Network allowlist configuration for permitted domains

### Utilities
- `generate-tools-readme` - Script to generate tooling documentation from profiles.ini

## Key Design Decisions & Notes

### Multi-Stage Build Pattern
The Dockerfiles use multi-stage builds to optimize image size and build caching. Base dependencies are installed first, then user-specific configurations.

### User ID Mapping
Container user (claude) is created with matching host UID/GID to avoid permission issues:
- Linux typically uses 1000:1000
- macOS uses 501:20 (staff group)
- The entrypoint handles this dynamically

### BuildKit and Layer Caching
- BuildKit is enabled by default for better caching
- Cache mounts were removed due to macOS UID/GID conflicts
- Each profile's dependencies are installed in separate RUN commands for better layer reuse

### Security Model
- Containers run as non-root user (claude)
- Sudo is available but controlled via ENABLE_SUDO flag
- Network isolation via iptables firewall (allowlist-based)
- No hardcoded secrets or credentials

## Recent Changes & Decisions

- BuildKit cache mounts removed to fix macOS permission errors
- Python installation switched to uv with --python-preference managed
- Entrypoint rewritten to handle tmux sessions and Python environments properly
- Added atomic lock mechanism for venv creation to prevent race conditions

## Areas Needing Attention

- The allowlist might need periodic updates for new services
- Some profile installations could be optimized for size
- Error handling in entrypoint could be more granular