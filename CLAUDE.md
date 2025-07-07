# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ClaudeBox Refactoring Documentation

### Overview

This document describes the refactoring of the ClaudeBox monolithic bash script into a modular, maintainable structure while preserving all existing functionality.

## Refactoring Goals

1. **Preserve Functionality**: No changes to argument semantics, flag interpretation, command logic, or default flows
2. **Improve Maintainability**: Split 2,337-line monolith into logical modules
3. **Enable Testing**: Modular structure allows for unit testing
4. **Maintain Compatibility**: All existing commands and workflows must work identically

## Original Structure Analysis

The original `claudebox` script (2,337 lines) has been analyzed and split into three logical parts:

### Part 1: Infrastructure and Utilities (Lines 1-901)
- Script initialization and configuration
- Cross-platform compatibility (macOS/Linux)
- Utility functions (colors, logging, UI)
- Docker management functions
- Profile and project management
- Container runtime functions
- Setup and build file generation

### Part 2: Command Dispatcher (Lines 902-1021)
- Main function and command routing
- All command implementations:
  - `profiles`, `projects`, `profile`
  - `install`, `save`, `shell`
  - `update`, `config`, `mcp`
  - `allowlist`, `clean`, `unlink`
  - `info`, `undo`, `redo`
- Docker status handling
- Build hash management

### Part 3: Build and Runtime (Lines 1022-2337)
- Dockerfile generation
- Profile-specific package installation
- Container build execution
- Runtime flag processing
- Update persistence logic
- Default allowlist creation

## New Modular Structure

```
claudebox/
├── claudebox.sh          # Main entry point (thin wrapper) [SCAFFOLD ONLY]
├── lib/
│   ├── common.sh         # Shared colors & logging [STUB]
│   ├── env.sh           # Static environment variables [STUB]
│   ├── os.sh            # OS detection & compatibility [STUB]
│   ├── state.sh         # Host-side state management [STUB]
│   ├── project.sh       # Project path → slug mapping [STUB - HAS sha256sum!]
│   ├── docker.sh        # Docker interaction layer [STUB]
│   ├── config.sh        # INI file & profile helpers [STUB]
│   ├── template.sh      # Template rendering [STUB]
│   └── commands.sh      # Command dispatcher & handlers [STUB]
├── entrypoint/
│   └── docker-entrypoint.sh  # Container entrypoint [SCAFFOLD ONLY]
├── assets/
│   └── templates/
│       ├── init-firewall.tmpl
│       └── docker-entrypoint.tmpl
└── build/                # Generated artifacts (not templates)
    ├── Dockerfile        # Generated from part3
    ├── docker-entrypoint.sh  # Generated from part1
    └── init-firewall     # Generated from part1

```

**IMPORTANT**: All lib files are currently STUBS with placeholder implementations. The actual code from original_split/ needs to be migrated.

## Module Responsibilities

### claudebox.sh
- Parse early flags (--verbose)
- Source all library modules
- Call update_symlink
- Delegate to dispatch_command

### lib/common.sh
- Color constants and output functions
- Shared logging helpers (_debug, _info, _warn, _error)

### lib/env.sh
- All static environment variables
- User/group IDs, paths, versions

### lib/os.sh
- OS detection (macOS vs Linux)
- Filesystem case-sensitivity detection
- Platform-specific settings

### lib/state.sh
- Create/maintain ~/.claudebox directory structure
- Manage symlink at ~/.local/bin/claudebox

### lib/project.sh
- Convert project paths to deterministic slugs
- Generate Docker image names

### lib/docker.sh
- All Docker commands (build, run, exec)
- Container management functions

### lib/config.sh
- INI file reading/writing
- Profile management
- Default flags handling

### lib/template.sh
- Simple {{TOKEN}} template rendering
- Used for generating Docker files

### lib/commands.sh
- Main command dispatcher
- All command implementations
- Forward unknown commands to container

## Implementation Approach

1. **Extract code fences** from scaffold-refactor.md
2. **Map functionality** from original parts to new modules
3. **Preserve exact behavior** including:
   - All command arguments
   - Flag processing order
   - Default values
   - Error messages
   - Output formatting
4. **Test thoroughly** with existing workflows

## Key Preservation Points

- **Docker Image Naming**: Project-based with hash suffix
- **Profile System**: Dependency resolution unchanged
- **Flag Priority**: --shell-mode > --enable-sudo > --disable-firewall
- **Update Persistence**: Special handling for claude update
- **Build Optimization**: Only rebuild on profile/base changes
- **Network Security**: Default allowlist behavior
- **Cross-Platform**: macOS case-insensitive FS handling

## Testing Checklist

- [ ] `claudebox --help`
- [ ] `claudebox profiles`
- [ ] `claudebox projects`
- [ ] `claudebox profile <name>`
- [ ] `claudebox install <packages>`
- [ ] `claudebox save <flags>`
- [ ] `claudebox shell [admin]`
- [ ] `claudebox update [all]`
- [ ] `claudebox clean <type>`
- [ ] `claudebox allowlist`
- [ ] `claudebox info`
- [ ] `claudebox rebuild`
- [ ] Forward to container (unknown commands)
- [ ] Symlink creation/update
- [ ] Docker installation flow
- [ ] Profile dependency resolution
- [ ] Build hash detection
- [ ] Update persistence

