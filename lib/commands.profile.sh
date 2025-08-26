#!/usr/bin/env bash
# Profile Commands - Development profile management
# ============================================================================
# Commands: profiles, profile, add, remove, install
# Manages development tools and packages in containers

_cmd_profiles() {
    # Get current profiles
    local current_profiles=($(get_current_profiles))
    
    # Show logo first
    logo_small
    printf '\n'
    
    # Show commands at the top
    printf '%s\n' "Commands:"
    printf "  ${CYAN}claudebox add <profiles...>${NC}    - Add development profiles to your project\n"
    printf "  ${CYAN}claudebox remove <profiles...>${NC} - Remove profiles from your project\n"
    printf "  ${CYAN}claudebox profile create <name>${NC} - Create a new custom profile\n"
    printf "  ${CYAN}claudebox profile install <path>${NC} - Install a custom profile\n"
    printf '\n'
    
    # Show currently enabled profiles
    if [[ ${#current_profiles[@]} -gt 0 ]]; then
        cecho "Currently enabled:" "$YELLOW"
        printf "  %s\n" "${current_profiles[*]}"
        printf '\n'
    fi
    
    # Show available profiles
    cecho "Available profiles:" "$CYAN"
    printf '\n'
    
    # Collect profiles with their sources
    local system_profiles=()
    local user_profiles=()
    
    if [[ -d "$SCRIPT_DIR/tooling/profiles" ]]; then
        for script in "$SCRIPT_DIR/tooling/profiles"/*.sh; do
            if [[ -f "$script" ]] && [[ -x "$script" ]]; then
                system_profiles+=("$(basename "$script" .sh)")
            fi
        done
    fi
    
    if [[ -d "$HOME/.claudebox/profiles" ]]; then
        for script in "$HOME/.claudebox/profiles"/*.sh; do
            if [[ -f "$script" ]] && [[ -x "$script" ]]; then
                user_profiles+=("$(basename "$script" .sh)")
            fi
        done
    fi
    
    # Show system profiles
    if [[ ${#system_profiles[@]} -gt 0 ]]; then
        printf "  ${YELLOW}System:${NC}\n"
        for profile in $(printf '%s\n' "${system_profiles[@]}" | sort); do
            local desc=$(get_profile_description "$profile")
            local is_enabled=false
            # Check if profile is currently enabled
            for enabled in "${current_profiles[@]}"; do
                if [[ "$enabled" == "$profile" ]]; then
                    is_enabled=true
                    break
                fi
            done
            printf "    ${GREEN}%-15s${NC} " "$profile"
            if [[ "$is_enabled" == "true" ]]; then
                printf "${GREEN}✓${NC} "
            else
                printf "  "
            fi
            printf "%s\n" "$desc"
        done
    fi
    
    # Show user profiles
    if [[ ${#user_profiles[@]} -gt 0 ]]; then
        printf "\n  ${YELLOW}User:${NC}\n"
        for profile in $(printf '%s\n' "${user_profiles[@]}" | sort); do
            local desc=$(get_profile_description "$profile")
            local is_enabled=false
            # Check if profile is currently enabled
            for enabled in "${current_profiles[@]}"; do
                if [[ "$enabled" == "$profile" ]]; then
                    is_enabled=true
                    break
                fi
            done
            printf "    ${GREEN}%-15s${NC} " "$profile"
            if [[ "$is_enabled" == "true" ]]; then
                printf "${GREEN}✓${NC} "
            else
                printf "  "
            fi
            printf "%s\n" "$desc"
        done
    fi
    
    printf '\n'
    exit 0
}

_cmd_profile() {
    # Check for subcommands
    local subcommand="${1:-}"
    
    case "$subcommand" in
        create)
            shift
            _cmd_profile_create "$@"
            ;;
        install)
            shift
            _cmd_profile_install "$@"
            ;;
        *)
            # Show profile menu/help
            logo_small
            echo
            cecho "ClaudeBox Profile Management:" "$CYAN"
            echo
            echo -e "  ${GREEN}profiles${NC}                 Show all available profiles"
            echo -e "  ${GREEN}add <names...>${NC}           Add development profiles"
            echo -e "  ${GREEN}remove <names...>${NC}        Remove development profiles"  
            echo -e "  ${GREEN}add status${NC}               Show current project's profiles"
            echo -e "  ${GREEN}profile create <name>${NC}    Create a custom profile"
            echo -e "  ${GREEN}profile install <path>${NC}   Install a profile from file/URL"
            echo
            cecho "Examples:" "$YELLOW"
            echo "  claudebox profiles              # See all available profiles"
            echo "  claudebox add python rust       # Add Python and Rust profiles"
            echo "  claudebox remove rust           # Remove Rust profile"
            echo "  claudebox add status            # Check current project's profiles"
            echo "  claudebox profile create mytools # Create custom profile"
            echo "  claudebox profile install https://example.com/profile.sh"
            echo
            exit 0
            ;;
    esac
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
        # Stop processing if we hit a flag (starts with -)
        if [[ "$1" == -* ]]; then
            remaining=("$@")
            break
        fi
        
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
    while IFS= read -r line; do
        [[ -n "$line" ]] && all_profiles+=("$line")
    done < <(read_profile_section "$profile_file" "profiles")

    cecho "Profile: $PROJECT_DIR" "$CYAN"
    cecho "Adding profiles: ${selected[*]}" "$PURPLE"
    if [[ ${#all_profiles[@]} -gt 0 ]]; then
        cecho "All active profiles: ${all_profiles[*]}" "$GREEN"
    fi
    echo
    
    # Check if any Python-related profiles were added
    local python_profiles_added=false
    for profile in "${selected[@]}"; do
        if [[ "$profile" == "python" ]] || [[ "$profile" == "ml" ]] || [[ "$profile" == "datascience" ]]; then
            python_profiles_added=true
            break
        fi
    done
    
    # If Python profiles were added, remove the pydev flag to trigger reinstall
    if [[ "$python_profiles_added" == "true" ]]; then
        local parent_dir=$(get_parent_dir "$PROJECT_DIR")
        if [[ -f "$parent_dir/.pydev_flag" ]]; then
            rm -f "$parent_dir/.pydev_flag"
            info "Python packages will be updated on next run"
        fi
    fi
    
    # Only show rebuild message for non-Python profiles
    local needs_rebuild=false
    for profile in "${selected[@]}"; do
        if [[ "$profile" != "python" ]] && [[ "$profile" != "ml" ]] && [[ "$profile" != "datascience" ]]; then
            needs_rebuild=true
            break
        fi
    done
    
    if [[ "$needs_rebuild" == "true" ]]; then
        warn "The Docker image will be rebuilt with new profiles on next run."
    fi
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
        # Stop processing if we hit a flag (starts with -)
        if [[ "$1" == -* ]]; then
            break
        fi
        
        if profile_exists "$1"; then
            to_remove+=("$1")
            shift
        else
            # Also stop if we hit an unknown profile
            # This prevents consuming Claude args as profile names
            break
        fi
    done

    [[ ${#to_remove[@]} -eq 0 ]] && error "No valid profiles specified to remove"

    # Remove specified profiles
    local new_profiles=()
    local python_profiles_removed=false
    for profile in "${current_profiles[@]}"; do
        local keep=true
        for remove in "${to_remove[@]}"; do
            if [[ "$profile" == "$remove" ]]; then
                keep=false
                # Check if we're removing a Python-related profile
                if [[ "$profile" == "python" ]] || [[ "$profile" == "ml" ]] || [[ "$profile" == "datascience" ]]; then
                    python_profiles_removed=true
                fi
                break
            fi
        done
        [[ "$keep" == "true" ]] && new_profiles+=("$profile")
    done
    
    # Check if any Python-related profiles remain
    local has_python_profiles=false
    for profile in "${new_profiles[@]}"; do
        if [[ "$profile" == "python" ]] || [[ "$profile" == "ml" ]] || [[ "$profile" == "datascience" ]]; then
            has_python_profiles=true
            break
        fi
    done
    
    # If we removed Python profiles and no Python profiles remain, clean up Python flags
    if [[ "$python_profiles_removed" == "true" ]] && [[ "$has_python_profiles" == "false" ]]; then
        init_project_dir "$PROJECT_DIR"
        PROJECT_PARENT_DIR=$(get_parent_dir "$PROJECT_DIR")
        
        # Remove Python flags and venv folder if they exist
        if [[ -f "$PROJECT_PARENT_DIR/.venv_flag" ]]; then
            rm -f "$PROJECT_PARENT_DIR/.venv_flag"
        fi
        if [[ -f "$PROJECT_PARENT_DIR/.pydev_flag" ]]; then
            rm -f "$PROJECT_PARENT_DIR/.pydev_flag"
        fi
        if [[ -d "$PROJECT_PARENT_DIR/.venv" ]]; then
            rm -rf "$PROJECT_PARENT_DIR/.venv"
        fi
        
        cecho "Cleaned up Python environment flags and venv folder" "$YELLOW"
    fi

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

_cmd_install() {
    [[ $# -eq 0 ]] && error "No packages specified. Usage: claudebox install <package1> <package2> ..."

    local profile_file
    profile_file=$(get_profile_file_path)

    update_profile_section "$profile_file" "packages" "$@"

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

# Profile creation command
_cmd_profile_create() {
    local name="${1:-}"
    [[ -z "$name" ]] && error "Usage: claudebox profile create <name>"
    
    # Validate profile name
    if [[ ! "$name" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        error "Profile name must start with a letter and contain only lowercase letters, numbers, hyphens, and underscores"
    fi
    
    # Check if profile already exists
    if profile_exists "$name"; then
        error "Profile '$name' already exists"
    fi
    
    # Create user profiles directory if needed
    local user_profiles_dir="$HOME/.claudebox/profiles"
    mkdir -p "$user_profiles_dir"
    
    # Create profile from template
    local profile_file="$user_profiles_dir/${name}.sh"
    local template_file="$SCRIPT_DIR/templates/profile.template.sh"
    
    if [[ ! -f "$template_file" ]]; then
        error "Profile template not found at $template_file"
    fi
    
    # Copy and customize template
    cp "$template_file" "$profile_file"
    sed -i '' "s/PROFILE_NAME/$name/g" "$profile_file" 2>/dev/null || \
        sed -i "s/PROFILE_NAME/$name/g" "$profile_file"
    chmod +x "$profile_file"
    
    cecho "Created profile: $profile_file" "$GREEN"
    printf "Edit the file to customize your profile:\n"
    printf "  - Update the description\n"
    printf "  - Add required apt packages\n"
    printf "  - Add Dockerfile commands\n"
    printf "  - Specify dependencies\n"
    printf "\n"
    printf "To use: claudebox add %s\n" "$name"
}

# Profile installation command
_cmd_profile_install() {
    local source="${1:-}"
    [[ -z "$source" ]] && error "Usage: claudebox profile install <path/url>"
    
    # Create user profiles directory if needed
    local user_profiles_dir="$HOME/.claudebox/profiles"
    mkdir -p "$user_profiles_dir"
    
    local profile_file=""
    local temp_file=""
    
    # Check if source is a URL
    if [[ "$source" =~ ^https?:// ]]; then
        temp_file="/tmp/claudebox-profile-$$.sh"
        cecho "Downloading profile from $source..." "$CYAN"
        curl -sSL "$source" -o "$temp_file" || error "Failed to download profile"
        profile_file="$temp_file"
    elif [[ -f "$source" ]]; then
        profile_file="$source"
    else
        error "Profile source not found: $source"
    fi
    
    # Validate profile script
    if ! bash -n "$profile_file" 2>/dev/null; then
        [[ -n "$temp_file" ]] && rm -f "$temp_file"
        error "Invalid profile script: syntax errors detected"
    fi
    
    # Extract profile name
    local profile_name=""
    local info
    info=$("$profile_file" info 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$info" ]]; then
        profile_name=$(printf '%s' "$info" | cut -d'|' -f1)
    fi
    
    if [[ -z "$profile_name" ]]; then
        [[ -n "$temp_file" ]] && rm -f "$temp_file"
        error "Could not determine profile name from script"
    fi
    
    # Check for dangerous commands
    if grep -qE 'rm -rf|curl.*\|.*sh|wget.*\|.*sh|sudo' "$profile_file"; then
        warn "Profile contains potentially dangerous commands. Review carefully before using."
    fi
    
    # Install profile
    local dest_file="$user_profiles_dir/${profile_name}.sh"
    if [[ -f "$dest_file" ]]; then
        warn "Profile '$profile_name' already exists. Overwrite? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            [[ -n "$temp_file" ]] && rm -f "$temp_file"
            exit 1
        fi
    fi
    
    cp "$profile_file" "$dest_file"
    chmod +x "$dest_file"
    [[ -n "$temp_file" ]] && rm -f "$temp_file"
    
    local desc
    desc=$(get_profile_description "$profile_name")
    cecho "Installed profile: $profile_name" "$GREEN"
    if [[ -n "$desc" ]]; then
        printf "Description: %s\n" "$desc"
    fi
    printf "\n"
    printf "To use: claudebox add %s\n" "$profile_name"
}

export -f _cmd_profiles _cmd_profile _cmd_add _cmd_remove _cmd_install _cmd_profile_create _cmd_profile_install