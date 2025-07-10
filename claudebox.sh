#!/usr/bin/env bash
# ==============================================================================
#  ClaudeBox – Docker-based Claude CLI environment
#
#  This refactored version preserves ALL existing functionality while
#  improving maintainability through modular structure.
# ==============================================================================

set -euo pipefail

# Add error handler to show where script fails
trap 'exit_code=$?; [[ $exit_code -eq 130 ]] && exit 130 || echo "Error at line $LINENO: Command failed with exit code $exit_code" >&2' ERR INT

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
for lib in common env os state project docker config template commands welcome; do
    # shellcheck disable=SC1090
    source "${SCRIPT_DIR}/lib/${lib}.sh"
done

# -------------------------------------------------------------------- main() --
main() {
    [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Starting main with args: $*" >&2
    update_symlink

    local docker_status
    docker_status=$(check_docker; echo $?)
    case $docker_status in
        1) install_docker ;;
        2)
            warn "Docker is installed but not running."
            warn "Starting Docker requires sudo privileges..."
            sudo systemctl start docker
            docker info || error "Failed to start Docker"
            docker ps || configure_docker_nonroot
            ;;
        3)
            warn "Docker requires sudo. Setting up non-root access..."
            configure_docker_nonroot
            ;;
    esac

    local args=("$@")
    local new_args=()
    local found_rebuild=false
    local found_tmux=false

    for arg in "${args[@]}"; do
        if [[ "$arg" == "rebuild" ]]; then
            found_rebuild=true
        elif [[ "$arg" == "--verbose" ]]; then
            VERBOSE=true
        elif [[ "$arg" == "tmux" ]]; then
            # Skip tmux from arguments but remember we saw it
            found_tmux=true
            export CLAUDEBOX_WRAP_TMUX=true
        else
            new_args+=("$arg")
        fi
    done

    # Initialize project directory early (creates parent with profiles.ini)
    init_project_dir "$PROJECT_DIR"

    # Get parent directory (always safe to get)
    PROJECT_PARENT_DIR=$(get_parent_dir "$PROJECT_DIR")
    export PROJECT_PARENT_DIR

    # Always update args to remove --verbose and rebuild
    set -- "${new_args[@]}"
    
    if [[ "$found_rebuild" == "true" ]]; then
        # Get image name for rebuild
        IMAGE_NAME=$(get_image_name)

        warn "Forcing full rebuild of ClaudeBox Docker image..."
        # Remove checksum file to force rebuild
        rm -f "$PROJECT_PARENT_DIR/.docker_layer_checksums"
        # Remove image to force full rebuild
        docker rmi -f "$IMAGE_NAME" 2>/dev/null || true
    fi

    # Initialize project directory (creates parent with profiles.ini)
    init_project_dir "$PROJECT_DIR"

    [[ "$VERBOSE" == "true" ]] && echo "Command: ${1:-none}" >&2

    # First, handle commands that don't require Docker image
    case "${1:-}" in
        profiles|projects|profile|add|remove|save|install|unlink|allowlist|clean|undo|redo|info|slots|revoke|create|open|help|-h|--help)
            # These will be handled by dispatch_command
            dispatch_command "$@"
            local dispatch_exit=$?
            [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Exiting main with code $dispatch_exit" >&2
            exit $dispatch_exit
            ;;
        *)
            # Default case - need to check if we need to build
            ;;
    esac

    # For commands that need Docker, set up slot variables
    case "${1:-}" in
        shell|update|config|mcp|migrate-installer|create|slot|help|-h|--help|"")
            # These commands need a slot (help benefits from having one)
            project_folder_name=$(get_project_folder_name "$PROJECT_DIR")
            
            # If no slots exist, show menu and exit (except for create, slot, and help commands)
            if [[ -z "$project_folder_name" ]] || [[ "$project_folder_name" == "NONE" ]]; then
                if [[ "${1:-}" == "help" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
                    # For help, we can show it without a slot
                    show_help
                    exit 0
                elif [[ "${1:-}" != "create" && "${1:-}" != "slot" ]]; then
                    show_no_slots_menu
                    exit 0
                fi
            fi
            
            IMAGE_NAME=$(get_image_name)
            PROJECT_CLAUDEBOX_DIR="$PROJECT_PARENT_DIR/$project_folder_name"
            export PROJECT_CLAUDEBOX_DIR

            # Check if Docker image exists for commands that require it (skip if rebuilding or default command)
            # Allow create command to trigger build
            if [[ "${1:-}" != "" ]] && [[ "${1:-}" != "create" ]] && [[ "${1:-}" != "slot" ]] && [[ "${CLAUDEBOX_NO_CACHE:-}" != "true" ]] && [[ ! -f /.dockerenv ]] && ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
                error "ClaudeBox image not found.\nRun ${GREEN}claudebox${NC} first to build the image."
            fi
            ;;
    esac

    # Ensure shared commands folder is set up
    setup_shared_commands

    setup_claude_agent_command

    local need_rebuild=false
    local current_profiles=()
    local profile_hash=""
    local profiles_file_hash=""

    local profiles_file="$PROJECT_PARENT_DIR/profiles.ini"
    if [[ -f "$profiles_file" ]]; then
        # Calculate CRC32 of the entire profiles.ini file
        profiles_file_hash=$(crc32_file "$profiles_file")
        
        while IFS= read -r line; do
            [[ -n "$line" ]] && current_profiles+=("$line")
        done < <(read_profile_section "$profiles_file" "profiles")
        local cleaned_profiles=()
        for profile in "${current_profiles[@]}"; do
            profile=$(echo "$profile" | tr -d '[:space:]')
            [[ -z "$profile" ]] && continue
            cleaned_profiles+=("$profile")
        done
        current_profiles=("${cleaned_profiles[@]}")

        if [[ ${#current_profiles[@]} -gt 0 ]]; then
            profile_hash=$(printf '%s\n' "${current_profiles[@]}" | sort | cksum | cut -d' ' -f1)
        fi
    fi

    # Check if Docker rebuild is needed based on layer checksums
    if needs_docker_rebuild "$PROJECT_DIR" "$IMAGE_NAME"; then
        need_rebuild=true
        if [[ "$found_rebuild" != "true" ]]; then
            info "Detected changes in Docker build files, rebuilding..."
        fi
    fi

    # Only check Docker image for commands that need it
    case "${1:-}" in
        profiles|projects|add|remove|save|install|unlink|allowlist|clean|undo|redo|help|info|slots|slot|revoke)
            # These commands don't need Docker image
            ;;
        *)
            # Commands that need Docker - ensure IMAGE_NAME is set
            if [[ -z "${IMAGE_NAME:-}" ]]; then
                project_folder_name=$(get_project_folder_name "$PROJECT_DIR")
                
                # If no slots exist, this was already handled above
                if [[ -z "$project_folder_name" ]] || [[ "$project_folder_name" == "NONE" ]]; then
                    exit 0
                fi
                
                IMAGE_NAME=$(get_image_name)
                PROJECT_CLAUDEBOX_DIR="$PROJECT_PARENT_DIR/$project_folder_name"
                export PROJECT_CLAUDEBOX_DIR
            fi

            if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
                local image_profile_hash
                local image_profiles_crc
                image_profile_hash=$(docker inspect "$IMAGE_NAME" --format '{{index .Config.Labels "claudebox.profiles"}}' || echo "")
                image_profiles_crc=$(docker inspect "$IMAGE_NAME" --format '{{index .Config.Labels "claudebox.profiles.crc"}}' || echo "")

                # Check if either profile list or profiles.ini file has changed
                if [[ "$profile_hash" != "$image_profile_hash" ]] || [[ "$profiles_file_hash" != "$image_profiles_crc" ]]; then
                    if [[ ${#current_profiles[@]} -gt 0 ]]; then
                        info "Profiles changed, rebuilding with: ${current_profiles[*]}"
                    else
                        info "Profiles.ini changed, rebuilding..."
                    fi
                    [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Removing old image: $IMAGE_NAME" >&2
                docker rmi -f "$IMAGE_NAME" || true
                    need_rebuild=true
                fi
            else
                need_rebuild=true
            fi
            ;;
    esac

    # Only build if needed AND not a command that doesn't require image
    case "${1:-}" in
        profiles|projects|add|remove|save|install|unlink|allowlist|clean|undo|redo|help|info|slots|revoke|create)
            # These commands don't need Docker image, skip building
            ;;
        *)
            if [[ "$need_rebuild" == "true" ]] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
                # Check if this is the first run for this project
                local is_first_run=false
                if [[ ! -d "$PROJECT_PARENT_DIR" ]] || [[ ! -f "$PROJECT_PARENT_DIR/profiles.ini" ]]; then
                    is_first_run=true
                fi
                
                # Show welcome screen for first-time users
                if [[ "$is_first_run" == "true" ]] && [[ "${1:-}" == "" ]]; then
                    show_welcome_screen
                else
                    logo
                fi
                
                local build_context="$HOME/.claudebox/build"
                mkdir -p "$build_context"
                local dockerfile="$build_context/Dockerfile"

                # Copy static build files from templates
                cp "${SCRIPT_DIR}/assets/templates/docker-entrypoint.tmpl" "$build_context/docker-entrypoint.sh" || error "Failed to copy docker-entrypoint.sh"
                cp "${SCRIPT_DIR}/assets/templates/init-firewall.tmpl" "$build_context/init-firewall" || error "Failed to copy init-firewall"
                cp "${SCRIPT_DIR}/assets/templates/dockerignore.tmpl" "$build_context/.dockerignore" || error "Failed to copy .dockerignore"
                chmod +x "$build_context/docker-entrypoint.sh" "$build_context/init-firewall"

                info "Using git-delta version: $DELTA_VERSION"

                # Read the base Dockerfile template
                local base_dockerfile
                base_dockerfile=$(cat "${SCRIPT_DIR}/assets/templates/Dockerfile.tmpl") || error "Failed to read base Dockerfile"

                # Build profile installations section
                local profile_installations=""

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
                            profile_installations+="
# $(get_profile_description "$profile")
RUN export DEBIAN_FRONTEND=noninteractive && \\
    apt-get update && \\
    apt-get install -y --no-autoremove ${pkg_list[*]} && \\
    apt-get clean && rm -rf /var/lib/apt/lists/*"
                        fi

                        # Always check for special installation steps
                        case "$profile" in
                            rust)
                                profile_installations+="
USER \$USERNAME
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \\
    echo 'source \$HOME/.cargo/env' >> ~/.bashrc && \\
    echo 'source \$HOME/.cargo/env' >> ~/.zshrc && \\
    echo 'export PATH=\"\$HOME/.cargo/bin:\$PATH\"' >> ~/.bashrc && \\
    echo 'export PATH=\"\$HOME/.cargo/bin:\$PATH\"' >> ~/.zshrc
USER root"
                                ;;
                            go)
                                profile_installations+="
RUN GO_VERSION=\"1.21.5\" && \\
    wget -q \"https://go.dev/dl/go\${GO_VERSION}.linux-amd64.tar.gz\" && \\
    tar -C /usr/local -xzf \"go\${GO_VERSION}.linux-amd64.tar.gz\" && \\
    rm \"go\${GO_VERSION}.linux-amd64.tar.gz\" && \\
    echo 'export PATH=\$PATH:/usr/local/go/bin' >> /etc/profile.d/go.sh"
                                ;;
                            python)
                                profile_installations+="
USER \$USERNAME
RUN ~/.local/bin/uv pip install --python ~/.venv/bin/python ipython black mypy pylint pytest ruff poetry pipenv
USER root"
                                ;;
                            ml)
                                profile_installations+="
USER \$USERNAME
RUN ~/.local/bin/uv pip install --python ~/.venv/bin/python torch transformers scikit-learn numpy pandas matplotlib
USER root"
                                ;;
                            datascience)
                                profile_installations+="
USER \$USERNAME
RUN ~/.local/bin/uv pip install --python ~/.venv/bin/python jupyter notebook jupyterlab numpy pandas scipy matplotlib seaborn scikit-learn statsmodels plotly
USER root"
                                ;;
                            javascript)
                                profile_installations+="
USER \$USERNAME
RUN bash -c \"source \\\$NVM_DIR/nvm.sh && npm install -g typescript eslint prettier yarn pnpm\"
USER root"
                                ;;
                            *) : ;;
                        esac
                    done
                fi

                # Add extra packages from [packages] section
                local extra_packages=()
                if [[ -f "$profiles_file" ]]; then
                    while IFS= read -r line; do
                        [[ -n "$line" ]] && extra_packages+=("$line")
                    done < <(read_profile_section "$profiles_file" "packages")
                fi
                
                if [[ ${#extra_packages[@]} -gt 0 ]]; then
                    info "Installing extra packages: ${extra_packages[*]}"
                    profile_installations+="
# Extra packages from claudebox install
RUN export DEBIAN_FRONTEND=noninteractive && \\
    apt-get update && \\
    apt-get install -y --no-autoremove ${extra_packages[*]} && \\
    apt-get clean && rm -rf /var/lib/apt/lists/*"
                fi

                # Build labels section
                local labels="# Label the image with the profile hash for change detection
LABEL claudebox.profiles=\"$profile_hash\"
LABEL claudebox.profiles.crc=\"$profiles_file_hash\"
LABEL claudebox.project=\"$project_folder_name\""

                # Replace placeholders in the base Dockerfile
                local final_dockerfile="$base_dockerfile"
                final_dockerfile="${final_dockerfile//\{\{PROFILE_INSTALLATIONS\}\}/$profile_installations}"
                final_dockerfile="${final_dockerfile//\{\{LABELS\}\}/$labels}"

                # Write the final Dockerfile
                echo "$final_dockerfile" > "$dockerfile"

                # Build the Docker image
                run_docker_build "$dockerfile" "$build_context"

                # Save layer checksums after successful build
                save_docker_layer_checksums "$PROJECT_DIR"
                
                # Show next steps for first-time users
                if [[ "$is_first_run" == "true" ]] && [[ "${1:-}" == "" ]]; then
                    show_next_steps
                    exit 0
                fi
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
    local allowlist_file="$PROJECT_PARENT_DIR/allowlist"

    if [[ ! -f "$allowlist_file" ]]; then
        # Copy allowlist template
        local allowlist_template="${SCRIPT_DIR}/assets/templates/allowlist.tmpl"
        if [[ -f "$allowlist_template" ]]; then
            cp "$allowlist_template" "$allowlist_file" || error "Failed to copy allowlist template"
        else
            error "Allowlist template not found at $allowlist_template"
        fi
    fi

    # Add default flags
    set -- "${DEFAULT_FLAGS[@]}" "$@"

    # Flag Prioritizer System
    # Define control flags and their priority (lower number = higher priority)
    # Using function for Bash 3.2 compatibility
    get_control_flag_priority() {
        case "$1" in
            "--enable-sudo") echo 1 ;;
            "--disable-firewall") echo 2 ;;
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
            docker commit "$temp_container" "$IMAGE_NAME"
            fillbar stop
            success "Claude updated and changes saved to image!"
        fi

        # Always remove the container
        docker rm -f "$temp_container" >/dev/null
    else
        # Check if this is a special command that should be dispatched
        case "${claude_flags[0]:-}" in
            create|shell|config|mcp|migrate-installer|slot|revoke)
                [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Dispatching command with claude_flags: ${claude_flags[*]}" >&2
                dispatch_command "${claude_flags[@]}"
                exit $?
                ;;
            help|-h|--help)
                # Handle help specially now that we have IMAGE_NAME
                show_help
                ;;
            *)
                # Default: run Claude
                [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Default case: running container with claude_flags: ${claude_flags[*]}" >&2
                # Generate container name based on project and slot
                local slot_name=$(basename "$PROJECT_CLAUDEBOX_DIR")
                local container_name="claudebox-${project_folder_name}-${slot_name}"
                run_claudebox_container "$container_name" "interactive" ${control_flags[@]+"${control_flags[@]}"} ${claude_flags[@]+"${claude_flags[@]}"}
                ;;
        esac
    fi
}

# Run main with all arguments
main "$@"
