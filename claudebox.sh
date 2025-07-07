#!/usr/bin/env bash
# ==============================================================================
#  ClaudeBox – Docker-based Claude CLI environment
#  
#  This refactored version preserves ALL existing functionality while
#  improving maintainability through modular structure.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------ constants --
# Cross-platform script path resolution  
get_script_path() {
    local source="${BASH_SOURCE[0]:-$0}"
    while [[ -L "$source" ]]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    echo "$(cd -P "$(dirname "$source")" && pwd)/$(basename "$source")"
}

readonly SCRIPT_PATH="$(get_script_path)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
export SCRIPT_PATH
export CLAUDEBOX_SCRIPT_DIR="${SCRIPT_DIR}"

# Parse early flags (--verbose)
VERBOSE=false
for arg in "$@"; do
    case "$arg" in
        --verbose) VERBOSE=true ;;
    esac
done
export VERBOSE

# Load saved default flags if they exist
DEFAULT_FLAGS=()
if [[ -f "$HOME/.claudebox/default-flags" ]]; then
    while IFS= read -r flag; do
        [[ -n "$flag" ]] && DEFAULT_FLAGS+=("$flag")
    done < "$HOME/.claudebox/default-flags"
fi

# --------------------------------------------------------------- source libs --
for lib in common env os state project docker config template commands; do
    # shellcheck disable=SC1090
    source "${SCRIPT_DIR}/lib/${lib}.sh"
done

