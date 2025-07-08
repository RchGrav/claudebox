#!/usr/bin/env bash
# The canonical place where CLI arguments map to functions.

# Show help function
show_help() {
    if docker image inspect "$IMAGE_NAME" &>/dev/null; then
        run_claudebox_container "" "pipe" --help | sed '1s/claude/claudebox/g'
        echo
        cecho "Added Options:" "$WHITE"
        echo -e "${CYAN}  --verbose                       ${WHITE}Show detailed output"
        echo -e "${CYAN}  --enable-sudo                   ${WHITE}Enable sudo without password"
        echo -e "${CYAN}  --disable-firewall              ${WHITE}Disable network restrictions"
        echo
        cecho "Added Commands:" "$WHITE"
        echo -e "  profiles                        List all available profiles"
        echo -e "  projects                        List all projects with paths"
        echo -e "  profile                         Profile management menu"
        echo -e "  install <packages>              Install apt packages"
        echo -e "  save [flags...]                 Save default flags (no args = clear saved flags)"
        echo -e "  shell                           Open transient shell (changes NOT saved)"
        echo -e "  shell admin                     Open admin shell (sudo, no firewall, changes saved)"
        echo -e "  allowlist                       Show/edit firewall allowlist"
        echo -e "  info                            Show comprehensive project info"
        echo -e "  clean                           Menu of cleanup tasks"
        echo -e "  unlink                          Remove claudebox symlink"
        echo -e "  rebuild                         Rebuild the Docker image from scratch"
        echo -e "  create                          Create new authenticated container slot"
        echo -e "  slots                           List all container slots for this project${NC}"
    else
        cecho "ClaudeBox - Claude Code Docker Environment" "$CYAN"
        echo
        warn "First run setup required!"
        echo "Run script without arguments first to build the Docker image."
    fi
}

# --- public -------------------------------------------------------------------
dispatch_command() {
  local cmd="${1:-help}"; shift || true
  case "${cmd}" in
    help|-h|--help)   _cmd_help "$@" ;;
    profiles)         _cmd_profiles "$@" ;;
    projects)         _cmd_projects "$@" ;;
    profile)          _cmd_profile "$@" ;;
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
    config|mcp|migrate-installer) _cmd_special "$cmd" "$@" ;;
    undo)             _cmd_undo "$@" ;;
    redo)             _cmd_redo "$@" ;;
    *)                _forward_to_container "${cmd}" "$@" ;;
  esac
}

# --- individual handlers ------------------------------------------------------

_cmd_help() {
    show_help
    exit 0
}

