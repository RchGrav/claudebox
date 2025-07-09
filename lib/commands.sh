#!/usr/bin/env bash
# The canonical place where CLI arguments map to functions.

# Show menu when no slots exist
show_no_slots_menu() {
    # Reuse the same options and commands from help
    local our_options="  --verbose                       Show detailed output
  --enable-sudo                   Enable sudo without password
  --disable-firewall              Disable network restrictions"
    
    local our_commands="  create                          Create new authenticated container slot
  slots                           List all container slots
  profiles                        List all available profiles
  projects                        List all projects with paths
  add <profiles...>               Add development profiles
  remove <profiles...>            Remove development profiles
  install <packages>              Install apt packages
  save [flags...]                 Save default flags
  allowlist                       Show/edit firewall allowlist
  info                            Show comprehensive project info
  clean                           Menu of cleanup tasks
  help                            Display help for command"
    
    # Show colored header
    echo
    logo header
    echo "Usage: claudebox [OPTIONS] [COMMAND]"
    echo
    echo "No container slots found for this project."
    echo
    echo "Options:"
    echo "  -h, --help                      Display help for command"
    echo "$our_options"
    echo
    echo "Commands:"
    echo "$our_commands"
    echo
    cecho "To get started: claudebox create in the base of your folder." "$YELLOW"
    echo
}

# Show help function
show_help() {
    # Our additional options to inject
    local our_options="  --verbose                       Show detailed output
  --enable-sudo                   Enable sudo without password
  --disable-firewall              Disable network restrictions"
    
    # Our additional commands to append
    local our_commands="  profiles                        List all available profiles
  projects                        List all projects with paths
  add <profiles...>               Add development profiles
  remove <profiles...>            Remove development profiles
  install <packages>              Install apt packages
  save [flags...]                 Save default flags
  shell                           Open transient shell
  shell admin                     Open admin shell (sudo enabled)
  allowlist                       Show/edit firewall allowlist
  info                            Show comprehensive project info
  clean                           Menu of cleanup tasks
  create                          Create new authenticated container slot
  slots                           List all container slots
  slot <number>                   Launch a specific container slot"
    
    if [[ -n "${IMAGE_NAME:-}" ]] && docker image inspect "$IMAGE_NAME" &>/dev/null; then
        # Get Claude's help and blend our additions
        local claude_help=$(docker run --rm "$IMAGE_NAME" claude --help 2>&1 | grep -v "iptables")
        
        # Process and combine everything in memory
        local full_help=$(echo "$claude_help" | \
            sed '1s/claude/claudebox/g' | \
            sed '/^Commands:/i\
  --verbose                       Show detailed output\
  --enable-sudo                   Enable sudo without password\
  --disable-firewall              Disable network restrictions\
' | \
            sed '$ a\
  profiles                        List all available profiles\
  projects                        List all projects with paths\
  add <profiles...>               Add development profiles\
  remove <profiles...>            Remove development profiles\
  install <packages>              Install apt packages\
  save [flags...]                 Save default flags\
  shell                           Open transient shell\
  shell admin                     Open admin shell (sudo enabled)\
  allowlist                       Show/edit firewall allowlist\
  info                            Show comprehensive project info\
  clean                           Menu of cleanup tasks\
  create                          Create new authenticated container slot\
  slots                           List all container slots\
  slot <number>                   Launch a specific container slot')
        
        # Output everything at once
        echo
        logo_small
        echo
        echo "$full_help"
    else
        # No Docker image - show compact menu
        echo
        logo_small
        echo
        echo "Usage: claudebox [OPTIONS] [COMMAND]"
        echo
        echo "Docker Environment for Claude CLI"
        echo
        echo "Options:"
        echo "  -h, --help                      Display help for command"
        echo "$our_options"
        echo
        echo "Commands:"
        echo "$our_commands"
        echo
        warn "Run 'claudebox create' to get started!"
    fi
}

# --- public -------------------------------------------------------------------
dispatch_command() {
  local cmd="${1:-help}"; shift || true
  [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] dispatch_command called with: cmd='$cmd' remaining args='$@'" >&2
  case "${cmd}" in
    help|-h|--help)   _cmd_help "$@" ;;
    profiles)         _cmd_profiles "$@" ;;
    projects)         _cmd_projects "$@" ;;
    profile)          _cmd_profile "$@" ;;
    add)              _cmd_add "$@" ;;
    remove)           _cmd_remove "$@" ;;
    install)          _cmd_install "$@" ;;
    save)             _cmd_save "$@" ;;
    shell)            _cmd_shell "$@" ;;
    allowlist)        _cmd_allowlist "$@" ;;
    info)             _cmd_info "$@" ;;
    clean)            _cmd_clean "$@" ;;
    unlink)           _cmd_unlink "$@" ;;
    rebuild)          _cmd_rebuild "$@" ;;
    update)           _cmd_update "$@" ;;
    create)           _cmd_create "$@" ;;
    slots)            _cmd_slots "$@" ;;
    slot)             _cmd_slot "$@" ;;
    revoke)           _cmd_revoke "$@" ;;
    config|mcp|migrate-installer) _cmd_special "$cmd" "$@" ;;
    undo)             _cmd_undo "$@" ;;
    redo)             _cmd_redo "$@" ;;
    *)                _forward_to_container "${cmd}" "$@" ;;
  esac
  local exit_code=$?
  [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] dispatch_command returning with exit code: $exit_code" >&2
  return $exit_code
}

# --- individual handlers ------------------------------------------------------

_cmd_help() {
    # Set up IMAGE_NAME if we're in a project directory
    if [[ -n "${PROJECT_DIR:-}" ]]; then
        # Initialize project directory to ensure parent exists
        init_project_dir "$PROJECT_DIR"
        IMAGE_NAME=$(get_image_name 2>/dev/null || echo "")
    fi
    
    show_help
    exit 0
}

