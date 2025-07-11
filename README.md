# ClaudeBox 🐳

[![Docker](https://img.shields.io/badge/Docker-Required-blue.svg)](https://www.docker.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-RchGrav%2Fclaudebox-blue.svg)](https://github.com/RchGrav/claudebox)

The Ultimate Claude Code Docker Development Environment - Run Claude AI's coding assistant in a fully containerized, reproducible environment with pre-configured development profiles and MCP servers.

```
 ██████╗██╗      █████╗ ██╗   ██╗██████╗ ███████╗
██╔════╝██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝
██║     ██║     ███████║██║   ██║██║  ██║█████╗
██║     ██║     ██╔══██║██║   ██║██║  ██║██╔══╝
╚██████╗███████╗██║  ██║╚██████╔╝██████╔╝███████╗
 ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝

██████╗  ██████╗ ██╗  ██╗
██╔══██╗██╔═══██╗╚██╗██╔╝
██████╔╝██║   ██║ ╚███╔╝ 
██╔══██╗██║   ██║ ██╔██╗ 
██████╔╝╚██████╔╝██╔╝ ██╗
╚═════╝  ╚═════╝ ╚═╝  ╚═╝
```

## 🚀 What's New in Latest Update

- **Enhanced UI/UX**: Improved menu alignment and comprehensive info display
- **New `profiles` Command**: Quick listing of all available profiles with descriptions
- **Firewall Management**: New `allowlist` command to view/edit network allowlists
- **Per-Project Isolation**: Separate Docker images, auth state, history, and configs
- **Improved Clean Menu**: Clear descriptions showing exact paths that will be removed
- **Profile Management Menu**: Interactive profile command with status and examples
- **Persistent Project Data**: Auth state, shell history, and tool configs preserved
- **Smart Profile Dependencies**: Automatic dependency resolution (e.g., C includes build-tools)

## ✨ Features

- **Containerized Environment**: Run Claude Code in an isolated Docker container
- **Development Profiles**: Pre-configured language stacks (C/C++, Python, Rust, Go, etc.)
- **Project Isolation**: Complete separation of images, settings, and data between projects
- **Persistent Configuration**: Settings and data persist between sessions
- **Multi-Instance Support**: Work on multiple projects simultaneously
- **Package Management**: Easy installation of additional development tools
- **Auto-Setup**: Handles Docker installation and configuration automatically
- **Security Features**: Network isolation with project-specific firewall allowlists
- **Developer Experience**: GitHub CLI, Delta, fzf, and zsh with oh-my-zsh powerline
- **Python Virtual Environments**: Automatic per-project venv creation with uv
- **Cross-Platform**: Works on Ubuntu, Debian, Fedora, Arch, and more
- **Shell Experience**: Powerline zsh with syntax highlighting and autosuggestions
- **Tmux Integration**: Seamless tmux socket mounting for multi-pane workflows

## 📋 Prerequisites

- Linux or macOS (WSL2 for Windows)
- Bash shell
- Docker (will be installed automatically if missing)

## 🛠️ Installation

### Quick Install (Recommended)

Once releases are available:
```bash
# Download and run the self-extracting installer
curl -fsSL https://github.com/RchGrav/claudebox/releases/latest/download/claudebox.run.sh | bash
```

For now (until release is published):
```bash
# Clone and run the installer
git clone https://github.com/RchGrav/claudebox.git
cd claudebox
bash .builder/build.sh
bash claudebox.run.sh
```

### Manual Install (Development)

```bash
# Clone the repository
git clone https://github.com/RchGrav/claudebox.git
cd claudebox

# Run the setup script
./setup.sh
```

The installer will:
- ✅ Extract ClaudeBox to `~/.claudebox/scripts/`
- ✅ Create symlink at `~/.local/bin/claudebox`
- ✅ Check for Docker (install if needed on first run)
- ✅ Configure Docker for non-root usage (on first run)


## 📚 Usage

### Basic Usage

```bash
# Launch Claude Code CLI
claudebox

# Pass arguments to Claude
claudebox --model opus -c

# Save your arguments so you don't need to type them every time
claudebox --model opus -c

# View the Claudebox info screen
claudebox info

# Get help
claudebox --help        # Shows Claude help with ClaudeBox additions
```

### Multi-Instance Support

ClaudeBox supports running multiple instances in different projects simultaneously:

```bash
# Terminal 1 - Project A
cd ~/projects/website
claudebox

# Terminal 2 - Project B
cd ~/projects/api
claudebox shell

# Terminal 3 - Project C
cd ~/projects/ml-model
claudebox profile python ml
```

Each project maintains its own:
- Docker image (`claudebox-<project-name>`)
- Language profiles and installed packages
- Firewall allowlist
- Python virtual environment
- Memory and context (via MCP)
- Claude configuration (`.claude.json`)

### Development Profiles

ClaudeBox includes 15+ pre-configured development environments:

```bash
# List all available profiles with descriptions
claudebox profiles

# Interactive profile management menu
claudebox profile

# Check current project's profiles
claudebox profile status

# Install specific profiles (project-specific)
claudebox profile python ml       # Python + Machine Learning
claudebox profile c openwrt       # C/C++ + OpenWRT
claudebox profile rust go         # Rust + Go
```

#### Available Profiles:

**Core Profiles:**
- **core** - Core Development Utilities (compilers, VCS, shell tools)
- **build-tools** - Build Tools (CMake, autotools, Ninja)
- **shell** - Optional Shell Tools (fzf, SSH, man, rsync, file)
- **networking** - Network Tools (IP stack, DNS, route tools)

**Language Profiles:**
- **c** - C/C++ Development (debuggers, analyzers, Boost, ncurses, cmocka)
- **rust** - Rust Development (installed via rustup)
- **python** - Python Development (managed via uv)
- **go** - Go Development (installed from upstream archive)
- **javascript** - JavaScript/TypeScript (Node installed via nvm)
- **java** - Java Development (OpenJDK 17, Maven, Gradle, Ant)
- **ruby** - Ruby Development (gems, native deps, XML/YAML)
- **php** - PHP Development (PHP + extensions + Composer)

**Specialized Profiles:**
- **openwrt** - OpenWRT Development (cross toolchain, QEMU, distro tools)
- **database** - Database Tools (clients for major databases)
- **devops** - DevOps Tools (Docker, Kubernetes, Terraform, etc.)
- **web** - Web Dev Tools (nginx, HTTP test clients)
- **embedded** - Embedded Dev (ARM toolchain, serial debuggers)
- **datascience** - Data Science (Python, Jupyter, R)
- **security** - Security Tools (scanners, crackers, packet tools)
- **ml** - Machine Learning (build layer only; Python via uv)

### Default Flags Management

Save your preferred security flags to avoid typing them every time:

```bash
# Save default flags
claudebox save --enable-sudo --disable-firewall

# Clear saved flags
claudebox save

# Now all claudebox commands will use your saved flags automatically
claudebox  # Will run with sudo and firewall disabled
```

### Project Information

View comprehensive information about your ClaudeBox setup:

```bash
# Show detailed project and system information
claudebox info
```

The info command displays:
- **Current Project**: Path, ID, and data directory
- **ClaudeBox Installation**: Script location and symlink
- **Saved CLI Flags**: Your default flags configuration
- **Claude Commands**: Global and project-specific custom commands
- **Project Profiles**: Installed profiles, packages, and available options
- **Docker Status**: Image status, creation date, layers, running containers
- **All Projects Summary**: Total projects, images, and Docker system usage

### Package Management

```bash
# Install additional packages (project-specific)
claudebox install htop vim tmux

# Open a powerline zsh shell in the container
claudebox shell

# Update Claude CLI
claudebox update

# View/edit firewall allowlist
claudebox allowlist
```

### Tmux Integration

ClaudeBox provides tmux support for multi-pane workflows:

```bash
# Launch ClaudeBox with tmux support
claudebox tmux

# If you're already in a tmux session, the socket will be automatically mounted
# Otherwise, tmux will be available inside the container

# Use tmux commands inside the container:
# - Create new panes: Ctrl+b % (vertical) or Ctrl+b " (horizontal)
# - Switch panes: Ctrl+b arrow-keys  
# - Create new windows: Ctrl+b c
# - Switch windows: Ctrl+b n/p or Ctrl+b 0-9
```

ClaudeBox automatically detects and mounts existing tmux sockets from the host, or provides tmux functionality inside the container for powerful multi-context workflows.

### Task Engine

ClaudeBox contains a compact task engine for reliable code generation tasks:

```bash
# In Claude, use the task command
/task

# This provides a systematic approach to:
# - Breaking down complex tasks
# - Implementing with quality checks
# - Iterating until specifications are met
```

### Security Options

```bash
# Run with sudo enabled (use with caution)
claudebox --enable-sudo

# Disable network firewall (allows all network access)
claudebox --disable-firewall

# Skip permission checks
claudebox --dangerously-skip-permissions
```

### Maintenance

```bash
# Interactive clean menu
claudebox clean

# Project-specific cleanup options
claudebox clean --project          # Shows submenu with options:
  # profiles - Remove profile configuration (*.ini file)
  # data     - Remove project data (auth, history, configs, firewall)
  # docker   - Remove project Docker image
  # all      - Remove everything for this project

# Global cleanup options
claudebox clean --containers       # Remove ClaudeBox containers
claudebox clean --image           # Remove containers and current project image
claudebox clean --cache           # Remove Docker build cache
claudebox clean --volumes         # Remove ClaudeBox volumes
claudebox clean --all             # Complete Docker cleanup

# Rebuild the image from scratch
claudebox rebuild
```

## 🔧 Configuration

ClaudeBox stores data in:
- `~/.claude/` - Global Claude configuration (mounted read-only)
- `~/.claudebox/` - Global ClaudeBox data
- `~/.claudebox/profiles/` - Per-project profile configurations (*.ini files)
- `~/.claudebox/<project-name>/` - Project-specific data:
  - `.claude/` - Project auth state
  - `.claude.json` - Project API configuration
  - `.zsh_history` - Shell history
  - `.config/` - Tool configurations
  - `firewall/allowlist` - Network allowlist
- Current directory mounted as `/workspace` in container

### Project-Specific Features

Each project automatically gets:
- **Docker Image**: `claudebox-<project-name>` with installed profiles
- **Profile Configuration**: `~/.claudebox/profiles/<project-name>.ini`
- **Python Virtual Environment**: `.venv` created with uv when Python profile is active
- **Firewall Allowlist**: Customizable per-project network access rules
- **Claude Configuration**: Project-specific `.claude.json` settings

### Environment Variables

- `ANTHROPIC_API_KEY` - Your Anthropic API key
- `NODE_ENV` - Node environment (default: production)

## 🏗️ Architecture

ClaudeBox creates a per-project Debian-based Docker image with:
- Node.js (via NVM for version flexibility)
- Claude Code CLI (@anthropic-ai/claude-code)
- User account matching host UID/GID
- Network firewall (project-specific allowlists)
- Volume mounts for workspace and configuration
- GitHub CLI (gh) for repository operations
- Delta for enhanced git diffs (version 0.17.0)
- uv for fast Python package management
- Nala for improved apt package management
- fzf for fuzzy finding
- zsh with oh-my-zsh and powerline theme
- Profile-specific development tools with intelligent layer caching
- Persistent project state (auth, history, configs)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🐛 Troubleshooting

### Docker Permission Issues
ClaudeBox automatically handles Docker setup, but if you encounter issues:
1. The script will add you to the docker group
2. You may need to log out/in or run `newgrp docker`
3. Run `claudebox` again

### Profile Installation Failed
```bash
# Clean and rebuild for current project
claudebox clean --project
claudebox rebuild
claudebox profile <name>
```

### Profile Changes Not Taking Effect
ClaudeBox automatically detects profile changes and rebuilds when needed. If you're having issues:
```bash
# Force rebuild
claudebox rebuild
```

### Python Virtual Environment Issues
ClaudeBox automatically creates a venv when Python profile is active:
```bash
# The venv is created at ~/.claudebox/<project>/.venv
# It's automatically activated in the container
claudebox shell
which python  # Should show the venv python
```

### Can't Find Command
Ensure the symlink was created:
```bash
ls -la ~/.local/bin/claudebox
# Or manually create it
ln -s /path/to/claudebox ~/.local/bin/claudebox
```

### Multiple Instance Conflicts
Each project has its own Docker image and is fully isolated. To check status:
```bash
# Check all ClaudeBox images and containers
claudebox info

# Clean project-specific data
claudebox clean --project
```

### Build Cache Issues
If builds are slow or failing:
```bash
# Clear Docker build cache
claudebox clean --cache

# Complete cleanup and rebuild
claudebox clean --all
claudebox
```

## 🎉 Acknowledgments

- [Anthropic](https://www.anthropic.com/) for Claude AI
- [Model Context Protocol](https://github.com/anthropics/model-context-protocol) for MCP servers
- Docker community for containerization tools
- All the open-source projects included in the profiles

---

Made with ❤️ for developers who love clean, reproducible environments

## Contact

**Author/Maintainer:** RchGrav  
**GitHub:** [@RchGrav](https://github.com/RchGrav)

## 📝 Changelog

### v1.0.0-rc4
- **Full macOS/Bash 3.2 Compatibility**: Complete rewrite for Bash 3.2 using function-based profile system
  - Replaced associative arrays with portable getter functions
  - Fixed uppercase conversion `${var^^}` with POSIX-compliant `tr` command
  - Eliminated all "unbound variable" errors in strict mode
  - Single implementation works for both Bash 3.2 and 4+
- **Project Isolation & Management**: Major improvements to project handling
  - Projects organized under `~/.claudebox/projects/` for cleaner separation
  - Single `config.ini` per project replaces multiple config files
  - Better project listing with size/status display
  - Fixed JSON handling prevents auth loss
  - Smart -c flag filtering when no conversation exists
  - Project claudebox folder mounted at `~/.claudebox` in container
- **MCP Configuration Support**: Smart MCP settings file handling
  - Automatically detects `.mcp.json` in project claudebox folder
  - Merges with workspace `.mcp.json` if both exist
  - Passes `--mcp-settings-file` to Claude CLI when appropriate
- **Stability & Quality**: Comprehensive improvements
  - Applied ShellCheck fixes for better reliability
  - Fixed unbound variables (`XAUTHORITY`, `profile_file`, etc.)
  - Improved clean command with fixed `--project all` functionality
  - Added terminal resize support (SIGWINCH handlers)
  - Enhanced error handling in build system
- **Testing**: Added comprehensive test suite
  - Bash 3.2 compatibility tests
  - Docker-based testing for actual Bash 3.2 verification
  - 13 tests covering all compatibility aspects

### v1.0.0-rc3
- **Flag Prioritizer System**: Implemented robust flag sorting to ensure control flags are processed in correct order
- **Fixed Shell Mode Bug**: Shell command now works properly with saved flags
- **Code Simplification**: Removed legacy flag handling code
- **Improved Entrypoint**: Cleaner flag processing with dedicated control flag handling

### v1.0.0-rc2
- **Enhanced UI**: Improved menu alignment and info display with emojis and consistent columns
- **New Commands**: Added `profiles` for quick listing and `allowlist` for firewall management
- **Project Isolation**: Complete separation of auth, history, and configs per project
- **Profile Menu**: Interactive profile management with status checking
- **Clean Menu**: Clearer descriptions showing exact paths for each cleanup option
- **Volume Architecture**: Fixed mount isolation for proper project separation