_cmd_profiles() {
    cecho "Available ClaudeBox Profiles:" "$CYAN"
    echo
    for profile in $(get_all_profile_names | tr ' ' '\n' | sort); do
        local desc=$(get_profile_description "$profile")
        echo -e "  ${GREEN}$profile${NC} - $desc"
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
    local project_folder_name
    project_folder_name=$(get_project_folder_name "$PROJECT_DIR")
    local profile_file
    profile_file=$(get_profile_file_path)

    case "${1:-}" in
        list|--list|-l)
            cecho "Available ClaudeBox Profiles:" "$CYAN"
            echo
            for profile in $(get_all_profile_names | tr ' ' '\n' | sort); do
                local desc=$(get_profile_description "$profile")
                echo -e "  ${GREEN}$profile${NC} - $desc"
            done
            exit 0
            ;;

        status|--status|-s)
            cecho "Project: $PROJECT_DIR" "$CYAN"
            echo
            if [[ -f "$profile_file" ]]; then
                local current_profiles=()
                readarray -t current_profiles < <(read_profile_section "$profile_file" "profiles")
                if [[ ${#current_profiles[@]} -gt 0 ]]; then
                    cecho "Active profiles: ${current_profiles[*]}" "$GREEN"
                else
                    cecho "No profiles installed" "$YELLOW"
                fi

                local current_packages=()
                readarray -t current_packages < <(read_profile_section "$profile_file" "packages")
                if [[ ${#current_packages[@]} -gt 0 ]]; then
                    echo "Extra packages: ${current_packages[*]}"
                fi
            else
                cecho "No profiles configured for this project" "$YELLOW"
            fi
            exit 0
            ;;

        "")
            cecho "ClaudeBox Profile Management:" "$CYAN"
            echo
            echo -e "  ${GREEN}profiles${NC}                 Show all available profiles"
            echo -e "  ${GREEN}profile status${NC}           Show current project's profiles"
            echo -e "  ${GREEN}profile <names...>${NC}       Install profiles (e.g., python c rust)"
            echo
            cecho "Examples:" "$YELLOW"
            echo "  claudebox profiles              # See all available profiles"
            echo "  claudebox profile status        # Check current project's profiles"
            echo "  claudebox profile python        # Install Python development profile"
            echo "  claudebox profile c openwrt     # Install C and OpenWRT profiles"
            exit 0
            ;;
    esac

    # Don't shift - dispatch_command already removed 'profile'
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

    [[ ${#selected[@]} -eq 0 ]] && error "No valid profiles specified\nRun 'claudebox profile' to see available profiles"

    local profile_file
    profile_file=$(get_profile_file_path)

    update_profile_section "$profile_file" "profiles" "${selected[@]}"

    local all_profiles=()
    readarray -t all_profiles < <(read_profile_section "$profile_file" "profiles")

    cecho "Profile: $PROJECT_DIR" "$CYAN"
    cecho "Installing profiles: ${selected[*]}" "$PURPLE"
    if [[ ${#all_profiles[@]} -gt 0 ]]; then
        cecho "All active profiles: ${all_profiles[*]}" "$GREEN"
    fi
    echo

    if [[ ${#remaining[@]} -gt 0 ]]; then
        set -- "${remaining[@]}"
    fi
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
    readarray -t all_packages < <(read_profile_section "$profile_file" "packages")

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
    # Check if image exists first
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        error "No Docker image found for this project folder: $PROJECT_DIR\nRun 'claudebox' first to build the image, or cd to your project directory."
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
                warn "Unknown shell flag: $1"
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
        
        run_claudebox_container "$temp_container" "interactive" --shell-mode "${shell_flags[@]}"
        
        # Commit changes back to image
        fillbar
        docker commit "$temp_container" "$IMAGE_NAME" >/dev/null
        docker rm -f "$temp_container" >/dev/null 2>&1
        fillbar stop
        success "Changes saved to image!"
    else
        # Regular shell mode - just run without committing
        run_claudebox_container "" "interactive" --shell-mode "${shell_flags[@]}"
    fi
    
    exit 0
}

_cmd_allowlist() {
    local allowlist_file="$PROJECT_CLAUDEBOX_DIR/allowlist"

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
            docker rmi -f "$IMAGE_NAME" 2>/dev/null || true
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
            local config_file="$project_claudebox_dir/config.ini"
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
                    echo "  profiles: Clears [profiles] and [packages] sections in config.ini"
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
        readarray -t current_profiles < <(read_profile_section "$current_profile_file" "profiles")
        local current_packages=()
        readarray -t current_packages < <(read_profile_section "$current_profile_file" "packages")

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
    if docker image inspect "$IMAGE_NAME" &>/dev/null; then
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
    cecho "Creating new authenticated container slot..." "$CYAN"
    echo
    
    # Create a new slot
    local slot_name=$(create_container "$PROJECT_DIR")
    local parent_dir=$(get_parent_dir "$PROJECT_DIR")
    local slot_dir="$parent_dir/$slot_name"
    
    info "Created slot: $slot_name"
    
    # Build Docker image if needed
    # All slots share the same Docker image based on parent name
    local parent_name=$(basename "$parent_dir")
    local image_name="claudebox-${parent_name}"
    if ! docker image inspect "$image_name" &>/dev/null; then
        warn "Docker image not found. Building..."
        # The main script will handle the build
        exit 2
    fi
    
    # Launch OAuth wizard in the container
    info "Launching authentication wizard..."
    echo
    cecho "Please follow these steps:" "$YELLOW"
    echo "1. Copy the URL that appears"
    echo "2. Open it in your browser"
    echo "3. Authenticate with Claude"
    echo "4. Copy the token and paste it back here"
    echo
    
    # Run container with slot directory mounted
    local container_name="claudebox-auth-$(date +%s)"
    docker run -it --rm \
        --name "$container_name" \
        -v "$slot_dir":/home/$DOCKER_USER/.claudebox \
        -v "$PROJECT_DIR":/workspace \
        -w /workspace \
        "$image_name" \
        claude login
    
    # Check if authentication succeeded
    if [[ -d "$slot_dir/.claude" ]]; then
        success "✓ Slot $slot_name authenticated successfully!"
        echo
        info "You can now use this slot by running: claudebox"
    else
        error "Authentication failed. The slot was created but not authenticated."
    fi
    
    exit 0
}

_cmd_slots() {
    list_project_slots "$PROJECT_DIR"
    exit 0
}

_forward_to_container() {
    run_claudebox_container "" "interactive" "$@"
}

export -f dispatch_command show_help