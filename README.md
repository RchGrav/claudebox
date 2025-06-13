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

- **MCP Server Integration**: Built-in Sequential Thinking and Memory servers for enhanced Claude capabilities
- **Automatic Docker Setup**: Complete Docker installation and configuration for Ubuntu, Debian, Fedora, Arch
- **Enhanced Security**: Network firewall restricting to Anthropic APIs (can be disabled)
- **15+ Development Profiles**: From embedded systems to machine learning
- **Visual Progress Indicators**: See exactly what's happening during installation
- **Advanced MCP Management**: Manage Model Context Protocol servers with `claudebox mcp [add|get|list|remove]` commands across project and user scopes. ClaudeBox default servers (`claudebox_thinking`, `claudebox_memory`) are intelligently managed in the project's `.mcp.json`.
- **Enhanced Security & Confirmation**: Interactive confirmations for privileged operations (`sudo`) and image modifications. Input sanitization for package names.
- **Dev Container Support**: Develop `claudebox` itself in a pre-configured VS Code development container.

## ✨ Features

- **Containerized Environment**: Run Claude Code in an isolated Docker container
- **MCP Servers**: Default `claudebox_thinking` and `claudebox_memory` servers. Full MCP server configuration via `claudebox mcp` commands.
- **Development Profiles**: Pre-configured language stacks (C/C++, Python, Rust, Go, etc.).
- **Persistent Configuration**: Settings and data persist between sessions.
- **Package Management**: Install additional `apt` packages into the image. Package names are sanitized for security.
- **Auto-Setup**: Handles Docker installation and configuration automatically, with user confirmations for privileged actions.
- **Security Features**:
    - Network isolation (iptables firewall) within the container, configurable via flags.
    - Interactive confirmations for sensitive operations.
    - Input sanitization for package installation.
    - User-configurable MCP servers.
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

# Get help (provides an overview of commands and security features)
claudebox help
# For Claude CLI specific help, run claudebox -- --help (if image is built)
# or claude --help inside 'claudebox shell'
```

### Main Commands

- `claudebox [claude-cli-options]`: Runs the Claude CLI with options.
- `claudebox profile [list|install name...]`: Manages development profiles.
- `claudebox install <package1> [package2...]`: Installs additional apt packages into the image.
- `claudebox mcp <add|get|list|remove> [options]`: Manages MCP server configurations (see details below).
- `claudebox shell`: Opens a Bash shell inside the container.
- `claudebox update`: Updates the Claude CLI within the image.
- `claudebox clean [--all]`: Removes the ClaudeBox Docker image (and optionally all build cache).
- `claudebox rebuild`: Rebuilds the Docker image from scratch.
- `claudebox help`: Shows ClaudeBox specific help, including security information.

### Development Profiles

ClaudeBox includes 15+ pre-configured development environments:

```bash
# List all available profiles
claudebox profile

# Install specific profiles
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

### MCP Server Management (`claudebox mcp`)

ClaudeBox provides robust tools for managing Model Context Protocol (MCP) server configurations. These configurations tell the Claude CLI how to launch and use custom tools or "servers" that can extend Claude's capabilities.

**Scopes:**
MCP configurations can exist in different scopes, with the following precedence (higher overrides lower):
1.  **Project Scope:** Defined in `.mcp.json` in your current project directory. Ideal for project-specific tools.
2.  **User Scope:** Defined in `~/.config/claude/mcp-servers-user.json`. For tools you want available across all your projects. This is a ClaudeBox-specific user file, separate from Claude CLI's own global config.
3.  **ClaudeBox Defaults:** `claudebox_thinking` and `claudebox_memory` servers are automatically configured in the project's `.mcp.json` if not already present. These provide built-in sequential thinking and memory capabilities.

**Commands:**

-   **`claudebox mcp list [--scope project|user|all]`**
    *   Lists MCP servers.
    *   `--scope project`: Shows only servers from `./.mcp.json`.
    *   `--scope user`: Shows only servers from `~/.config/claude/mcp-servers-user.json`.
    *   `--scope all` (or no scope): Shows a combined list reflecting the precedence (Project > User > ClaudeBox Defaults).