# -------------------------------------------------------------------- main() --
main() {
    update_symlink
    
    local project_folder_name
    project_folder_name=$(get_project_folder_name "$PROJECT_DIR")
    IMAGE_NAME="claudebox-${project_folder_name}"
    export IMAGE_NAME
    
    local docker_status
    docker_status=$(check_docker; echo $?)
    case $docker_status in
        1) install_docker ;;
        2)
            warn "Docker is installed but not running."
            warn "Starting Docker requires sudo privileges..."
            sudo systemctl start docker
            docker info &>/dev/null || error "Failed to start Docker"
            docker ps &>/dev/null || configure_docker_nonroot
            ;;
        3)
            warn "Docker requires sudo. Setting up non-root access..."
            configure_docker_nonroot
            ;;
    esac

    local args=("$@")
    local new_args=()
    local found_rebuild=false

    for arg in "${args[@]}"; do
        if [[ "$arg" == "rebuild" ]]; then
            found_rebuild=true
        elif [[ "$arg" == "--verbose" ]]; then
            VERBOSE=true
        else
            new_args+=("$arg")
        fi
    done
    
    # Set up project variables early - needed by multiple sections
    project_folder_name=$(get_project_folder_name "$PROJECT_DIR")
    IMAGE_NAME="claudebox-${project_folder_name}"
    PROJECT_CLAUDEBOX_DIR="$HOME/.claudebox/projects/$project_folder_name"
    export PROJECT_CLAUDEBOX_DIR

    if [[ "$found_rebuild" == "true" ]]; then
        warn "Rebuilding ClaudeBox Docker image (no cache)..."
        if docker image inspect "$IMAGE_NAME" &>/dev/null; then
            # Remove the specific container for this project
            docker rm -f "$IMAGE_NAME" 2>/dev/null || true
            # Remove any old labeled containers
            docker ps -a --filter "label=claudebox.project" -q | xargs -r docker rm -f 2>/dev/null || true
            docker rmi -f "$IMAGE_NAME" 2>/dev/null || true
        fi
        export CLAUDEBOX_NO_CACHE=true
        set -- "${new_args[@]}"
    fi

    mkdir -p "$PROJECT_CLAUDEBOX_DIR"

    # Check for help flags early - only check first argument
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
        show_help
        exit 0
    fi

    [[ "$VERBOSE" == "true" ]] && echo "Command: ${1:-none}" >&2
    
    # First, handle commands that don't require Docker image
    case "${1:-}" in
        profiles|projects|profile|save|install|unlink|allowlist|clean|undo|redo|help|info)
            # These will be handled by dispatch_command
            dispatch_command "$@"
            exit $?
            ;;
        *)
            # Default case - need to check if we need to build
            ;;
    esac
    
    # Check if Docker image is needed and exists (skip if rebuilding)
    case "${1:-}" in
        shell|update|config|mcp|migrate-installer)
            # These commands need Docker image
            if [[ "${CLAUDEBOX_NO_CACHE:-}" != "true" ]] && [[ ! -f /.dockerenv ]] && ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
                error "ClaudeBox image not found.\nRun ${GREEN}claudebox${NC} first to build the image."
            fi
            ;;
    esac

    # Ensure shared commands folder is set up
    setup_shared_commands
    
    setup_project_folder
    setup_claude_agent_command

    local need_rebuild=false
    local current_profiles=()
    local profile_hash=""

    local config_file="$PROJECT_CLAUDEBOX_DIR/config.ini"
    if [[ -f "$config_file" ]]; then
        readarray -t current_profiles < <(read_profile_section "$config_file" "profiles")
        local cleaned_profiles=()
        for profile in "${current_profiles[@]}"; do
            profile=$(echo "$profile" | tr -d '[:space:]')
            [[ -z "$profile" ]] && continue
            cleaned_profiles+=("$profile")
        done
        current_profiles=("${cleaned_profiles[@]}")

        if [[ ${#current_profiles[@]} -gt 0 ]]; then
            profile_hash=$(printf '%s\n' "${current_profiles[@]}" | sort | _sha256 | cut -d' ' -f1)
        fi
    fi

    # Calculate hash of the script itself
    local script_hash=$(_sha256 "$SCRIPT_PATH" | cut -d' ' -f1)
    local build_hash="${script_hash}-${profile_hash}"
    
    # Check if build files have changed
    local last_build_hash_file="$HOME/.claudebox/.last_build_hash"
    if [[ -f "$last_build_hash_file" ]]; then
        local last_build_hash=$(cat "$last_build_hash_file")
        if [[ "$build_hash" != "$last_build_hash" ]]; then
            docker rmi -f "$IMAGE_NAME" 2>/dev/null || true
            need_rebuild=true
        fi
    else
        # No hash file means first run or deleted, trigger rebuild
        need_rebuild=true
    fi

    if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        local image_profile_hash
        image_profile_hash=$(docker inspect "$IMAGE_NAME" --format '{{index .Config.Labels "claudebox.profiles"}}' 2>/dev/null || echo "")

        if [[ "$profile_hash" != "$image_profile_hash" ]]; then
            if [[ ${#current_profiles[@]} -gt 0 ]]; then
                info "Building with profiles: ${current_profiles[*]}"
            fi
            docker rmi -f "$IMAGE_NAME" 2>/dev/null || true
            need_rebuild=true
        fi
    else
        need_rebuild=true
    fi

    # Only build if needed AND not a command that doesn't require image
    case "${1:-}" in
        profiles|projects|profile|save|install|unlink|allowlist|clean|undo|redo|help|info)
            # These commands don't need Docker image, skip building
            ;;
        *)
            if [[ "$need_rebuild" == "true" ]] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
                logo
                local build_context="$HOME/.claudebox/build"
                mkdir -p "$build_context"
                local dockerfile="$build_context/Dockerfile"
                
                # Copy static build files from repository
                cp "${SCRIPT_DIR}/build/docker-entrypoint.sh" "$build_context/" || error "Failed to copy docker-entrypoint.sh"
                cp "${SCRIPT_DIR}/build/init-firewall" "$build_context/" || error "Failed to copy init-firewall"
                chmod +x "$build_context/docker-entrypoint.sh" "$build_context/init-firewall"

                info "Using git-delta version: $DELTA_VERSION"

                # Generate Dockerfile
                cat > "$dockerfile" <<'DOCKERFILE'
FROM debian:bookworm
ARG USER_ID GROUP_ID USERNAME NODE_VERSION DELTA_VERSION
ARG REBUILD_TIMESTAMP

RUN echo '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
        apt-get install -y --no-autoremove --no-install-recommends ca-certificates curl locales gnupg && apt-get clean && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen en_US.UTF-8 &&\
        mkdir -p /usr/share/keyrings && \
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /tmp/githubcli.gpg && \
        cat /tmp/githubcli.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
        rm -f /tmp/githubcli.gpg && \
    chmod 644 /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg]" \
    "https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && apt-get update && \
        apt-get install -y --no-autoremove --no-install-recommends apt-utils wget zsh fzf ca-certificates sudo git iptables ipset gh unzip jq \
        procps vim nano less iputils-ping traceroute dnsutils netcat-openbsd net-tools xdg-utils && \
        rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

RUN groupadd -g $GROUP_ID $USERNAME || true && \
    useradd -m -u $USER_ID -g $GROUP_ID -s /bin/bash $USERNAME

RUN ARCH=$(dpkg --print-architecture) && \
    wget -q https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${ARCH}.deb && \
    dpkg -i git-delta_${DELTA_VERSION}_${ARCH}.deb && \
    rm git-delta_${DELTA_VERSION}_${ARCH}.deb

USER $USERNAME
WORKDIR /home/$USERNAME

RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v1.2.0/zsh-in-docker.sh)" -- \
    -p git \
    -p fzf \
    -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
    -a "source /usr/share/doc/fzf/examples/completion.zsh" \
    -a 'export HISTFILE="/home/$USERNAME/.cache/zsh_history"' \
    -a 'export HISTSIZE=10000' \
    -a 'export SAVEHIST=10000' \
    -a 'setopt HIST_IGNORE_DUPS' \
    -a 'setopt SHARE_HISTORY' \
    -a 'setopt HIST_FCNTL_LOCK' \
    -a 'setopt APPEND_HISTORY' \
    -a 'export NVM_DIR="$HOME/.nvm"' \
    -a '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' \
    -a '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' \
    -x

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

# Create Python venv that all tools can use
RUN ~/.local/bin/uv venv ~/.venv

RUN git config --global core.pager delta && \
    git config --global interactive.diffFilter "delta --color-only" && \
    git config --global delta.navigate true && \
    git config --global delta.light false && \
    git config --global delta.side-by-side true

ENV DEVCONTAINER=true

ENV SHELL=/bin/zsh

ENV NVM_DIR="/home/$USERNAME/.nvm"
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

RUN bash -c "source $NVM_DIR/nvm.sh && \
    if [[ \"$NODE_VERSION\" == '--lts' ]]; then \
        nvm install --lts && \
        nvm alias default 'lts/*'; \
    else \
        nvm install $NODE_VERSION && \
        nvm alias default $NODE_VERSION; \
    fi && \
    nvm use default"

RUN echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc && \
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc

RUN bash -c "source $NVM_DIR/nvm.sh && \
    nvm use default && \
    npm install -g @anthropic-ai/claude-code"

RUN cat >> ~/.zshrc <<'EOF'

if [[ -n "$PS1" ]] && command -v stty >/dev/null; then
  function _update_size {
    local rows cols
    { stty size } 2>/dev/null | read rows cols
    ((rows)) && export LINES=$rows COLUMNS=$cols
  }
  TRAPWINCH() { _update_size }
  _update_size
fi
EOF

RUN echo "shopt -s checkwinsize" >> ~/.bashrc

RUN cat > ~/.tmux.conf <<'EOF'

set -g aggressive-resize on

set -g default-terminal "screen-256color"
set -ga terminal-overrides ",xterm-256color:Tc"

set -g mouse on
set -g history-limit 10000
EOF

USER root

# Add sudoers entry for claude user (following Anthropic's model)
RUN echo "claude ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/claude && \
    chmod 0440 /etc/sudoers.d/claude

RUN cat > /etc/profile.d/00-winsize.sh <<'EOF'
if [ -n "$PS1" ] && command -v stty >/dev/null 2>&1; then
  _update_size() {
    local sz
    sz=$(stty size 2>/dev/null) || return
    export LINES=${sz%% *}  COLUMNS=${sz##* }
  }
  trap _update_size WINCH
  _update_size
fi
EOF
DOCKERFILE

                # Add profile-specific installations
                if [[ ${#current_profiles[@]} -gt 0 ]]; then
                    info "Building with profiles: ${current_profiles[*]}"

                    resolved_profiles=()
                    for profile in "${current_profiles[@]}"; do
                        resolved_profiles+=($(expand_profile "$profile"))
                    done

                    unique_profiles=($(awk -v RS=' ' '!seen[$1]++' <<< "${resolved_profiles[*]}"))

                    for profile in "${unique_profiles[@]}"; do
                        # Convert space-separated package string to array
                        local packages=$(get_profile_packages "$profile")
                        IFS=' ' read -ra pkg_list <<< "$packages"
                        
                        # Only add apt install section if there are packages
                        if [[ ${#pkg_list[@]} -gt 0 ]]; then
                            cat >> "$dockerfile" <<DOCKERFILE
# $(get_profile_description "$profile")
RUN export DEBIAN_FRONTEND=noninteractive && \\
    apt-get update && \\
    apt-get install -y --no-autoremove ${pkg_list[*]} && \\
    apt-get clean && rm -rf /var/lib/apt/lists/*
DOCKERFILE
                        fi
                        
                        # Always check for special installation steps
                        case "$profile" in
                            rust)
                                cat >> "$dockerfile" <<'DOCKERFILE'
USER $USERNAME
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    echo 'source $HOME/.cargo/env' >> ~/.bashrc && \
    echo 'source $HOME/.cargo/env' >> ~/.zshrc && \
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc && \
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.zshrc
USER root
DOCKERFILE
                                ;;
                            go)
                                cat >> "$dockerfile" <<'DOCKERFILE'
RUN GO_VERSION="1.21.5" && \
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" && \
    tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz" && \
    rm "go${GO_VERSION}.linux-amd64.tar.gz" && \
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile.d/go.sh
DOCKERFILE
                                ;;
                            python)
                                cat >> "$dockerfile" <<'DOCKERFILE'
USER $USERNAME
RUN ~/.local/bin/uv pip install --python ~/.venv/bin/python ipython black mypy pylint pytest ruff poetry pipenv
USER root
DOCKERFILE
                                ;;
                            ml)
                                cat >> "$dockerfile" <<'DOCKERFILE'
USER $USERNAME
RUN ~/.local/bin/uv pip install --python ~/.venv/bin/python torch transformers scikit-learn numpy pandas matplotlib
USER root
DOCKERFILE
                                ;;
                            datascience)
                                cat >> "$dockerfile" <<'DOCKERFILE'
USER $USERNAME
RUN ~/.local/bin/uv pip install --python ~/.venv/bin/python jupyter notebook jupyterlab numpy pandas scipy matplotlib seaborn scikit-learn statsmodels plotly
USER root
DOCKERFILE
                                ;;
                            javascript)
                                cat >> "$dockerfile" <<'DOCKERFILE'
USER $USERNAME
RUN bash -c "source \$NVM_DIR/nvm.sh && npm install -g typescript eslint prettier yarn pnpm"
USER root
DOCKERFILE
                                ;;
                            *) : ;;
                        esac
                    done
                fi

                # Add label with profile hash
                echo "# Label the image with the profile hash for change detection" >> "$dockerfile"
                echo "LABEL claudebox.profiles=\"$profile_hash\"" >> "$dockerfile"
                echo "LABEL claudebox.project=\"$project_folder_name\"" >> "$dockerfile"
                echo "" >> "$dockerfile"
                
                cat >> "$dockerfile" <<'DOCKERFILE'

# Copy init-firewall script
COPY --chmod=755 init-firewall /home/$USERNAME/init-firewall
RUN chown $USERNAME:$USERNAME /home/$USERNAME/init-firewall

USER $USERNAME
RUN bash -c "source $NVM_DIR/nvm.sh && claude --version"

WORKDIR /workspace
USER root
COPY --chown=$USERNAME docker-entrypoint.sh /usr/local/bin/docker-entrypoint
RUN sed -i "s/DOCKERUSER/$USERNAME/g" /usr/local/bin/docker-entrypoint && \
    sed -i "s/DOCKERUSER/$USERNAME/g" /home/$USERNAME/init-firewall && \
    chmod +x /usr/local/bin/docker-entrypoint

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
DOCKERFILE

                # Build the Docker image
                run_docker_build "$dockerfile" "$build_context"
                
                # Save build hash
                mkdir -p "$(dirname "$last_build_hash_file")"
                echo "$build_hash" > "$last_build_hash_file"

                echo
                cecho "ClaudeBox Setup Complete!" "$CYAN"
                echo
                cecho "Quick Start:" "$GREEN"
                echo -e "  ${YELLOW}claudebox [options]${NC}        # Launch Claude CLI"
                echo
                cecho "Power Features:" "$GREEN"
                echo -e "  ${YELLOW}claudebox profiles${NC}               # See all available profiles"
                echo -e "  ${YELLOW}claudebox profile c openwrt${NC}      # Install C + OpenWRT tools"
                echo -e "  ${YELLOW}claudebox profile python ml${NC}      # Install Python + ML stack"
                echo -e "  ${YELLOW}claudebox install <packages>${NC}     # Install additional apt packages"
                echo -e "  ${YELLOW}claudebox shell${NC}                  # Open powerline shell in container"
                echo -e "  ${YELLOW}claudebox allowlist${NC}              # View firewall configuration"
                echo
                cecho "Security:" "$GREEN"
                echo -e "  Network firewall: ON by default (Anthropic recommended)"
                echo -e "  Sudo access: OFF by default"
                echo
                cecho "Maintenance:" "$GREEN"
                echo -e "  ${YELLOW}claudebox clean ${NC}                 # See all cleanup options"
                echo -e "  ${YELLOW}claudebox unlink ${NC}                # Remove symbolic link"
                echo
                cecho "Just install the profile you need and start coding!" "$PURPLE"
                exit 0
            fi
            ;;
    esac

    # Ensure .claudebox exists with proper permissions
    if [[ ! -d "$HOME/.claudebox" ]]; then
        mkdir -p "$HOME/.claudebox"
    fi

    # Fix permissions if needed
    if [[ ! -w "$HOME/.claudebox" ]]; then
        warn "Fixing .claudebox permissions..."
        sudo chown -R "$USER:$USER" "$HOME/.claudebox" || true
    fi

    # Create default allowlist file if it doesn't exist
    local allowlist_file="$PROJECT_CLAUDEBOX_DIR/allowlist"
    
    if [[ ! -f "$allowlist_file" ]]; then
        # Create allowlist with default domains
        cat > "$allowlist_file" <<'EOF'
# Default domains (always allowed):
# api.anthropic.com, console.anthropic.com, statsig.anthropic.com, sentry.io

# GitHub.com
github.com
api.github.com
raw.githubusercontent.com
ssh.github.com
avatars.githubusercontent.com
codeload.github.com
objects.githubusercontent.com
pipelines.actions.githubusercontent.com
ghcr.io
pkg-containers.githubusercontent.com

# GitLab.com
gitlab.com
api.gitlab.com
registry.gitlab.com
uploads.gitlab.com
gitlab.io
*.gitlab.io
*.s3.amazonaws.com
*.amazonaws.com

# Bitbucket.org
bitbucket.org
api.bitbucket.org
altssh.bitbucket.org
bbuseruploads.s3.amazonaws.com
bitbucket-pipelines-prod-us-west-2.s3.amazonaws.com
bitbucket-pipelines-prod-us-east-1.s3.amazonaws.com
bitbucket-pipelines-prod-eu-west-1.s3.amazonaws.com

# Atlassian IP Ranges (Bitbucket Cloud)
104.192.136.0/21
185.166.140.0/22
13.200.41.128/25
18.246.31.128/25

# Optional (Git LFS, Assets)
github-cloud.s3.amazonaws.com
github-releases.githubusercontent.com
github-production-release-asset-2e65be.s3.amazonaws.com
EOF
    fi

    # Add default flags
    set -- "${DEFAULT_FLAGS[@]}" "$@"

    # Flag Prioritizer System
    # Define control flags and their priority (lower number = higher priority)
    # Using function for Bash 3.2 compatibility
    get_control_flag_priority() {
        case "$1" in
            "--shell-mode") echo 1 ;;
            "--enable-sudo") echo 2 ;;
            "--disable-firewall") echo 3 ;;
            *) echo "" ;;
        esac
    }
    
    # Check if .claude/projects exists, if not remove -c flag
    if [[ ! -d "$PROJECT_CLAUDEBOX_DIR/.claude/projects" ]]; then
        local filtered_args=()
        for arg in "$@"; do
            if [[ "$arg" != "-c" && "$arg" != "--continue" ]]; then
                filtered_args+=("$arg")
            fi
        done
        set -- "${filtered_args[@]}"
    fi
    
    # Extract and sort control flags
    local control_flags=()
    local claude_flags=()
    local temp_args=("$@")
    
    # Extract control flags and separate from Claude flags
    for arg in "${temp_args[@]}"; do
        local priority=$(get_control_flag_priority "$arg")
        if [[ -n "$priority" ]]; then
            control_flags+=("$arg")
        else
            claude_flags+=("$arg")
        fi
    done
    
    # Sort control flags by priority
    if [[ ${#control_flags[@]} -gt 0 ]]; then
        IFS=$'\n' control_flags=($(
            for flag in "${control_flags[@]}"; do
                echo "$(get_control_flag_priority "$flag"):$flag"
            done | sort -n | cut -d: -f2
        ))
    fi
    
    # Handle update command specially to persist changes
    if [[ "${claude_flags[0]:-}" == "update" ]]; then
        local project_folder_name
        project_folder_name=$(get_project_folder_name "$PROJECT_DIR")
        local temp_container="claudebox-update-${project_folder_name}-$$"
        
        # Run update in a named container and capture output
        local update_output
        update_output=$(run_claudebox_container "$temp_container" "attached" ${control_flags[@]+"${control_flags[@]}"} ${claude_flags[@]+"${claude_flags[@]}"} 2>&1)
        echo "$update_output"
        
        # Only commit if an actual update occurred
        if echo "$update_output" | grep -q "Successfully updated\|Verifying update"; then
            fillbar
            docker commit "$temp_container" "$IMAGE_NAME" >/dev/null
            fillbar stop
            success "Claude updated and changes saved to image!"
        fi
        
        # Always remove the container
        docker rm -f "$temp_container" >/dev/null 2>&1
    else
        # For now, just run the container directly without persistence
        # This approach is simpler and more reliable
        run_claudebox_container "" "interactive" ${control_flags[@]+"${control_flags[@]}"} ${claude_flags[@]+"${claude_flags[@]}"}
    fi
}

# Run main with all arguments
main "$@"