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
    for profile in $(get_all_profile_names | tr ' ' '\n' | sort); do
        local desc=$(get_profile_description "$profile")
        local is_enabled=false
        # Check if profile is currently enabled (guard for empty array)
        if [ ${#current_profiles[@]} -gt 0 ]; then
            for enabled in "${current_profiles[@]}"; do
                if [[ "$enabled" == "$profile" ]]; then
                    is_enabled=true
                    break
                fi
            done
        fi
        printf "  ${GREEN}%-15s${NC} " "$profile"
        if [[ "$is_enabled" == "true" ]]; then
            printf "${GREEN}✓${NC} "
        else
            printf "  "
        fi
        printf "%s\n" "$desc"
    done
    printf '\n'
    exit 0
}

_cmd_profile() {
    # Profile menu/help
    logo_small
    echo
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
    echo
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
    if [ ${#selected[@]} -gt 0 ]; then
        for profile in "${selected[@]}"; do
            if [[ "$profile" == "python" ]] || [[ "$profile" == "ml" ]] || [[ "$profile" == "datascience" ]]; then
                python_profiles_added=true
                break
            fi
        done
    fi
    
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
    if [ ${#selected[@]} -gt 0 ]; then
        for profile in "${selected[@]}"; do
            if [[ "$profile" != "python" ]] && [[ "$profile" != "ml" ]] && [[ "$profile" != "datascience" ]]; then
                needs_rebuild=true
                break
            fi
        done
    fi
    
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
    if [ ${#current_profiles[@]} -gt 0 ]; then
        for profile in "${current_profiles[@]}"; do
            local keep=true
            if [ ${#to_remove[@]} -gt 0 ]; then
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
            fi
            [[ "$keep" == "true" ]] && new_profiles+=("$profile")
        done
    fi
    
    # Check if any Python-related profiles remain
    local has_python_profiles=false
    if [ ${#new_profiles[@]} -gt 0 ]; then
        for profile in "${new_profiles[@]}"; do
            if [[ "$profile" == "python" ]] || [[ "$profile" == "ml" ]] || [[ "$profile" == "datascience" ]]; then
                has_python_profiles=true
                break
            fi
        done
    fi
    
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
        if [ ${#new_profiles[@]} -gt 0 ]; then
            for profile in "${new_profiles[@]+"${new_profiles[@]}"}"; do
                echo "$profile"
            done
        fi
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

export -f _cmd_profiles _cmd_profile _cmd_add _cmd_remove _cmd_install