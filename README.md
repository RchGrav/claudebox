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

- **Per-Project Docker Images**: Each project now maintains its own Docker image for complete isolation
- **Intelligent Layer Caching**: Optimized Docker builds with profile-specific layer caching
- **Task Engine**: Built-in compact task engine for reliable code generation (`/task`)
- **Automatic Profile Rebuilding**: Detects profile changes and rebuilds automatically
- **Enhanced Firewall Templates**: Pre-configured allowlists for GitHub, GitLab, and Bitbucket
- **Project-Specific Claude Config**: Each project can have its own `.claude.json` settings
- **Profile Dependencies**: Smart dependency resolution (e.g., C profile includes build tools)
- **Nala Package Manager**: Faster, more user-friendly package management
- **Latest Tool Versions**: Auto-detects and installs latest versions of git-delta and other tools

## ✨ Features

- **Containerized Environment**: Run Claude Code in an isolated Docker container
- **MCP Servers**: Pre-configured Model Context Protocol servers for thinking and memory
- **Development Profiles**: Pre-configured language stacks (C/C++, Python, Rust, Go, etc.)
- **Project Isolation**: Complete separation of images, settings, and data between projects
- **Persistent Configuration**: Settings and data persist between sessions
- **Multi-Instance Support**: Work on multiple projects simultaneously
- **Package Management**: Easy installation of additional development tools
- **Auto-Setup**: Handles Docker installation and configuration automatically
- **Security Features**: Network isolation with project-specific firewall allowlists
- **Developer Experience**: GitHub CLI, Delta, fzf, and zsh with oh-my-zsh
- **Python Virtual Environments**: Automatic per-project venv creation with uv
- **Cross-Platform**: Works on Ubuntu, Debian, Fedora, Arch, and more

## 📋 Prerequisites

- Linux or macOS (WSL2 for Windows)
- Bash shell
- Docker (will be installed automatically if missing)

## 🛠️ Installation

```bash
# Download and setup ClaudeBox
curl -O https://raw.githubusercontent.com/RchGrav/claudebox/main/claudebox
chmod +x claudebox

# Run initial setup (handles everything automatically)
./claudebox
```

The script will:
- ✅ Check for Docker (install if needed)
- ✅ Configure Docker for non-root usage
- ✅ Build the ClaudeBox image with MCP servers
- ✅ Create a global symlink for easy access
- ✅ Set up MCP configuration in your workspace

## 📚 Usage

### Basic Usage

```bash
# Launch Claude CLI with MCP servers enabled
claudebox

# Pass arguments to Claude
claudebox --model opus -c

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
# List all available profiles
claudebox profile

# Install specific profiles (project-specific)
claudebox profile python ml        # Python + Machine Learning
claudebox profile c openwrt       # C/C++ + OpenWRT
claudebox profile rust go         # Rust + Go
```

#### Available Profiles:

- **c** - C/C++ Development (gcc, g++, gdb, valgrind, cmake, cmocka, lcov, ncurses)
- **openwrt** - OpenWRT Development (cross-compilation, QEMU, build essentials)
- **rust** - Rust Development (cargo, rustc, clippy, rust-analyzer)
- **python** - Python Development (pip, venv, black, mypy, pylint, poetry, pipenv)
- **go** - Go Development (latest Go toolchain)
- **javascript** - Node.js/TypeScript (npm, yarn, pnpm, TypeScript, ESLint, Prettier)
- **java** - Java Development (OpenJDK 17, Maven, Gradle, Ant)
- **ruby** - Ruby Development (Ruby, gems, bundler)
- **php** - PHP Development (PHP, Composer, common extensions)
- **database** - Database Tools (PostgreSQL, MySQL, SQLite, Redis, MongoDB clients)
- **devops** - DevOps Tools (Docker, Kubernetes, Terraform, Ansible, AWS CLI)
- **web** - Web Development (nginx, curl, httpie, jq)
- **embedded** - Embedded Development (ARM toolchain, OpenOCD, PlatformIO)
- **datascience** - Data Science (NumPy, Pandas, Jupyter, R)
- **security** - Security Tools (nmap, tcpdump, wireshark, penetration testing)
- **ml** - Machine Learning (PyTorch, TensorFlow, scikit-learn, transformers)

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

View detailed information about your ClaudeBox setup:

```bash
# Show all project profiles and running containers
claudebox info

# Example output:
# ClaudeBox Profile Status
# 
# Tracking 3 project profile(s)
# 
# /home/user/project1:
#   Profiles: python ml
#   Packages: htop vim
# 
# /home/user/project2:
#   Profiles: rust
# 
# Current project (/home/user/project1):
#   Profiles: python ml
#   Packages: htop vim
# 
# Running ClaudeBox containers:
# CONTAINER ID   STATUS         COMMAND
# abc123def      Up 5 minutes   claude
# 
# ClaudeBox Docker Images:
# REPOSITORY          TAG       SIZE
# claudebox-project1  latest    2.1GB
# claudebox-project2  latest    1.8GB
```

### Package Management

```bash
# Install additional packages (project-specific)
claudebox install htop vim tmux

# Open a shell in the container
claudebox shell

# Update Claude CLI
claudebox update
```

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
# View all clean options
claudebox clean --help

# Remove containers only
claudebox clean

# Remove current project's data and profile
claudebox clean --project

# Remove containers and image
claudebox clean --image

# Remove Docker build cache
claudebox clean --cache

# Remove associated volumes
claudebox clean --volumes

# Complete cleanup
claudebox clean --all

# Rebuild the image from scratch
claudebox rebuild
```

## 🔧 Configuration

ClaudeBox stores data in:
- `~/.claude/` - Claude configuration and data
- `~/.claudebox/` - Global ClaudeBox data
- `~/.claudebox/profiles/` - Per-project profile configurations
- `~/.claudebox/<project-name>/` - Project-specific data (memory, context, firewall, .claude.json)
- Current directory mounted as `/workspace` in container

### Project-Specific Features

Each project automatically gets:
- **Docker Image**: `claudebox-<project-name>` with installed profiles
- **Profile Configuration**: `~/.claudebox/profiles/<project-name>.ini`
- **Python Virtual Environment**: `.venv` created with uv when Python profile is active
- **Firewall Allowlist**: Customizable per-project network access rules
- **Memory & Context**: Isolated MCP server data
- **Claude Configuration**: Project-specific `.claude.json` settings

### Environment Variables

- `ANTHROPIC_API_KEY` - Your Anthropic API key
- `NODE_ENV` - Node environment (default: production)

### MCP Configuration

ClaudeBox automatically manages `.mcp.json` with three servers:
- Memory server for knowledge graphs
- Sequential thinking server for complex reasoning
- Context7 server for enhanced context management

## 🏗️ Architecture

ClaudeBox creates a per-project Debian-based Docker image with:
- Node.js (via NVM for version flexibility)
- Claude Code CLI (@anthropic-ai/claude-code)
- MCP servers (thinking, memory, and context7)
- User account matching host UID/GID
- Network firewall (project-specific allowlists)
- Volume mounts for workspace and configuration
- GitHub CLI (gh) for repository operations
- Delta for enhanced git diffs (auto-updated to latest)
- uv for fast Python package management
- Nala for improved apt package management
- fzf for fuzzy finding
- zsh with oh-my-zsh
- Profile-specific development tools with intelligent layer caching

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

### MCP Servers Not Working
Ensure your project has the `.mcp.json` configuration:
```bash
cat .mcp.json  # Should show memory, sequential-thinking, and context7 servers
```

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
