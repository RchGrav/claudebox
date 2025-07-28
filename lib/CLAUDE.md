# lib/ Directory Documentation

This directory contains the core library modules for ClaudeBox, implementing modular functionality for the Docker-based Claude CLI environment.

## File Index and Key Information

### Core Modules
- `common.sh` - Shared utilities, logging, colors, and error handling functions
- `cli.sh` - CLI argument parsing following four-bucket architecture (host-only, control, script, pass-through)
- `env.sh` - Environment variable management and exports
- `os.sh` - Cross-platform OS detection and compatibility layer (handles MD5 differences between Linux/macOS)
- `state.sh` - State management, installation handling, and symlink creation

### Docker & Container Management
- `docker.sh` - Docker operations, image building, container management, and slot system
- `preflight.sh` - Pre-flight checks for Docker, disk space, and system requirements

### Project & Configuration
- `project.sh` - Project isolation, per-project settings, and command syncing
- `config.sh` - Configuration loading/saving, profile system, and ~/.claudebox structure

### Command System
- `commands.sh` - Main command dispatcher and help system
- `commands.core.sh` - Core commands (claude, shell, etc.)
- `commands.clean.sh` - Cleanup commands (prune, clean, reset)
- `commands.info.sh` - Information commands (info, status, projects)
- `commands.profile.sh` - Profile management commands
- `commands.slot.sh` - Multi-slot container management
- `commands.system.sh` - System commands (update, install, uninstall, rebuild)

### Other Utilities
- `welcome.sh` - Welcome messages and branding
- `tools-report.sh` - Generates tooling reports for Claude
- `project-fixed.sh` - Fixed project configurations (appears to be a stub)

## Key Design Decisions & Notes

### Bash 3.2 Compatibility
All scripts MUST maintain Bash 3.2 compatibility for macOS support. This means:
- No associative arrays
- No `${var^^}` uppercase expansion
- No `[[ -v var ]]` variable checks
- Use `command -v` instead of `which`

### Error Handling
All modules use `set -euo pipefail` for strict error handling. When using `&&` or `||` with this setting, always use proper if statements to avoid script exits.

### Cross-Platform Support
The `os.sh` module provides abstraction for platform differences. Any new platform-specific commands should be added there first. Never use commands like `sha256sum` directly without checking for macOS alternatives.

### Module Loading Order
In main.sh, libraries are loaded in a specific order:
```bash
for lib in cli common env os state project docker config commands welcome preflight; do
```
This order ensures dependencies are available when needed.

## Recent Changes & Decisions

- CLI parsing was completely refactored to fix flag handling issues
- Docker BuildKit cache mounts were removed to fix macOS permission issues
- Cross-platform MD5 handling was added to os.sh
- The slot system was implemented to support multiple concurrent Claude instances

## Areas Needing Attention

- SHA256 cross-platform support needs to be added to os.sh (similar to MD5)
- Some error messages could be more user-friendly
- Test coverage for the library modules could be improved