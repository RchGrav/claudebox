# Changelog

All notable changes to ClaudeBox will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [2.0.1] - 2026-09-15

### Fixed
- **Bash 3.2 / `set -u`**: Fresh installs on macOS aborted with
  `lib/cli.sh: line 22: all_args[@]: unbound variable`. Empty array
  expansions are now guarded across the CLI, config, docker, and profile
  modules, and `readarray` is gone. Fixes #71, #90. (#89, TonyHernandezAtMS)
- **Entrypoint**: `local` used outside a function made containers exit on
  start once Python profiles were enabled. Fixes #65. (#100, b00y0h)
- **Python profiles**: uv-managed Python is now persisted by mounting
  `~/.local/share`, so `python3` survives container restarts. Fixes #87.
  (#88, TonyHernandezAtMS)
- **javascript profile**: nvm directory is chowned to the container user
  before `npm install -g`, fixing EACCES during build. (#102, b00y0h)
- **devops profile**: kubectl, helm, and terraform are installed from
  upstream releases since Debian bookworm has no packages for them.
  (#101, b00y0h)

### Added
- `tests/test_cli_bash32.sh` drives `main.sh` end to end under real
  Bash 3.2 and fails on any unbound variable; `test_in_bash32_docker.sh`
  now exits non-zero on failure.

## [2.0.0] - 2025-07-25

### Added
- **macOS Support**: Full macOS compatibility
  - Docker Desktop detection (no systemctl on macOS)
  - Fixed UID/GID mismatches (macOS uses 501:20 vs Linux 1000:1000)
  - Python PATH configuration for uv-managed installations
- **Build System Overhaul**: New versioned release system
  - Version tracking with `CLAUDEBOX_VERSION` constant
  - Builds output to `dist/` directory
  - Creates versioned archives (e.g., `claudebox-2.0.0.tar.gz`)
  - Self-extracting installer (`claudebox.run`)
- **PATH Setup**: Automatic PATH configuration detection
  - Shows setup instructions when `~/.local/bin` not in PATH
  - Works with both bash and zsh

### Changed
- **Docker BuildKit**: Removed cache mounts to fix macOS permission issues
- **Python Management**: Updated to use uv with `--python-preference managed`
- **Installation**: Improved first-time setup experience

### Fixed
- **macOS Docker**: Fixed "systemctl: command not found" error
- **Build Permissions**: Resolved npm cache permission errors on macOS
- **Python Availability**: Fixed Python not in PATH in tmux sessions
- **CLI Architecture**: Complete refactor of CLI parsing system
  - Fixed `--verbose` flag changing program behavior
  - Fixed `rebuild` command not continuing to requested action
  - Fixed inconsistent flag parsing across multiple locations
  - Implemented clean four-bucket architecture (host-only, control, script, pass-through)
  - All parsing now happens in single location (`lib/cli.sh`)
  - Predictable, maintainable flag handling
- **Docker Entrypoint**: Simplified to only handle control flags
  - Removed complex argument parsing
  - Control flags (`--enable-sudo`, `--disable-firewall`) extracted cleanly
  - Everything else passes through to Claude CLI

### Documentation
- Added `docs/cli-implementation.md` - Complete CLI architecture reference
- Added `docs/slot-management-system.md` - Comprehensive slot system documentation
- Updated `docs/checksum-and-naming-system.md` - Fixed slot checksum explanation
- Documented approved core image architecture for future implementation

## [1.0.0] - Previous Releases
## [2025-06-25]

### Fixed
- Fixed profile selection logic to handle empty profile values correctly (#24)

## [2025-06-22]

### Added
- Cross-platform host detection for Linux and macOS (#22)
- Filesystem case-sensitivity detection for macOS (HFS+/APFS)
- Docker BuildKit normalization for case-insensitive filesystems

### Changed
- Improved host OS detection with proper error handling
- Enhanced cross-platform script path resolution
- Pinned git-delta version to 0.17.0 for consistency

### Fixed
- Fixed grep -P flag compatibility issue on macOS (#21)
- Resolved issues with case-insensitive filesystem handling on macOS

## [2025-06-21]

### Changed
- Multiple README improvements and documentation updates
- Enhanced Docker build process and configuration

## [2025-06-20]

### Fixed
- Resolved initialization errors in the claudebox script
- Improved container performance and stability

### Removed
- Removed duplicate code blocks for cleaner codebase

## [2025-06-19]

### Added
- BuildX compatibility check for Docker builds
- Enhanced WSL (Windows Subsystem for Linux) support

### Changed
- Streamlined feature set and workflow improvements
- Improved error handling and user feedback

## Earlier Changes

### Initial Features
- Project-specific Docker containers for isolated development environments
- Profile system for language and tool installations
- Firewall configuration with allowlist support
- Persistent storage for project data
- Multi-project support with separate containers per project