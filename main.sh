#!/usr/bin/env bash
# ==============================================================================
#  ClaudeBox – Docker-based Claude CLI environment
#
#  Clean CLI implementation following the four-bucket architecture
# ==============================================================================

# Version
readonly CLAUDEBOX_VERSION="2.0.0"

set -euo pipefail

# Add error handler to show where script fails
trap 'exit_code=$?; [[ $exit_code -eq 130 ]] && exit 130 || { echo "Error at line $LINENO: Command failed with exit code $exit_code" >&2; echo "Failed command: $BASH_COMMAND" >&2; echo "Call stack:" >&2; for i in ${!BASH_LINENO[@]}; do if [[ $i -gt 0 ]]; then echo "  at ${FUNCNAME[$i]} (${BASH_SOURCE[$i]}:${BASH_LINENO[$i-1]})" >&2; fi; done; }' ERR INT

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
# Now that script is at root, SCRIPT_DIR is the repo/install root
readonly INSTALL_ROOT="$HOME/.claudebox"
export SCRIPT_PATH
export CLAUDEBOX_SCRIPT_DIR="${SCRIPT_DIR}"
# Set PROJECT_DIR early (but allow override from environment)
export PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"

# Initialize VERBOSE to false (will be set properly by CLI parser)
export VERBOSE=false

# Note: Default flags are loaded later, only when running Claude interactively

# --------------------------------------------------------------- source libs --
# LIB_DIR is always relative to where the script is located
LIB_DIR="${SCRIPT_DIR}/lib"

# Load libraries in order - cli.sh must be loaded first for parsing
for lib in cli common env os state project docker config commands welcome preflight; do
    # shellcheck disable=SC1090
    source "${LIB_DIR}/${lib}.sh"
done

# Show first-time welcome message
show_first_time_welcome() {
    logo_small
    printf '\n'
    cecho "Welcome to ClaudeBox!" "$CYAN"
    printf '\n'
    printf '%s\n' "ClaudeBox is ready to use. Here's how to get started:"
    printf '\n'
    printf '%s\n' "1. Navigate to your project directory:"
    printf "   ${CYAN}%s${NC}\n" "cd /path/to/your/project"
    printf '\n'
    printf '%s\n' "2. Create your first container slot:"
    printf "   ${CYAN}%s${NC}\n" "claudebox create"
    printf '\n'
    printf '%s\n' "3. Launch Claude:"
    printf "   ${CYAN}%s${NC}\n" "claudebox"
    printf '\n'
    printf '%s\n' "Other useful commands:"
    printf "  ${CYAN}%-20s${NC} - %s\n" "claudebox help" "Show all available commands"
    printf "  ${CYAN}%-20s${NC} - %s\n" "claudebox profiles" "List available development profiles"
    printf "  ${CYAN}%-20s${NC} - %s\n" "claudebox projects" "List all ClaudeBox projects"
    printf '\n'
}