-   **`claudebox mcp add <name> <command> [--args JSON_ARRAY] [--env JSON_OBJECT] [--scope project|user]`**
    *   Adds or updates an MCP server configuration.
    *   `<name>`: A unique name for the server (e.g., `my_custom_tool`).
    *   `<command>`: The command to execute for this server (e.g., `/workspace/tools/my_tool_server.py`).
    *   `--args '["--port", "8080"]'`: Optional JSON array of arguments for the command.
    *   `--env '{"MY_VAR": "value"}'`: Optional JSON object of environment variables for the command.
    *   `--scope project` (default): Adds to `./.mcp.json`.
    *   `--scope user`: Adds to `~/.config/claude/mcp-servers-user.json`.

-   **`claudebox mcp get <name> [--scope project|user|container_default|effective]`**
    *   Retrieves and displays the configuration for a specific server.
    *   `--scope effective` (default): Shows the configuration that would actually be used, respecting precedence.
    *   Other scopes show the definition from that specific file or the built-in default.

-   **`claudebox mcp remove <name> --scope project|user`**
    *   Removes an MCP server configuration.
    *   `--scope` is mandatory to prevent accidental deletion.

**Example:**
```bash
# Add a project-specific Python tool
claudebox mcp add mypy_checker /usr/bin/python3 --args '["/workspace/tools/mypy_runner.py"]' --scope project

# List all effective MCP servers
claudebox mcp list

# Get the configuration for the memory server
claudebox mcp get claudebox_memory --scope effective
```

### Package Management

```bash
# Install additional packages
claudebox install htop vim tmux

# Open a shell in the container
claudebox shell

# Update Claude CLI
claudebox update
```

### Security Options

```bash
# Enable NOPASSWD sudo for the 'claude' user *inside* the container.
# This does NOT affect your host system's sudo.
# Use with extreme caution, as it allows root privileges within the container.
claudebox --dangerously-enable-sudo

# Disable the container's network firewall, allowing all outbound connections
# from the container. The default firewall restricts access to Anthropic APIs and common package repos.
# Use with extreme caution.
claudebox --dangerously-disable-firewall

# Pass the --dangerously-skip-permissions flag directly to the Claude CLI.
# This may bypass certain safety checks within the Claude CLI itself.
claudebox --dangerously-skip-permissions
```

### Maintenance

```bash
# Remove ClaudeBox image
claudebox clean

# Deep clean (remove all build cache)
claudebox clean --all

# Rebuild the image from scratch
claudebox rebuild
```

## 🔧 Configuration

ClaudeBox stores data in:
- `~/.claude/` - Claude configuration and data
- `~/.claudebox/` - ClaudeBox-specific data (MCP memory, etc.)
- Current directory mounted as `/workspace` in container

### Environment Variables

- `ANTHROPIC_API_KEY` - Your Anthropic API key
- `NODE_ENV` - Node environment (default: production)

### MCP Configuration (Legacy Note)

Previously, ClaudeBox used a backup/restore mechanism for a single project-level `.mcp.json`. This has been upgraded. ClaudeBox now intelligently manages its default servers (`claudebox_thinking`, `claudebox_memory`) within the project's `.mcp.json` without overwriting other user-defined servers in that file. Users can also manage a separate user-level configuration file. See the "MCP Server Management" section for details on the new `claudebox mcp` commands.

## 🛡️ Security

ClaudeBox is designed with security in mind, but it's important to understand its features and your responsibilities:

-   **Confirmations for Sensitive Actions**:
    *   **Tier 1 (y/N confirmation)**: Operations that modify the Docker image (e.g., `claudebox profile ...`, `claudebox install ...`) or make significant non-system changes will ask for a `y/N` confirmation.
    *   **Tier 2 (Keyword confirmation)**: Operations requiring `sudo` on your host machine (e.g., initial Docker installation, Docker group configuration, global symlink creation) or performing potentially destructive actions (e.g., `claudebox clean --all`) will require you to type a specific keyword to proceed.
    *   These confirmations can be bypassed for automated environments using environment variables (use with caution):
        *   `export CLAUDEBOX_AUTO_APPROVE_TIER1=true` (for y/N prompts)
        *   `export CLAUDEBOX_AUTO_APPROVE_TIER2_DANGEROUS=true` (for keyword prompts - **highly risky**)

-   **Input Sanitization**:
    *   Package names provided to `claudebox install` are sanitized to allow only typical characters (alphanumeric, `_`, `-`, `.`, `:`, `~`, `+`) to prevent command injection.

-   **Dangerous Flags**:
    *   Flags like `--dangerously-enable-sudo` (for sudo *inside* the container) and `--dangerously-disable-firewall` significantly alter the container's security posture. Understand the risks before using them. The `confirm_action` prompt will notify you if these flags are active.

-   **MCP Server Commands**:
    *   You define the commands for custom MCP servers. Ensure these commands are from trusted sources or are safe, as they will be executed by the Claude CLI within the container.

-   **Container Network Firewall**:
    *   By default, the ClaudeBox container runs with a network firewall (`iptables`) that restricts outbound connections primarily to Anthropic APIs, common package repositories, and other essential services for development. This can be disabled with `--dangerously-disable-firewall`.

-   **Docker Socket Access**:
    *   ClaudeBox interacts with your host's Docker socket to manage its own image and containers. This is a powerful privilege; ensure no malicious software has replaced your `claudebox` script.

-   **Review**:
    *   Users are encouraged to review the `claudebox` script and the generated Dockerfile (e.g., via `docker history claudebox`) to understand the operations being performed.

## 🏗️ Architecture

ClaudeBox creates a Debian-based Docker image with:
- Node.js (via NVM for version flexibility)
- Claude Code CLI (@anthropic-ai/claude-code)
- MCP servers (thinking and memory)
- User account matching host UID/GID
- Network firewall (Anthropic-only by default)
- Volume mounts for workspace and configuration

## 🧑‍💻 Development

ClaudeBox includes a development container setup for VS Code, providing a consistent environment for working on the `claudebox` script itself.

**Prerequisites:**
- VS Code
- Docker Desktop
- VS Code "Dev Containers" extension (ID: `ms-vscode-remote.remote-containers`)

**Setup:**
1. Clone this repository.
2. Open the repository root in VS Code.
3. VS Code should prompt you to "Reopen in Container". Click it.

**Features:**
- Ubuntu-based container with necessary tools pre-installed (`bash`, `curl`, `git`, `jq`, `shellcheck`, `shfmt`, `iptables`).
- The `claudebox` script from your workspace is available as `claudebox-dev` within the dev container for testing.
- Docker-in-Docker support: The host Docker socket is mounted, allowing you to run and test `claudebox-dev` commands that interact with Docker (e.g., building images, running containers).
- Pre-configured VS Code extensions for Bash scripting, Docker integration, and Markdown.
- **Dev Container Firewall**: A restrictive firewall (`.devcontainer/init-firewall.sh`) is applied when the dev container starts, limiting its outbound network access to essential domains (Anthropic, GitHub, package repos, VS Code services). This helps test `claudebox` in a more controlled network setting and enhances the security of the development environment itself.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. See the "Development" section for information on setting up a development environment.

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🐛 Troubleshooting

### Docker Permission Issues
ClaudeBox automatically handles Docker setup, but if you encounter issues:
1. The script will add you to the docker group
2. You may need to log out/in or run `newgrp docker`
3. Run `claudebox` again

### MCP Servers Not Working
Test MCP servers after installation:
```bash
claudebox shell
~/test-mcp.sh
```

### Profile Installation Failed
```bash
claudebox clean --all
claudebox rebuild
claudebox profile <name>
```

### Can't Find Command
Ensure the symlink was created:
```bash
sudo ln -s /path/to/claudebox /usr/local/bin/claudebox
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