_cmd_profiles() {
    # Get current profiles
    local current_profiles=($(get_current_profiles))
    
    # Show currently enabled profiles
    if [[ ${#current_profiles[@]} -gt 0 ]]; then
        cecho "Currently Enabled Profiles:" "$YELLOW"
        echo -e "  ${current_profiles[*]}"
        echo
    fi
    
    cecho "Available ClaudeBox Profiles:" "$CYAN"
    echo
    for profile in $(get_all_profile_names | tr ' ' '\n' | sort); do
        local desc=$(get_profile_description "$profile")
        local marker=""
        # Check if profile is currently enabled
        for enabled in "${current_profiles[@]}"; do
            if [[ "$enabled" == "$profile" ]]; then
                marker=" ${YELLOW}[ENABLED]${NC}"
                break
            fi
        done
        echo -e "  ${GREEN}$profile${NC} - $desc$marker"
    done
    exit 0
}

_cmd_projects() {
    cecho "ClaudeBox Projects:" "$CYAN"
    echo
    printf "%10s  %s  %s\n" "Size" "🐳" "Path"
    printf "%10s  %s  %s\n" "----" "--" "----"

    if ! list_all_projects; then
        echo
        warn "No ClaudeBox projects found."
        echo
        cecho "Start a new project:" "$GREEN"
        echo "  cd /your/project/directory"
        echo "  claudebox"
    fi
    echo
    exit 0
}

_cmd_profile() {
    # Profile menu/help
    cecho "ClaudeBox Profile Management:" "$CYAN"
    echo
    echo -e "  ${GREEN}profiles${NC}                 Show all available profiles"
    echo -e "  ${GREEN}add <names...>${NC}           Add development profiles"
    echo -e "  ${GREEN}remove <names...>${NC}        Remove development profiles"  
    echo -e "  ${GREEN}add status${NC}               Show current project's profiles"
    echo
    cecho "Examples:" "$YELLOW"
    echo "  claudebox profiles              # See all available profiles"
    echo "  claudebox add python rust       # Add Python and Rust profiles"
    echo "  claudebox remove rust           # Remove Rust profile"
    echo "  claudebox add status            # Check current project's profiles"
    exit 0
}

_cmd_add() {
    # Profile management doesn't need a slot, just the parent directory
    init_project_dir "$PROJECT_DIR"
    local profile_file
    profile_file=$(get_profile_file_path)

    # Check for special subcommands
    case "${1:-}" in
        status|--status|-s)
            cecho "Project: $PROJECT_DIR" "$CYAN"
            echo
            if [[ -f "$profile_file" ]]; then
                local current_profiles=()
                while IFS= read -r line; do
                    [[ -n "$line" ]] && current_profiles+=("$line")
                done < <(read_profile_section "$profile_file" "profiles")
                if [[ ${#current_profiles[@]} -gt 0 ]]; then
                    cecho "Active profiles: ${current_profiles[*]}" "$GREEN"
                else
                    cecho "No profiles installed" "$YELLOW"
                fi

                local current_packages=()
                local current_packages=()
                while IFS= read -r line; do
                    [[ -n "$line" ]] && current_packages+=("$line")
                done < <(read_profile_section "$profile_file" "packages")
                if [[ ${#current_packages[@]} -gt 0 ]]; then
                    echo "Extra packages: ${current_packages[*]}"
                fi
            else
                cecho "No profiles configured for this project" "$YELLOW"
            fi
            exit 0
            ;;
    esac

    # Process profile names
    local selected=() remaining=()
    while [[ $# -gt 0 ]]; do
        if profile_exists "$1"; then
            selected+=("$1")
            shift
        else
            remaining=("$@")
            break
        fi
    done

    [[ ${#selected[@]} -eq 0 ]] && error "No valid profiles specified\nRun 'claudebox profiles' to see available profiles"

    update_profile_section "$profile_file" "profiles" "${selected[@]}"

    local all_profiles=()
    local all_profiles=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && all_profiles+=("$line")
    done < <(read_profile_section "$profile_file" "profiles")

    cecho "Profile: $PROJECT_DIR" "$CYAN"
    cecho "Adding profiles: ${selected[*]}" "$PURPLE"
    if [[ ${#all_profiles[@]} -gt 0 ]]; then
        cecho "All active profiles: ${all_profiles[*]}" "$GREEN"
    fi
    echo
    warn "The Docker image will be rebuilt with new profiles on next run."
    echo

    if [[ ${#remaining[@]} -gt 0 ]]; then
        set -- "${remaining[@]}"
    fi
}

_cmd_remove() {
    # Profile management doesn't need a slot, just the parent directory
    init_project_dir "$PROJECT_DIR"
    local profile_file
    profile_file=$(get_profile_file_path)

    # Read current profiles
    local current_profiles=()
    if [[ -f "$profile_file" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && current_profiles+=("$line")
        done < <(read_profile_section "$profile_file" "profiles")
    fi

    # Show currently enabled profiles if no arguments
    if [[ $# -eq 0 ]]; then
        if [[ ${#current_profiles[@]} -gt 0 ]]; then
            cecho "Currently Enabled Profiles:" "$YELLOW"
            echo -e "  ${current_profiles[*]}"
            echo
            echo "Usage: claudebox remove <profile1> [profile2] ..."
        else
            echo "No profiles currently enabled."
        fi
        exit 1
    fi

    # Get list of profiles to remove
    local to_remove=()
    while [[ $# -gt 0 ]]; do
        if profile_exists "$1"; then
            to_remove+=("$1")
            shift
        else
            warn "Unknown profile: $1"
            shift
        fi
    done

    [[ ${#to_remove[@]} -eq 0 ]] && error "No valid profiles specified to remove"

    # Remove specified profiles
    local new_profiles=()
    for profile in "${current_profiles[@]}"; do
        local keep=true
        for remove in "${to_remove[@]}"; do
            if [[ "$profile" == "$remove" ]]; then
                keep=false
                break
            fi
        done
        [[ "$keep" == "true" ]] && new_profiles+=("$profile")
    done

    # Write back the filtered profiles
    {
        echo "[profiles]"
        for profile in "${new_profiles[@]}"; do
            echo "$profile"
        done
        echo ""
        
        # Preserve packages section if it exists
        if [[ -f "$profile_file" ]] && grep -q "^\[packages\]" "$profile_file"; then
            echo "[packages]"
            while IFS= read -r line; do
                echo "$line"
            done < <(read_profile_section "$profile_file" "packages")
        fi
    } > "${profile_file}.tmp" && mv "${profile_file}.tmp" "$profile_file"

    cecho "Profile: $PROJECT_DIR" "$CYAN"
    cecho "Removed profiles: ${to_remove[*]}" "$PURPLE"
    if [[ ${#new_profiles[@]} -gt 0 ]]; then
        cecho "Remaining profiles: ${new_profiles[*]}" "$GREEN"
    else
        cecho "No profiles remaining" "$YELLOW"
    fi
    echo
    warn "The Docker image will be rebuilt with updated profiles on next run."
    echo
}

_cmd_save() {
    local defaults_file="$HOME/.claudebox/default-flags"

    if [[ $# -eq 0 ]]; then
        if [[ -f "$defaults_file" ]]; then
            rm -f "$defaults_file"
            success "Cleared saved default flags"
        else
            info "No saved default flags to clear"
        fi
    else
        mkdir -p "$HOME/.claudebox"
        printf '%s\n' "$@" > "$defaults_file"
        success "Saved default flags: $*"
    fi
    exit 0
}

_cmd_install() {
    [[ $# -eq 0 ]] && error "No packages specified. Usage: claudebox install <package1> <package2> ..."

    local profile_file
    profile_file=$(get_profile_file_path)

    update_profile_section "$profile_file" "packages" "$@"

    local all_packages=()
    local all_packages=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && all_packages+=("$line")
    done < <(read_profile_section "$profile_file" "packages")

    cecho "Profile: $PROJECT_DIR" "$CYAN"
    cecho "Installing packages: $*" "$PURPLE"
    if [[ ${#all_packages[@]} -gt 0 ]]; then
        cecho "All packages: ${all_packages[*]}" "$GREEN"
    fi
    echo
}

_cmd_unlink() {
    if [[ -L "$LINK_TARGET" ]]; then
        rm -f "$LINK_TARGET"
        success "Removed claudebox symlink from $(dirname "$LINK_TARGET")"
    else
        info "No claudebox symlink found at $LINK_TARGET"
    fi
    exit 0
}

_cmd_shell() {
    # Set up slot variables if not already set
    if [[ -z "${IMAGE_NAME:-}" ]]; then
        local project_folder_name
        project_folder_name=$(get_project_folder_name "$PROJECT_DIR" 2>/dev/null || echo "NONE")
        
        if [[ "$project_folder_name" == "NONE" ]]; then
            error "No container slots available. Please run 'claudebox create' to create a container slot."
        fi
        
        IMAGE_NAME="claudebox-${project_folder_name}"
        PROJECT_CLAUDEBOX_DIR="$PROJECT_PARENT_DIR/$project_folder_name"
        export PROJECT_CLAUDEBOX_DIR
    fi
    
    # Check if image exists
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        error "No Docker image found for this project.\nRun 'claudebox' first to build the image."
    fi
    
    local persist_mode=false
    local shell_flags=()
    
    # Check if first arg is "admin"
    if [[ "${1:-}" == "admin" ]]; then
        persist_mode=true
        shift
        # In admin mode, automatically enable sudo and disable firewall
        shell_flags+=("--enable-sudo" "--disable-firewall")
    fi
    
    # Process remaining flags (only for non-persist mode)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --enable-sudo|--disable-firewall)
                if [[ "$persist_mode" == "false" ]]; then
                    shell_flags+=("$1")
                fi
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    echo
    logo
    echo
    
    # Run container for shell
    if [[ "$persist_mode" == "true" ]]; then
        cecho "Administration Mode" "$YELLOW"
        echo "Sudo enabled, firewall disabled."
        echo "Changes will be saved to the image when you exit."
        echo
        
        # Create a named container for admin mode so we can commit it
        local project_folder_name
        project_folder_name=$(get_project_folder_name "$PROJECT_DIR")
        local temp_container="claudebox-shell-${project_folder_name}-$$"
        
        # Ensure cleanup runs on any exit (including Ctrl-C)
        cleanup_admin() {
            docker commit "$temp_container" "$IMAGE_NAME" >/dev/null 2>&1
            docker rm -f "$temp_container" >/dev/null 2>&1
        }
        trap cleanup_admin EXIT
        
        run_claudebox_container "$temp_container" "interactive" shell "${shell_flags[@]}"
        
        # Commit changes back to image
        fillbar
        docker commit "$temp_container" "$IMAGE_NAME" >/dev/null
        docker rm -f "$temp_container" >/dev/null 2>&1
        fillbar stop
        success "Changes saved to image!"
    else
        # Regular shell mode - just run without committing
        run_claudebox_container "" "interactive" shell "${shell_flags[@]}"
    fi
    
    exit 0
}

_cmd_allowlist() {
    # Allowlist is stored in parent directory, not slot directory
    local allowlist_file="$PROJECT_PARENT_DIR/allowlist"

    cecho "🔒 ClaudeBox Firewall Allowlist" "$CYAN"
    echo
    cecho "Current Project: $PROJECT_DIR" "$WHITE"
    echo

    if [[ -f "$allowlist_file" ]]; then
        cecho "Allowlist file:" "$GREEN"
        echo "  $allowlist_file"
        echo
        cecho "Allowed domains:" "$CYAN"
        # Display allowlist contents
        while IFS= read -r line; do
            if [[ -n "$line" ]] && [[ ! "$line" =~ ^#.* ]]; then
                echo "  $line"
            fi
        done < "$allowlist_file"
        echo
    else
        cecho "Allowlist file:" "$YELLOW"
        echo "  Not yet created (will be created on first run)"
        echo "  Location: $allowlist_file"
    fi

    echo
    cecho "Default Allowed Domains:" "$CYAN"
    echo "  api.anthropic.com, console.anthropic.com, statsig.anthropic.com, sentry.io"
    echo
    cecho "To edit allowlist:" "$YELLOW"
    echo "  \$EDITOR $allowlist_file"
    echo
    cecho "Note:" "$WHITE"
    echo "  Changes take effect on next container start"
    echo "  Use --disable-firewall flag to bypass all restrictions"

    exit 0
}

_cmd_clean() {
    case "${1:-}" in
        all)
            warn "Complete Docker cleanup: removing all claudebox containers, images, volumes, and cache..."
            # Remove all claudebox containers
            docker ps -a --filter "label=claudebox.project" -q | xargs -r docker rm -f 2>/dev/null || true
            docker ps -a --format "{{.Names}}" | grep "^claudebox-" | xargs -r docker rm -f 2>/dev/null || true

            # Remove ALL claudebox images (including base)
            docker images --filter "reference=claudebox-*" -q | xargs -r docker rmi -f 2>/dev/null || true
            docker images --filter "reference=claudebox" -q | xargs -r docker rmi -f 2>/dev/null || true

            # Remove dangling images
            docker images -f "dangling=true" -q | xargs -r docker rmi -f 2>/dev/null || true

            # Prune build cache
            docker builder prune -af 2>/dev/null || true

            # Remove volumes
            docker volume ls -q --filter "name=claudebox" | xargs -r docker volume rm 2>/dev/null || true

            success "Docker cleanup complete!"
            echo
            docker system df
            exit 0
            ;;
        image)
            warn "Removing ClaudeBox containers and image..."
            # Remove any containers from this image
            docker ps -a --filter "label=claudebox.project" -q | xargs -r docker rm -f 2>/dev/null || true
            # Remove orphaned containers from images that no longer exist
            # This is safer as it only removes containers whose images are gone
            docker ps -a --filter "status=exited" --format "{{.ID}} {{.Image}}" | while read id image; do
                if ! docker image inspect "$image" >/dev/null 2>&1; then
                    docker rm -f "$id" 2>/dev/null || true
                fi
            done
           # Remove all claudebox project images
           docker images --filter "reference=claudebox-*" -q | xargs -r docker rmi -f 2>/dev/null || true
            success "Containers and image removed! Build cache preserved."
            echo
            docker system df
            exit 0
            ;;
        cache)
            warn "Cleaning Docker build cache..."
            docker builder prune -af
            success "Build cache cleaned!"
            echo
            docker system df
            exit 0
            ;;
        volumes)
            warn "Removing ClaudeBox-related volumes..."
            docker volume ls -q --filter "name=claudebox" | xargs -r docker volume rm 2>/dev/null || true
            docker volume prune -f 2>/dev/null || true
            success "Volumes cleaned!"
            echo
            docker system df
            exit 0
            ;;
        containers)
            warn "Cleaning ClaudeBox containers..."
            # Remove any containers from this image
            docker ps -a --filter "label=claudebox.project" -q | xargs -r docker rm -f 2>/dev/null || true
            # Remove orphaned containers from images that no longer exist
            # This is safer as it only removes containers whose images are gone
            docker ps -a --filter "status=exited" --format "{{.ID}} {{.Image}}" | while read id image; do
                if ! docker image inspect "$image" >/dev/null 2>&1; then
                    docker rm -f "$id" 2>/dev/null || true
                fi
            done
            success "Containers cleaned!"
            echo
            docker system df
            exit 0
            ;;
        dangling)
            warn "Removing dangling images and unused containers..."
            docker image prune -f
            docker container prune -f
            success "Dangling resources cleaned!"
            echo
            docker system df
            exit 0
            ;;
        logs)
            warn "Clearing Docker container logs..."
            docker ps -a --filter "label=claudebox.project" -q | while read -r container; do
                docker logs "$container" >/dev/null 2>&1 && echo -n | docker logs "$container" 2>/dev/null || true
            done
            success "Container logs cleared!"
            echo
            docker system df
            exit 0
            ;;
        project)
            shift
            local target_path="$PROJECT_DIR"
            local project_folder_name

            if [[ $# -gt 0 ]] && [[ "${1:0:1}" != "-" ]] && [[ "$1" != "all" && "$1" != "data" && "$1" != "docker" && "$1" != "profiles" && "$1" != "tools" ]]; then
                target_path="$1"
                shift

                project_folder_name=$(resolve_project_path "$target_path")
                if [[ -z "$project_folder_name" ]]; then
                    error "No ClaudeBox project found at: $target_path"
                fi
            else
                project_folder_name=$(get_project_folder_name "$PROJECT_DIR")
            fi

            local project_claudebox_dir="$HOME/.claudebox/projects/$project_folder_name"
            local image_name="claudebox-${project_folder_name}"

            local display_path="$PROJECT_DIR"
            local config_file="$project_claudebox_dir/profiles.ini"
            if [[ -f "$config_file" ]]; then
                local path_value=$(read_config_value "$config_file" "project" "path")
                [[ -n "$path_value" ]] && display_path="$path_value"
            fi

            case "${1:-}" in
                profiles|tools)
                    warn "Clearing profile configuration for: $display_path"
                    if [[ -f "$config_file" ]]; then
                        {
                            awk '/^\[profiles\]/ { profiles=1; print; print ""; next }
                                 /^\[packages\]/ { packages=1; print; print ""; next }
                                 /^\[/ { profiles=0; packages=0 }
                                 !profiles && !packages { print }' "$config_file"
                        } > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
                        success "Cleared profile configuration"
                    else
                        info "No configuration file found"
                    fi
                    ;;
                data)
                    warn "Removing project data for: $display_path"
                    if [[ -d "$project_claudebox_dir" ]]; then
                        rm -rf "$project_claudebox_dir"
                        success "Removed project data folder: $project_claudebox_dir"
                    else
                        info "No project data folder found"
                    fi
                    ;;
                docker)
                    warn "Removing Docker image for: $display_path"
                    docker rmi -f "$image_name" 2>/dev/null && \
                        success "Removed Docker image: $image_name" || \
                        info "No Docker image found for this project"
                    ;;
                all)
                    warn "Removing all project artifacts for: $display_path"
                    if [[ -f "$config_file" ]]; then
                        rm -f "$config_file"
                        success "Removed profile configuration"
                    fi
                    if [[ -d "$project_claudebox_dir" ]]; then
                        rm -rf "$project_claudebox_dir"
                        success "Removed project data folder"
                    fi
                    docker rmi -f "$image_name" 2>/dev/null && \
                        success "Removed Docker image" || \
                        info "No Docker image found"
                    ;;
                *)
                    cecho "ClaudeBox Project Clean Options:" "$CYAN"
                    echo
                    echo -e "  ${GREEN}clean project [path] profiles${NC}   Remove installed profiles & packages"
                    echo -e "  ${GREEN}clean project [path] data${NC}       Remove project data (auth, history, configs)"
                    echo -e "  ${GREEN}clean project [path] docker${NC}     Remove project Docker image"
                    echo -e "  ${GREEN}clean project [path] all${NC}        Remove everything for this project"
                    echo
                    cecho "Usage examples:" "$WHITE"
                    echo "  claudebox clean project data                      # Current directory"
                    echo "  claudebox clean project /path/to/project all      # Specific path"
                    echo
                    cecho "Current project: $PROJECT_DIR" "$YELLOW"
                    echo
                    cecho "What gets removed:" "$WHITE"
                    echo "  profiles: Clears [profiles] and [packages] sections in profiles.ini"
                    echo "  data:     ~/.claudebox/projects/${project_folder_name}/ (entire project folder)"
                    echo "  docker:   Docker image claudebox-${project_folder_name}"
                    exit 0
                    ;;
            esac
            exit 0
            ;;
        *)
            cecho "ClaudeBox Clean Options:" "$CYAN"
            echo
            echo -e "  ${GREEN}clean containers${NC}         Remove all containers (preserves image)"
            echo -e "  ${GREEN}clean project${NC}            Show project cleanup options"
            echo -e "  ${GREEN}clean all${NC}                Remove all Docker artifacts (containers, images, cache, volumes)"
            echo -e "  ${GREEN}clean image${NC}              Remove containers and image (preserves build cache)"
            echo -e "  ${GREEN}clean cache${NC}              Remove Docker build cache only"
            echo -e "  ${GREEN}clean volumes${NC}            Remove associated Docker volumes"
            echo -e "  ${GREEN}clean dangling${NC}           Remove dangling images and unused containers"
            echo -e "  ${GREEN}clean logs${NC}               Clear Docker container logs"
            echo
            cecho "Examples:" "$YELLOW"
            echo "  claudebox clean containers  # Remove all containers"
            echo "  claudebox clean project     # Show project cleanup menu"
            echo "  claudebox clean image       # Remove containers and image"
            echo "  claudebox clean all         # Complete Docker cleanup"
            exit 0
            ;;
    esac
}

_cmd_info() {
    # Compute project folder name early for paths
    local project_folder_name
    project_folder_name=$(get_project_folder_name "$PROJECT_DIR")
    IMAGE_NAME="claudebox-${project_folder_name}"
    PROJECT_CLAUDEBOX_DIR="$HOME/.claudebox/projects/$project_folder_name"

    cecho "╔═══════════════════════════════════════════════════════════════════╗" "$CYAN"
    cecho "║                    ClaudeBox Information Panel                    ║" "$CYAN"
    cecho "╚═══════════════════════════════════════════════════════════════════╝" "$CYAN"
    echo

    # Current Project Info
    cecho "📁 Current Project" "$WHITE"
    echo "   Path:       $PROJECT_DIR"
    echo "   Project ID: $project_folder_name"
    echo "   Data Dir:   $PROJECT_CLAUDEBOX_DIR"
    echo

    # ClaudeBox Installation
    cecho "📦 ClaudeBox Installation" "$WHITE"
    echo "   Script:  $SCRIPT_PATH"
    echo "   Symlink: $LINK_TARGET"
    echo

    # Saved CLI Flags
    cecho "🚀 Saved CLI Flags" "$WHITE"
    if [[ -f "$HOME/.claudebox/default-flags" ]]; then
        local saved_flags=()
        while IFS= read -r flag; do
            [[ -n "$flag" ]] && saved_flags+=("$flag")
        done < "$HOME/.claudebox/default-flags"
        if [[ ${#saved_flags[@]} -gt 0 ]]; then
            echo -e "   Flags: ${GREEN}${saved_flags[*]}${NC}"
        else
            echo -e "   ${YELLOW}No flags saved${NC}"
        fi
    else
        echo -e "   ${YELLOW}No saved flags${NC}"
    fi
    echo

    # Claude Commands
    cecho "📝 Claude Commands" "$WHITE"
    local cmd_count=0
    if [[ -d "$HOME/.claudebox/commands" ]]; then
        cmd_count=$(ls -1 "$HOME/.claudebox/commands"/*.md 2>/dev/null | wc -l)
    fi
    local project_cmd_count=0
    if [[ -d ".claude/commands" ]]; then
        project_cmd_count=$(ls -1 .claude/commands/*.md 2>/dev/null | wc -l)
    fi

    if [[ $cmd_count -gt 0 ]] || [[ $project_cmd_count -gt 0 ]]; then
        echo "   Global:  $cmd_count command(s)"
        if [[ $cmd_count -gt 0 ]] && [[ -d "$HOME/.claudebox/commands" ]]; then
            for cmd_file in "$HOME/.claudebox/commands"/*.md; do
                [[ -f "$cmd_file" ]] || continue
                echo "            - $(basename "$cmd_file" .md)"
            done
        fi
        echo "   Project: $project_cmd_count command(s)"
        if [[ $project_cmd_count -gt 0 ]] && [[ -d ".claude/commands" ]]; then
            for cmd_file in .claude/commands/*.md; do
                [[ -f "$cmd_file" ]] || continue
                echo "            - $(basename "$cmd_file" .md)"
            done
        fi
    else
        echo -e "   ${YELLOW}No custom commands found${NC}"
        echo -e "   Location: ~/.claudebox/commands/ (global), .claude/commands/ (project)"
    fi
    echo

    # Project Profiles
    cecho "🛠️ Project Profiles & Packages" "$WHITE"
    local current_profile_file
    current_profile_file=$(get_profile_file_path)
    if [[ -f "$current_profile_file" ]]; then
        local current_profiles=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && current_profiles+=("$line")
        done < <(read_profile_section "$current_profile_file" "profiles")
        local current_packages=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && current_packages+=("$line")
        done < <(read_profile_section "$current_profile_file" "packages")

        if [[ ${#current_profiles[@]} -gt 0 ]]; then
            echo -e "   Installed:  ${GREEN}${current_profiles[*]}${NC}"
        else
            echo -e "   Installed:  ${YELLOW}None${NC}"
        fi

        if [[ ${#current_packages[@]} -gt 0 ]]; then
            echo "   Packages:   ${current_packages[*]}"
        fi
    else
        echo -e "   Status:     ${YELLOW}No profiles installed${NC}"
    fi

    echo -e "   Available:  ${CYAN}core${NC}, python, c, rust, go, javascript, java, ruby, php"
    echo -e "               database, devops, web, ml, security, embedded, networking"
    echo -e "   ${CYAN}Hint:${NC} Run 'claudebox profile' for profile help "
    echo

    cecho "🐳 Docker Status" "$WHITE"
    if [[ -n "${IMAGE_NAME:-}" ]] && docker image inspect "$IMAGE_NAME" &>/dev/null; then
        local image_info=$(docker images --filter "reference=$IMAGE_NAME" --format "{{.Size}}")
        echo -e "   Image:      ${GREEN}Ready${NC} ($IMAGE_NAME - $image_info)"

        local image_created=$(docker inspect "$IMAGE_NAME" --format '{{.Created}}' | cut -d'T' -f1)
        local layer_count=$(docker history "$IMAGE_NAME" --no-trunc --format "{{.CreatedBy}}" | wc -l)
        echo "   Created:    $image_created"
        echo "   Layers:     $layer_count"
    else
        echo -e "   Image:      ${YELLOW}Not built${NC}"
    fi

    local running_containers=$(docker ps --filter "ancestor=$IMAGE_NAME" -q 2>/dev/null)
    if [[ -n "$running_containers" ]]; then
        local container_count=$(echo "$running_containers" | wc -l)
        echo -e "   Containers: ${GREEN}$container_count running${NC}"

        for container_id in $running_containers; do
            local container_stats="$(docker stats --no-stream --format "{{.Container}}: {{.CPUPerc}} CPU, {{.MemUsage}}" "$container_id" 2>/dev/null || echo "")"
            if [[ -n "$container_stats" ]]; then
                echo "               - $container_stats"
            fi
        done
    else
        echo "   Containers: None running"
    fi
    echo

    # All Projects Summary
    cecho "📊 All Projects Summary" "$WHITE"
    local total_projects=$(ls -1d "$HOME/.claudebox/projects"/*/ 2>/dev/null | wc -l)
    echo "   Projects:   $total_projects total"

    local total_size=$(docker images --filter "reference=claudebox-*" --format "{{.Size}}" | awk '{
        size=$1; unit=$2;
        if (unit == "GB") size = size * 1024;
        else if (unit == "KB") size = size / 1024;
        total += size
    } END {
        if (total > 1024) printf "%.1fGB", total/1024;
        else printf "%.1fMB", total
    }')
    local image_count=$(docker images --filter "reference=claudebox-*" -q | wc -l)
    echo "   Images:     $image_count ClaudeBox images using $total_size"

    local docker_stats=$(docker system df --format "table {{.Type}}\t{{.Total}}\t{{.Active}}\t{{.Size}}\t{{.Reclaimable}}" 2>/dev/null | tail -n +2)
    if [[ -n "$docker_stats" ]]; then
        echo "   System:"
        while IFS=$'\t' read -r type total active size reclaim; do
            echo "               - $type: $total total, $active active ($size, $reclaim reclaimable)"
        done <<< "$docker_stats"
    fi
    echo

    exit 0
}

_cmd_rebuild() {
    # Rebuild is handled in main() before dispatching
    # This function shouldn't be called but is here for completeness
    exit 0
}

_cmd_update() {
    # Handle update all specially
    if [[ "${1:-}" == "all" ]]; then
        info "Updating all components..."
        echo
        
        # Update claudebox script
        info "Updating claudebox script..."
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL https://raw.githubusercontent.com/RchGrav/claudebox/main/claudebox -o /tmp/claudebox.new
        elif command -v wget >/dev/null 2>&1; then
            wget -qO /tmp/claudebox.new https://raw.githubusercontent.com/RchGrav/claudebox/main/claudebox
        else
            error "Neither curl nor wget found"
        fi
        
        if [[ -f /tmp/claudebox.new ]]; then
            # Find the installed claudebox (not the source)
            local installed_path=$(which claudebox 2>/dev/null || echo "/usr/local/bin/claudebox")
            
            # If it's a symlink, replace it with the actual file first
            if [[ -L "$installed_path" ]]; then
                info "Converting symlink to real file..."
                local source_file=$(readlink -f "$installed_path")
                if [[ -w "$(dirname "$installed_path")" ]]; then
                    cp "$source_file" "$installed_path.tmp"
                    mv "$installed_path.tmp" "$installed_path"
                    chmod +x "$installed_path"
                else
                    sudo cp "$source_file" "$installed_path.tmp"
                    sudo mv "$installed_path.tmp" "$installed_path"
                    sudo chmod +x "$installed_path"
                fi
            fi
            
            # Compare hashes of the INSTALLED file
            current_hash=$(crc32_file "$installed_path" || echo "none")
            new_hash=$(crc32_file /tmp/claudebox.new)
            
            if [[ "$current_hash" != "$new_hash" ]]; then
                info "New version available, updating..."
                
                # Backup current installed version
                local backups_dir="$HOME/.claudebox/backups"
                mkdir -p "$backups_dir"
                local timestamp=$(date +%s)
                cp "$installed_path" "$backups_dir/$timestamp"
                info "Backed up current version to $backups_dir/$timestamp"
                
                # Update the INSTALLED file
                if [[ -w "$installed_path" ]] || [[ -w "$(dirname "$installed_path")" ]]; then
                    cp /tmp/claudebox.new "$installed_path"
                    chmod +x "$installed_path"
                else
                    sudo cp /tmp/claudebox.new "$installed_path"
                    sudo chmod +x "$installed_path"
                fi
                success "✓ Claudebox script updated at $installed_path"
            else
                success "✓ Claudebox script already up to date"
            fi
            rm -f /tmp/claudebox.new
        fi
        echo
        
        # Update commands
        info "Updating commands..."
        local commands_dir="$HOME/.claudebox/commands"
        mkdir -p "$commands_dir"
        
        for cmd in taskengine devops; do
            echo -n "  Updating $cmd.md... "
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL "https://raw.githubusercontent.com/RchGrav/claudebox/main/commands/$cmd.md" -o "$commands_dir/$cmd.md"
            else
                wget -qO "$commands_dir/$cmd.md" "https://raw.githubusercontent.com/RchGrav/claudebox/main/commands/$cmd.md"
            fi
            echo "✓"
        done
        echo
        
        # Now update Claude
        info "Updating Claude..."
        shift # Remove "update"
        shift # Remove "all"
        set -- "update" "$@" # Put back just "update"
    fi
    
    # Check if image exists first
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        error "No Docker image found for this project folder: $PROJECT_DIR\nRun 'claudebox' first to build the image, or cd to your project directory."
    fi
    
    # Continue with normal update flow
    _cmd_special "update" "$@"
}

_cmd_special() {
    local cmd="$1"
    shift
    
    # Check if image exists first (for non-update commands)
    if [[ "$cmd" != "update" ]] && ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        error "No Docker image found for this project folder: $PROJECT_DIR\nRun 'claudebox' first to build the image, or cd to your project directory."
    fi
    
    # Create temporary container
    local project_folder_name=$(get_project_folder_name "$PROJECT_DIR")
    local temp_container="claudebox-temp-${project_folder_name}-$$"
    
    # Run container with all arguments passed through
    run_claudebox_container "$temp_container" "detached" "$cmd" "$@" >/dev/null
    
    # Show progress while waiting
    if [[ "$cmd" == "update" ]]; then
        # Show hint during update
        echo
        cecho "Hint:" "$YELLOW"
        echo "  claudebox update all            # Pull the latest claudebox features!"
        echo
    fi
    fillbar
    
    # Wait for container to finish
    docker wait "$temp_container" >/dev/null
    
    fillbar stop
    
    # Show container output for commands that produce output
    docker logs "$temp_container" 2>&1
    
    # For update command, show version after update
    if [[ "$cmd" == "update" ]]; then
        docker exec -u "$DOCKER_USER" "$temp_container" bash -c "
            source \$HOME/.nvm/nvm.sh && nvm use default >/dev/null 2>&1 && claude --version
        " 2>/dev/null || true
    fi

    # Commit changes back to image
    docker commit "$temp_container" "$IMAGE_NAME" >/dev/null
    docker stop "$temp_container" >/dev/null 2>&1 || true
    docker rm "$temp_container" >/dev/null 2>&1 || true
    
    exit 0
}

_cmd_undo() {
    local backups_dir="$HOME/.claudebox/backups"
    if [[ ! -d "$backups_dir" ]] || [[ -z "$(ls -A "$backups_dir" 2>/dev/null)" ]]; then
        error "No backups found"
    fi
    
    # Get oldest backup (smallest timestamp)
    local oldest=$(ls -1 "$backups_dir" | sort -n | head -1)
    local installed_path=$(which claudebox 2>/dev/null || echo "/usr/local/bin/claudebox")
    
    info "Restoring oldest backup from $(date -d @$oldest '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $oldest '+%Y-%m-%d %H:%M:%S')"
    
    if [[ -w "$installed_path" ]] || [[ -w "$(dirname "$installed_path")" ]]; then
        cp "$backups_dir/$oldest" "$installed_path"
        chmod +x "$installed_path"
    else
        sudo cp "$backups_dir/$oldest" "$installed_path"
        sudo chmod +x "$installed_path"
    fi
    
    success "✓ Restored claudebox from backup"
    exit 0
}

_cmd_redo() {
    local backups_dir="$HOME/.claudebox/backups"
    if [[ ! -d "$backups_dir" ]] || [[ -z "$(ls -A "$backups_dir" 2>/dev/null)" ]]; then
        error "No backups found"
    fi
    
    # Get newest backup (largest timestamp)
    local newest=$(ls -1 "$backups_dir" | sort -n | tail -1)
    local installed_path=$(which claudebox 2>/dev/null || echo "/usr/local/bin/claudebox")
    
    info "Restoring newest backup from $(date -d @$newest '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $newest '+%Y-%m-%d %H:%M:%S')"
    
    if [[ -w "$installed_path" ]] || [[ -w "$(dirname "$installed_path")" ]]; then
        cp "$backups_dir/$newest" "$installed_path"
        chmod +x "$installed_path"
    else
        sudo cp "$backups_dir/$newest" "$installed_path"
        sudo chmod +x "$installed_path"
    fi
    
    success "✓ Restored claudebox from backup"
    exit 0
}

_cmd_create() {
    cecho "Creating new container slot..." "$CYAN"
    echo
    
    # Create a new slot
    local slot_name=$(create_container "$PROJECT_DIR")
    local parent_dir=$(get_parent_dir "$PROJECT_DIR")
    local slot_dir="$parent_dir/$slot_name"
    
    success "✓ Created slot: $slot_name"
    echo
    info "Slot directory: $slot_dir"
    echo
    
    # Show updated slots list
    list_project_slots "$PROJECT_DIR"
    
    return 0
}

_cmd_slots() {
    list_project_slots "$PROJECT_DIR"
    return 0
}

_cmd_slot() {
    # Extract slot number - it should be the first argument
    local slot_num="${1:-}"
    shift || true  # Remove slot number from arguments
    
    # Validate slot number
    if [[ ! "$slot_num" =~ ^[0-9]+$ ]]; then
        error "Usage: claudebox slot <number> [claude arguments...]"
    fi
    
    # Get the slot directory
    local slot_dir=$(get_slot_dir "$PROJECT_DIR" "$slot_num")
    local slot_name=$(basename "$slot_dir")
    
    # Check if slot exists
    if [[ ! -d "$slot_dir" ]]; then
        error "Slot $slot_num does not exist. Run 'claudebox slots' to see available slots."
    fi
    
    # Set up environment for this specific slot
    local parent_dir=$(get_parent_dir "$PROJECT_DIR")
    export PROJECT_CLAUDEBOX_DIR="$slot_dir"
    export PROJECT_PARENT_DIR="$parent_dir"
    export IMAGE_NAME=$(get_image_name)
    
    info "Using slot $slot_num: $slot_name"
    
    # Run container with remaining arguments passed to claude
    run_claudebox_container "" "interactive" "$@"
    exit 0
}

_cmd_revoke() {
    [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Starting _cmd_revoke with PROJECT_DIR=$PROJECT_DIR" >&2
    local parent
    parent=$(get_parent_dir "$PROJECT_DIR")
    [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] parent=$parent" >&2
    local max
    max=$(read_counter "$parent")
    [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] max=$max" >&2
    
    if [ $max -eq 0 ]; then
        echo "No slots to revoke"
        return 0
    fi
    
    [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Checking argument: ${1:-}" >&2
    
    # Check for "all" argument
    if [ "${1:-}" = "all" ]; then
        [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Processing revoke all" >&2
        local removed_count=0
        local existing_count=0
        
        # First count how many slots actually exist
        [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Starting count loop, max=$max" >&2
        for ((idx=1; idx<=max; idx++)); do
            [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Count loop idx=$idx" >&2
            local name
            name=$(generate_container_name "$PROJECT_DIR" "$idx")
            [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Generated name=$name" >&2
            local dir="$parent/$name"
            if [ -d "$dir" ]; then
                ((existing_count++)) || true
            fi
        done
        
        [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Finished count loop, existing_count=$existing_count, max=$max" >&2
        
        # Now remove them
        [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Starting removal loop" >&2
        for ((idx=$max; idx>=1; idx--)); do
            local name=$(generate_container_name "$PROJECT_DIR" "$idx")
            local dir="$parent/$name"
            
            if [ -d "$dir" ]; then
                # Check if container is running
                if docker ps --format "{{.Names}}" | grep -q "^claudebox-.*-${name}$"; then
                    info "Slot $idx is in use, skipping"
                else
                    [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Removing slot $idx: $dir" >&2
                    if rm -rf "$dir"; then
                        ((removed_count++)) || true
                    else
                        error "Failed to remove slot $idx: $dir"
                    fi
                fi
            else
                [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Slot $idx not found: $dir" >&2
            fi
        done
        
        # If we removed all existing slots, set counter to 0
        [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] removed_count=$removed_count, existing_count=$existing_count" >&2
        if [ $removed_count -eq $existing_count ]; then
            [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Setting counter to 0" >&2
            write_counter "$parent" 0
        else
            # Otherwise prune the counter
            [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Pruning counter" >&2
            prune_slot_counter "$PROJECT_DIR"
        fi
        
        # Show updated slots list
        list_project_slots "$PROJECT_DIR"
    else
        # Revoke highest slot only
        local name=$(generate_container_name "$PROJECT_DIR" "$max")
        local dir="$parent/$name"
        
        if [ ! -d "$dir" ]; then
            # Slot doesn't exist, just prune the counter
            prune_slot_counter "$PROJECT_DIR"
            local new_max=$(read_counter "$parent")
            info "Slot $max doesn't exist. Counter adjusted to $new_max"
        else
            # Check if container is running
            if docker ps --format "{{.Names}}" | grep -q "^claudebox-.*-${name}$"; then
                error "Cannot revoke slot $max - it is currently in use"
            fi
            
            # Remove the slot
            rm -rf "$dir"
            write_counter "$parent" $((max - 1))
        fi
        
        # Show updated slots list
        [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] About to call list_project_slots" >&2
        list_project_slots "$PROJECT_DIR"
        [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] list_project_slots returned" >&2
    fi
    
    [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Exiting _cmd_revoke" >&2
    return 0
}

_forward_to_container() {
    run_claudebox_container "" "interactive" "$@"
}

export -f dispatch_command show_help