# -------------------------------------------------------------------- main() --
main() {
    # Save original arguments for later use with saved flags
    local original_args=("$@")
    
    # Enable BuildKit for all Docker operations
    export DOCKER_BUILDKIT=1
    
    # Step 1: Update symlink
    update_symlink
    
    # Step 2: Parse ALL arguments
    parse_cli_args "$@"
    
    # Step 3: Process host flags (sets VERBOSE, REBUILD, CLAUDEBOX_WRAP_TMUX)
    process_host_flags
    
    # Step 3a: Handle saved flags based on the first CLI argument
    local first_arg="${original_args[0]:-}"
    
    # Check if first arg is a command (no dash) that should skip saved flags
    case "$first_arg" in
        save|clean|kill)
            # These commands don't get saved flags at all
            ;;
        *)
            # Load and apply saved flags
            if [[ -f "$HOME/.claudebox/default-flags" ]]; then
                local saved_flags=()
                while IFS= read -r flag; do
                    [[ -n "$flag" ]] && saved_flags+=("$flag")
                done < "$HOME/.claudebox/default-flags"
                
                if [[ ${#saved_flags[@]} -gt 0 ]]; then
                    # Re-parse WITH saved flags, but the command structure is preserved
                    # because the command was already identified from original args
                    parse_cli_args "${original_args[@]}" "${saved_flags[@]}"
                    process_host_flags
                    
                    if [[ "$VERBOSE" == "true" ]]; then
                        echo "[DEBUG] Loaded saved flags: ${saved_flags[*]}" >&2
                    fi
                fi
            fi
            ;;
    esac
    
    # Step 4: Debug output if verbose
    debug_parsed_args
    
    # Step 4a: Check if this command even needs Docker
    local cmd_requirements="none"
    if [[ -n "${CLI_SCRIPT_COMMAND}" ]]; then
        # Pass the first pass-through arg as potential subcommand
        local first_arg="${CLI_PASS_THROUGH[0]:-}"
        cmd_requirements=$(get_command_requirements "${CLI_SCRIPT_COMMAND}" "$first_arg")
    else
        # No script command means we're running claude - needs Docker
        cmd_requirements="docker"
    fi
    
    # If command doesn't need Docker, skip all Docker setup
    if [[ "$cmd_requirements" == "none" ]]; then
        # Dispatch the command directly and exit
        dispatch_command "${CLI_SCRIPT_COMMAND}" "${CLI_PASS_THROUGH[@]}" "${CLI_CONTROL_FLAGS[@]}"
        exit $?
    fi
    
    # Step 5: Docker checks
    local docker_status
    docker_status=$(check_docker; echo $?)
    case $docker_status in
        1) install_docker ;;
        2)
            warn "Docker is installed but not running."
            case "$(uname -s)" in
                Darwin)
                    error "Docker Desktop is not running. Please start Docker Desktop from Applications."
                    ;;
                Linux)
                    warn "Starting Docker requires sudo privileges..."
                    sudo systemctl start docker
                    docker info || error "Failed to start Docker"
                    docker ps || configure_docker_nonroot
                    ;;
                *)
                    error "Unsupported OS: $(uname -s)"
                    ;;
            esac
            ;;
        3)
            warn "Docker requires sudo. Setting up non-root access..."
            configure_docker_nonroot
            ;;
    esac
    
    # Step 5a: Build core image if it doesn't exist
    local core_image="claudebox-core"
    if ! docker image inspect "$core_image" >/dev/null 2>&1; then
        # Show logo during build
        logo
        
        local build_context="$HOME/.claudebox/docker-build-context"
        mkdir -p "$build_context"
        
        # Copy build files
        local root_dir="$SCRIPT_DIR"
        cp "${root_dir}/build/docker-entrypoint" "$build_context/docker-entrypoint.sh" || error "Failed to copy docker-entrypoint.sh"
        cp "${root_dir}/build/init-firewall" "$build_context/init-firewall" || error "Failed to copy init-firewall"
        cp "${root_dir}/build/generate-tools-readme" "$build_context/generate-tools-readme" || error "Failed to copy generate-tools-readme"
        cp "${root_dir}/lib/tools-report.sh" "$build_context/tools-report.sh" || error "Failed to copy tools-report.sh"
        cp "${root_dir}/build/dockerignore" "$build_context/.dockerignore" || error "Failed to copy .dockerignore"
        chmod +x "$build_context/docker-entrypoint.sh" "$build_context/init-firewall" "$build_context/generate-tools-readme"
        
        # Create core Dockerfile
        local core_dockerfile="$build_context/Dockerfile.core"
        local base_dockerfile=$(cat "${root_dir}/build/Dockerfile") || error "Failed to read base Dockerfile"
        
        # Remove profile installations and labels placeholders for core
        local core_dockerfile_content="$base_dockerfile"
        core_dockerfile_content="${core_dockerfile_content//\{\{PROFILE_INSTALLATIONS\}\}/}"
        core_dockerfile_content="${core_dockerfile_content//\{\{LABELS\}\}/LABEL claudebox.type=\"core\"}"
        
        echo "$core_dockerfile_content" > "$core_dockerfile"
        
        # Build core image
        docker build \
            --progress=${BUILDKIT_PROGRESS:-auto} \
            --build-arg BUILDKIT_INLINE_CACHE=1 \
            --build-arg USER_ID="$USER_ID" \
            --build-arg GROUP_ID="$GROUP_ID" \
            --build-arg USERNAME="$DOCKER_USER" \
            --build-arg NODE_VERSION="$NODE_VERSION" \
            --build-arg DELTA_VERSION="$DELTA_VERSION" \
            -f "$core_dockerfile" -t "$core_image" "$build_context" || error "Failed to build core image"
            
            
        # Check if this is truly a first-time setup (no projects exist)
        local project_count=$(ls -1d "$HOME/.claudebox/projects"/*/ 2>/dev/null | wc -l)
        
        if [[ $project_count -eq 0 ]]; then
            # First-time user - show welcome menu
            show_first_time_welcome
            exit 0
        fi
        
        # Existing user - core rebuilt, continue normal flow
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Core image built, continuing with normal flow..." >&2
        fi
    fi
    
    # If running from installer, show appropriate message and exit
    if [[ "${CLAUDEBOX_INSTALLER_RUN:-}" == "true" ]]; then
        # Check if this is first install or update
        if [[ -f "$HOME/.claudebox/.installed" ]]; then
            # Update - just show brief message
            logo_small
            echo
            cecho "ClaudeBox updated successfully!" "$GREEN"
            echo
            echo "Run 'claudebox' to start using ClaudeBox."
            echo
        else
            # First install - check if they have projects
            local project_count=$(ls -1d "$HOME/.claudebox/projects"/*/ 2>/dev/null | wc -l)
            if [[ $project_count -eq 0 ]]; then
                # Show full welcome
                show_first_time_welcome
            else
                # Has projects but no .installed file
                logo_small
                echo
                cecho "ClaudeBox installed successfully!" "$GREEN"
                echo
                echo "Run 'claudebox' to start using ClaudeBox."
                echo
            fi
            touch "$HOME/.claudebox/.installed"
        fi
        exit 0
    fi
    
    # Step 6: Initialize project directory (creates parent with profiles.ini)
    init_project_dir "$PROJECT_DIR"
    PROJECT_PARENT_DIR=$(get_parent_dir "$PROJECT_DIR")
    export PROJECT_PARENT_DIR
    
    # Step 7: Handle rebuild if requested (will use IMAGE_NAME from step 8)
    local rebuild_requested="${REBUILD:-false}"
    
    # Step 8: Always set up project variables
    # Get the actual parent folder name for the project
    local parent_folder_name=$(generate_parent_folder_name "$PROJECT_DIR")
    
    # Get the slot to use (might be empty)
    project_folder_name=$(get_project_folder_name "$PROJECT_DIR")
    
    # Early exit if command needs Docker but no slots exist
    if [[ "$project_folder_name" == "NONE" ]] && [[ "$cmd_requirements" == "docker" ]]; then
        show_no_slots_menu
        exit 1
    fi
    
    # Always set IMAGE_NAME based on parent folder
    IMAGE_NAME=$(get_image_name)
    export IMAGE_NAME
    
    # Set PROJECT_SLOT_DIR if we have a slot
    if [[ -n "$project_folder_name" ]] && [[ "$project_folder_name" != "NONE" ]]; then
        PROJECT_SLOT_DIR="$PROJECT_PARENT_DIR/$project_folder_name"
        export PROJECT_SLOT_DIR
    fi
    
    # Handle rebuild if requested
    if [[ "$rebuild_requested" == "true" ]]; then
        warn "Forcing full rebuild of ClaudeBox Docker image..."
        rm -f "$PROJECT_PARENT_DIR/.docker_layer_checksums"
        docker rmi -f "$IMAGE_NAME" 2>/dev/null || true
    fi
    
    # Step 9: Run pre-flight validation for commands that need Docker
    if [[ -n "${CLI_SCRIPT_COMMAND}" ]]; then
        local cmd_req=$(get_command_requirements "${CLI_SCRIPT_COMMAND}")
        # Only run pre-flight for commands that need Docker or image
        if [[ "$cmd_req" == "docker" ]] || [[ "$cmd_req" == "image" ]]; then
            if ! preflight_check "${CLI_SCRIPT_COMMAND}" "${CLI_PASS_THROUGH[@]}"; then
                # Pre-flight check failed and printed error
                exit 1
            fi
        fi
    fi
    
    # Step 10: Check command requirements
    local cmd_requirements="none"
    
    if [[ -n "${CLI_SCRIPT_COMMAND}" ]]; then
        # Pass the first pass-through arg as potential subcommand
        local first_arg="${CLI_PASS_THROUGH[0]:-}"
        cmd_requirements=$(get_command_requirements "${CLI_SCRIPT_COMMAND}" "$first_arg")
    else
        # No script command means we're running claude - needs Docker
        cmd_requirements="docker"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] Command requirements: $cmd_requirements" >&2
    fi
    
    # Step 10a: Set IMAGE_NAME if needed (for "image" or "docker" requirements)
    if [[ "$cmd_requirements" != "none" ]]; then
        # Commands that need image name should have it set even without Docker
        IMAGE_NAME=$(get_image_name)
        export IMAGE_NAME
    fi
    
    # Step 10b: Build Docker image if needed (only for "docker" requirements)
    if [[ "$cmd_requirements" == "docker" ]]; then
        # Check if rebuild needed
        local need_rebuild=false
        
        if [[ "${REBUILD:-false}" == "true" ]] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
            need_rebuild=true
        elif needs_docker_rebuild "$PROJECT_DIR" "$IMAGE_NAME"; then
            need_rebuild=true
            info "Detected changes in Docker build files, rebuilding..."
        else
            # Check profiles
            local profiles_file="$PROJECT_PARENT_DIR/profiles.ini"
            if [[ -f "$profiles_file" ]]; then
                # Read current profiles
                local current_profiles=()
                while IFS= read -r line; do
                    [[ -n "$line" ]] && current_profiles+=("$line")
                done < <(read_profile_section "$profiles_file" "profiles")
                
                # Separate Python-only profiles from Docker-affecting profiles
                local docker_profiles=()
                local python_only_profiles=("python" "ml" "datascience")
                
                for profile in "${current_profiles[@]}"; do
                    local is_python_only=false
                    for py_profile in "${python_only_profiles[@]}"; do
                        if [[ "$profile" == "$py_profile" ]]; then
                            is_python_only=true
                            break
                        fi
                    done
                    if [[ "$is_python_only" == "false" ]]; then
                        docker_profiles+=("$profile")
                    fi
                done
                
                # Calculate hash only for Docker-affecting profiles
                local docker_profiles_hash=""
                if [[ ${#docker_profiles[@]} -gt 0 ]]; then
                    docker_profiles_hash=$(printf '%s\n' "${docker_profiles[@]}" | sort | cksum | cut -d' ' -f1)
                fi
                
                local image_profiles_hash=$(docker inspect "$IMAGE_NAME" --format '{{index .Config.Labels "claudebox.profiles"}}' 2>/dev/null || echo "")
                
                if [[ "$docker_profiles_hash" != "$image_profiles_hash" ]]; then
                    info "Docker-affecting profiles changed, rebuilding..."
                    docker rmi -f "$IMAGE_NAME" 2>/dev/null || true
                    need_rebuild=true
                fi
            fi
        fi
        
        if [[ "$need_rebuild" == "true" ]]; then
            # Set rebuild timestamp to bust Docker cache when templates change
            export CLAUDEBOX_REBUILD_TIMESTAMP=$(date +%s)
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] About to build Docker image..." >&2
            fi
            build_docker_image
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] Docker build completed, continuing..." >&2
            fi
        fi
    fi
    
    # Step 11: Set up shared resources
    setup_shared_commands
    setup_claude_agent_command
    
    # Step 12: Fix permissions if needed
    if [[ ! -d "$HOME/.claudebox" ]]; then
        mkdir -p "$HOME/.claudebox"
    fi
    if [[ ! -w "$HOME/.claudebox" ]]; then
        warn "Fixing .claudebox permissions..."
        sudo chown -R "$USER:$USER" "$HOME/.claudebox" || true
    fi
    
    # Step 13: Create allowlist if needed
    if [[ -n "${PROJECT_PARENT_DIR:-}" ]]; then
        local allowlist_file="$PROJECT_PARENT_DIR/allowlist"
        if [[ ! -f "$allowlist_file" ]]; then
            # Root directory is where the script is located
            local root_dir="$SCRIPT_DIR"
            
            local allowlist_template="${root_dir}/build/allowlist"
            if [[ -f "$allowlist_template" ]]; then
                cp "$allowlist_template" "$allowlist_file" || error "Failed to copy allowlist template"
            fi
        fi
    fi
    
    # Step 14: Single dispatch point
    if [[ -n "${CLI_SCRIPT_COMMAND}" ]]; then
        # Script command - dispatch on host
        # Pass control flags and pass-through args to dispatch_command
        dispatch_command "${CLI_SCRIPT_COMMAND}" "${CLI_PASS_THROUGH[@]}" "${CLI_CONTROL_FLAGS[@]}"
        exit $?
    else
        # No script command - running Claude interactively
        # This is where we load saved default flags
        if [[ -n "${PROJECT_SLOT_DIR:-}" ]]; then
            local slot_name=$(basename "$PROJECT_SLOT_DIR")
            # parent_folder_name already set in step 8
            local container_name="claudebox-${parent_folder_name}-${slot_name}"
            
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] PROJECT_SLOT_DIR=$PROJECT_SLOT_DIR" >&2
                echo "[DEBUG] slot_name=$slot_name" >&2
                echo "[DEBUG] parent_folder_name=$parent_folder_name" >&2
                echo "[DEBUG] container_name=$container_name" >&2
            fi
            
            # Sync commands before launching container
            sync_commands_to_project "$PROJECT_PARENT_DIR"
            
            # Load saved default flags ONLY for interactive Claude (no command)
            local saved_flags=()
            if [[ -f "$HOME/.claudebox/default-flags" ]]; then
                while IFS= read -r flag; do
                    [[ -n "$flag" ]] && saved_flags+=("$flag")
                done < "$HOME/.claudebox/default-flags"
                
                # Re-parse all arguments with saved flags included
                if [[ ${#saved_flags[@]} -gt 0 ]]; then
                    # Combine original args with saved flags
                    local all_args=("${original_args[@]}" "${saved_flags[@]}")
                    
                    # Re-parse to properly sort flags
                    parse_cli_args "${all_args[@]}"
                    process_host_flags
                    
                    if [[ "$VERBOSE" == "true" ]]; then
                        echo "[DEBUG] Re-parsed with saved flags" >&2
                        debug_parsed_args
                    fi
                fi
            fi
            
            # Check if stdin is not a terminal (i.e., we're receiving piped input)
            # and -p/--print flag isn't already present
            local has_print_flag=false
            for arg in "${CLI_PASS_THROUGH[@]}"; do
                if [[ "$arg" == "-p" ]] || [[ "$arg" == "--print" ]]; then
                    has_print_flag=true
                    break
                fi
            done
            
            if [[ "$VERBOSE" == "true" ]]; then
                if [[ -t 0 ]]; then
                    echo "[DEBUG] stdin IS a terminal" >&2
                else
                    echo "[DEBUG] stdin is NOT a terminal" >&2
                fi
                echo "[DEBUG] has_print_flag=$has_print_flag" >&2
            fi
            
            if [[ ! -t 0 ]] && [[ "$has_print_flag" == "false" ]]; then
                # Read piped input and pass as argument to -p
                if [[ "$VERBOSE" == "true" ]]; then
                    echo "[DEBUG] Reading piped input for -p flag" >&2
                fi
                local piped_input
                piped_input=$(cat)
                run_claudebox_container "$container_name" "interactive" "${CLI_CONTROL_FLAGS[@]}" "-p" "$piped_input" "${CLI_PASS_THROUGH[@]}"
            else
                run_claudebox_container "$container_name" "interactive" "${CLI_CONTROL_FLAGS[@]}" "${CLI_PASS_THROUGH[@]}"
            fi
        else
            show_no_slots_menu
        fi
    fi
}

# Helper function to build Docker image
build_docker_image() {
    local build_context="$HOME/.claudebox/docker-build-context"
    mkdir -p "$build_context"
    
    # Copy build files to Docker build context
    # Root directory is where the script is located
    local root_dir="$SCRIPT_DIR"
    
    cp "${root_dir}/build/docker-entrypoint" "$build_context/docker-entrypoint.sh" || error "Failed to copy docker-entrypoint.sh"
    cp "${root_dir}/build/init-firewall" "$build_context/init-firewall" || error "Failed to copy init-firewall"
    cp "${root_dir}/build/generate-tools-readme" "$build_context/generate-tools-readme" || error "Failed to copy generate-tools-readme"
    cp "${root_dir}/lib/tools-report.sh" "$build_context/tools-report.sh" || error "Failed to copy tools-report.sh"
    cp "${root_dir}/build/dockerignore" "$build_context/.dockerignore" || error "Failed to copy .dockerignore"
    chmod +x "$build_context/docker-entrypoint.sh" "$build_context/init-firewall" "$build_context/generate-tools-readme"
    
    
    # Build profile installations
    local profiles_file="$PROJECT_PARENT_DIR/profiles.ini"
    local profile_installations=""
    local profile_hash=""
    local profiles_file_hash=""
    
    if [[ -f "$profiles_file" ]]; then
        profiles_file_hash=$(crc32_file "$profiles_file")
        
        local current_profiles=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && current_profiles+=("$line")
        done < <(read_profile_section "$profiles_file" "profiles")
        
        # Generate profile installations
        for profile in "${current_profiles[@]}"; do
            profile=$(echo "$profile" | tr -d '[:space:]')
            [[ -z "$profile" ]] && continue
            
            # Convert hyphens to underscores for function names
            local profile_fn="get_profile_${profile//-/_}"
            if type -t "$profile_fn" >/dev/null; then
                profile_installations+=$'\n'"$($profile_fn)"
            fi
        done
        
        # Calculate hash only for Docker-affecting profiles
        local docker_profiles=()
        local python_only_profiles=("python" "ml" "datascience")
        
        for profile in "${current_profiles[@]}"; do
            local is_python_only=false
            for py_profile in "${python_only_profiles[@]}"; do
                if [[ "$profile" == "$py_profile" ]]; then
                    is_python_only=true
                    break
                fi
            done
            if [[ "$is_python_only" == "false" ]]; then
                docker_profiles+=("$profile")
            fi
        done
        
        if [[ ${#docker_profiles[@]} -gt 0 ]]; then
            profile_hash=$(printf '%s\n' "${docker_profiles[@]}" | sort | cksum | cut -d' ' -f1)
        fi
    fi
    
    # Create Dockerfile
    local dockerfile="$build_context/Dockerfile"
    
    # Use the minimal project Dockerfile template
    local base_dockerfile
    base_dockerfile=$(tr -d '\r' < "${root_dir}/build/Dockerfile.project") || error "Failed to read project Dockerfile template"
    
    # Build labels
    local project_folder_name
    project_folder_name=$(generate_parent_folder_name "$PROJECT_DIR")
    local labels="\
LABEL claudebox.profiles=\"$profile_hash\"
LABEL claudebox.profiles.crc=\"$profiles_file_hash\"
LABEL claudebox.project=\"$project_folder_name\""
    
    # Replace placeholders in the project template
    local final_dockerfile="$base_dockerfile"
    
    # Replace WHOLE lines that contain the placeholders (with optional spaces)
    local final_dockerfile
    final_dockerfile=$(awk -v pi="$profile_installations" -v lbs="$labels" '
    # If the whole line is {{ PROFILE_INSTALLATIONS }}, print injected block and skip
    /^[[:space:]]*\{\{[[:space:]]*PROFILE_INSTALLATIONS[[:space:]]*\}\}[[:space:]]*$/ { print pi; next }
    # If the whole line is {{ LABELS }}, print labels block and skip
    /^[[:space:]]*\{\{[[:space:]]*LABELS[[:space:]]*\}\}[[:space:]]*$/ { print lbs; next }
    # Otherwise, print the line unchanged
    { print }
    ' <<<"$base_dockerfile") || error "Failed to apply Dockerfile substitutions"

    # Guard: ensure no unreplaced placeholders remain
    if grep -q '{{PROFILE_INSTALLATIONS}}' <<<"$final_dockerfile" || grep -q '{{LABELS}}' <<<"$final_dockerfile"; then
    error "Unreplaced placeholders remain in generated Dockerfile"
    fi

    printf '%s' "$final_dockerfile" > "$dockerfile"
    
    # Build the image
    run_docker_build "$dockerfile" "$build_context"
    
    # Save checksums
    save_docker_layer_checksums "$PROJECT_DIR"
}

# Run main with user arguments only
main "$@"