## Common Development Commands

### Testing
```bash
# Run Bash 3.2 compatibility tests
bash tests/test_bash32_compat.sh

# Test in actual Bash 3.2 environment (Docker)
bash tests/test_in_bash32_docker.sh
```

### Building and Running
```bash
# Initial setup (will create Docker image for project)
./claudebox

# Rebuild Docker image from scratch
./claudebox rebuild

# Run with specific profiles
./claudebox profile python ml

# Open shell in container
./claudebox shell
./claudebox shell admin  # Persistent admin mode

# Pass flags to Claude
./claudebox --model opus -c
```

### Maintenance
```bash
# Clean project-specific data
./claudebox clean --project

# Update Claude CLI
./claudebox update

# Update everything (claudebox + commands + Claude)
./claudebox update all

# View project info
./claudebox info
```

## High-Level Architecture

### Current Monolithic Structure
The original `claudebox` script (2,337 lines) contains all functionality in a single file. Key sections:

1. **Initialization & Configuration** (lines 1-90)
   - Cross-platform compatibility detection
   - Default flags loading
   - Environment setup

2. **Core Functions** (lines 91-900)
   - Docker management
   - Profile system with 20 development environments
   - Project isolation and management
   - Container runtime configuration

3. **Main Command Dispatcher** (lines 914-1500+)
   - Handles 15+ commands with complex subcommands
   - Docker status checking and auto-configuration
   - Build optimization with hash tracking

4. **Dockerfile Generation & Build** (lines 1500-2337)
   - Dynamic Dockerfile creation based on profiles
   - Profile-specific installation logic
   - Container entrypoint and firewall setup

### Key Architectural Patterns

#### Project Isolation
Each project gets:
- Unique Docker image: `claudebox-<project-slug>_<hash>`
- Isolated configuration: `~/.claudebox/projects/<project-slug>/`
- Separate auth state, history, and tool configs
- Project-specific firewall allowlist

#### Profile System
- Function-based implementation for Bash 3.2 compatibility
- Profile dependencies (e.g., `c` → `core build-tools c`)
- Dynamic package installation based on profiles
- Build optimization via hash tracking

#### Security Model
- Firewall with allowlist-based network access
- Optional sudo controlled by flags
- Flag priority system: `--shell-mode` > `--enable-sudo` > `--disable-firewall`

#### Container Execution
- Standardized mounts and environment
- Three execution modes: interactive, detached, pipe
- Special handling for `claude update` with persistence

### Refactoring Target Structure
```
claudebox.sh          → Thin wrapper, sources libs, calls dispatch_command
lib/common.sh         → Colors, logging functions
lib/env.sh           → Static environment variables
lib/os.sh            → OS detection, compatibility
lib/state.sh         → Directory/symlink management
lib/project.sh       → Project path → slug mapping
lib/docker.sh        → Docker interaction layer
lib/config.sh        → INI file handling, profiles
lib/template.sh      → {{TOKEN}} template rendering
lib/commands.sh      → Command dispatcher and handlers
```

### Critical Preservation Points
1. **Exact command semantics** - All flags and arguments must work identically
2. **Profile function signatures** - Used throughout for package lookup
3. **Docker image naming** - Must maintain same algorithm for compatibility
4. **Flag processing order** - Priority system must be preserved
5. **Build hash detection** - Optimization logic must remain intact

## Special Commands

### Task Engine
The `/task` command activates a sophisticated multi-agent system for code generation:
- Located in `commands/taskengine.md`
- Provides systematic task breakdown and implementation
- Includes quality checks and iterative refinement

### DevOps Master
Custom DevOps configuration agent in `commands/devops.md`:
- Multi-platform CI/CD setup
- Repository configuration with best practices
- Support for GitHub Actions, GitLab CI, Jenkins, etc.

## Migration Status

- [x] Documentation of original structure
- [x] Module structure defined
- [x] Documentation stored in Pinecone database
- [ ] Code extraction from scaffold
- [ ] Function mapping to modules
- [ ] Integration testing
- [ ] Performance validation

## MCP Resources

This project uses Model Context Protocol (MCP) servers for enhanced capabilities:

### Pinecone Documentation Database
- **Index**: `claudebox-docs` 
- **Namespaces**:
  - `architecture`: Project overview and architecture documentation
  - `code-structure`: Detailed function and implementation documentation
- **Usage**: Search for specific implementation details or architectural decisions

### Memory Graph
- **Entities**: ClaudeBox (Project), ClaudeBox Refactoring (Task)
- **Relations**: Refactoring relationship tracked
- **Usage**: Track project state and relationships

### Sequential Thinking
- **Purpose**: Complex reasoning for refactoring decisions
- **Usage**: Analyze impact of changes and maintain consistency