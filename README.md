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

The source version is v2.0.1. Release downloads contain the latest published
version; use [Development Installation](#development-installation) to test changes
on `main` that have not yet been released.

### Method 1: Self-Extracting Installer (Recommended)

The self-extracting installer is ideal for automated setups and quick installation:

```bash
# Download the latest release
wget https://github.com/RchGrav/claudebox/releases/latest/download/claudebox.run
chmod +x claudebox.run
./claudebox.run
```

This will:
- Extract ClaudeBox to `~/.claudebox/source/`
- Create a symlink at `~/.local/bin/claudebox` (you may need to add `~/.local/bin` to your PATH)
- Show setup instructions if PATH configuration is needed

### Method 2: Archive Installation

For manual installation or custom locations, use the archive:

```bash
# Download a versioned archive from the Releases page, then set its filename.
# The latest published release at the time of this update is v2.0.0.
ARCHIVE=claudebox-2.0.0.tar.gz
wget "https://github.com/RchGrav/claudebox/releases/latest/download/$ARCHIVE"

# Extract to your preferred location
mkdir -p ~/my-tools/claudebox
tar -xzf "$ARCHIVE" -C ~/my-tools/claudebox --strip-components=1

# Run main.sh to create symlink
cd ~/my-tools/claudebox
./main.sh

# Or create your own symlink
ln -s ~/my-tools/claudebox/main.sh ~/.local/bin/claudebox
```

### Development Installation

For development or testing the latest changes:
```bash
# Clone the repository
git clone https://github.com/RchGrav/claudebox.git
cd claudebox

# Build the installer
bash .builder/build.sh

# Run the installer built from this checkout
./dist/claudebox.run profiles
```

### PATH Configuration

If `claudebox` command is not found after installation, add `~/.local/bin` to your PATH:

```bash
# For Bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# For Zsh (macOS default)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

The installer will:
- ✅ Extract ClaudeBox to `~/.claudebox/source/`
- ✅ Create symlink at `~/.local/bin/claudebox`
- ✅ Check for Docker (install if needed on first run)
- ✅ Configure Docker for non-root usage (on first run)


## 📚 Usage

### First Project and Slots

A **slot** is a persistent Claude session/configuration directory for a project.
Slots share that project's workspace, Docker image, profiles, and Python environment;
each slot has its own Claude authentication, history, and tool configuration.
The running container is temporary; the slot's mounted data survives normal exit.

```bash
cd ~/projects/my-project
claudebox create            # Create your first slot
claudebox slots             # Show slot numbers, authentication and running state
claudebox add python        # Optional: add development profiles
claudebox slot 1            # Launch slot 1; authenticate inside Claude if needed
```

For another simultaneous session, run `claudebox create` again and launch the new
number shown by `claudebox slots`. Bare `claudebox` selects an available slot.
`claudebox slot <number>` attaches to that slot if it is already running. Extra
Claude arguments require an inactive slot because they cannot change a running
session. Bare `claudebox` continues to select an inactive slot.

`claudebox revoke` removes the highest-numbered slot if it is inactive, including
its saved authentication and history; it refuses to remove an active slot. `claudebox revoke all` removes inactive slots while
skipping active ones. Neither command deletes the project workspace.

See [Installation, persistence and customization](docs/operations.md) for installer
internals, actual storage paths, host access to session logs, and persistent tools.

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

### macOS Clipboard

Enable clipboard access when starting a session:

```bash
claudebox --clipboard
# Or select an inactive slot:
claudebox --clipboard slot 1
```

This optional feature requires Python 3 on the Mac. It lets container applications
read clipboard images and replace clipboard text while the session is running.
It does not expose host clipboard text for reading. Without this option, ClaudeBox
does not start a clipboard service.

Use Claude Code's image-paste shortcut (`Ctrl+V` in most terminals) after copying
an image or screenshot. Text copy through Linux clipboard utilities is forwarded
to macOS too. Images are limited to 20 MiB and text writes to 1 MiB. The bridge uses
a random session token, permits only its host TCP port through the container
firewall, and shuts down with the launching session. Detached launches do not
start an independent clipboard service.
The HTTP listener binds only to host loopback; treat the session token as a
secret and enable this only for containers you trust with that
clipboard access. Enabling it on an already-running slot requires restarting that
slot unless it was started with clipboard support.

Terminal selection is separate from application clipboard access. In Apple
Terminal, if a wrapped login URL cannot be selected, use **Select All**, copy into
an editor, then copy just the URL. This workaround was confirmed in
[issue #107](https://github.com/RchGrav/claudebox/issues/107#issuecomment-4349351938).
Terminals that support clipboard escape sequences may require permission in
their settings. See [tmux's clipboard guide](https://github.com/tmux/tmux/wiki/Clipboard)
when using host tmux.

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
- **flutter** - Flutter Framework (installed using fvm, use FLUTTER_SDK_VERSION to set different version)
- **javascript** - JavaScript/TypeScript (Node installed via nvm)
- **java** - Java Development (Latest LTS via SDKMan, Maven, Gradle, Ant)
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
- `~/.claudebox/source/` - Installed source files
- `~/.claudebox/projects/<project-id>/` - Shared project state, including `profiles.ini`
- `~/.claudebox/projects/<project-id>/<slot-id>/.claude/` - Per-slot authentication, sessions and history
- `~/.claudebox/projects/<project-id>/<slot-id>/.claude.json`, `.config/`, `.cache/` - Per-slot settings and tool data
- `~/.claudebox/projects/<project-id>/.venv/` and `.local/share/uv/python/` - Shared Python environment and managed interpreters
- `~/.claudebox/ssh/` - Optional dedicated SSH directory
- Current project directory - Mounted read-write at `/workspace`, including a normal repository's `.git` directory

The host's entire `~/.claude/` directory is **not** mounted. User MCP configuration
is read from `~/.claude.json`; commands are synchronized separately. Global skill
packages are not automatically imported.

### SSH Key Configuration

ClaudeBox prefers `~/.claudebox/ssh/` and mounts it **read-write**, allowing persistent
`known_hosts` updates. This applies even when the directory is empty. Otherwise,
an existing host `~/.ssh/` is mounted **read-only**.

**Read-only is not secret isolation.** Container processes can read and use private
keys in the mounted directory; read-only only prevents changing those host files.
A dedicated directory limits which keys are exposed. An empty dedicated directory
avoids mounting the host's normal SSH keys.

```bash
mkdir -p ~/.claudebox/ssh
chmod 700 ~/.claudebox/ssh
# Optional: generate a dedicated key and register its public key with your service.
ssh-keygen -t ed25519 -f ~/.claudebox/ssh/id_ed25519 -C "claudebox@$(hostname)"
```

Use `claudebox add shell` to include `openssh-client` when `ssh` is missing. The
profile is installed on the next image build. SSH-agent forwarding is not provided
by this directory-mount mechanism.

### Project-Specific Features

Each project automatically gets:
- **Docker Image**: `claudebox-<project-name>` with installed profiles
- **Profile Configuration**: `~/.claudebox/projects/<project-id>/profiles.ini`
- **Python Virtual Environment**: `.venv` created with uv when Python profile is active
- **Firewall Allowlist**: Customizable per-project network access rules
- **Claude Configuration**: Project-specific `.claude.json` settings

### Environment Variables

A project `.env` file is both mounted read-only at `/workspace/.env` and loaded by
Docker's `--env-file`. For example:

```dotenv
ANTHROPIC_BASE_URL=https://your-api-endpoint.example
GH_TOKEN=your-fine-grained-token
ANTHROPIC_API_KEY=your-api-key
```

Use Docker env-file syntax (`NAME=value`), not shell commands or `export` statements.
The file is not executed or sourced. Keep real credentials out of Git commits.
An explicitly set host `ANTHROPIC_API_KEY` overrides the file, including an explicitly
empty value; an unset host key leaves the file's value intact. `NODE_ENV` is explicitly
forwarded from the host and defaults to `production`.

The host's `~/.gitconfig` is also mounted read-only when it exists. Paths referenced
by that file, such as external `include` files or credential helpers, must be available
inside the container to work.

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
# The venv is created at ~/.claudebox/projects/<project-id>/.venv
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
