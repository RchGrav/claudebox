#!/usr/bin/env bash
# Configuration management including INI files and profile definitions.

# -------- INI file helpers ----------------------------------------------------
_read_ini() {               # $1=file $2=section $3=key
  awk -F' *= *' -v s="[$2]" -v k="$3" '
    $0==s {in=1; next}
    /^\[/ {in=0}
    in && $1==k {print $2; exit}
  ' "$1" 2>/dev/null
}


# -------- Dynamic Profile System (Bash 3.2 compatible) -----------------------

# Get profile directories
get_profile_dirs() {
    # System profiles first (lower priority)
    local dirs=""
    if [[ -d "$SCRIPT_DIR/tooling/profiles" ]]; then
        dirs="$SCRIPT_DIR/tooling/profiles"
    fi
    # User profiles second (higher priority, can override system)
    if [[ -d "$HOME/.claudebox/profiles" ]]; then
        dirs="${dirs:+$dirs }$HOME/.claudebox/profiles"
    fi
    printf '%s\n' "$dirs"
}

# Execute a profile script with a command
execute_profile() {
    local profile="$1"
    local command="$2"
    
    # Search for profile script in directories (reverse order for priority)
    local profile_dirs
    profile_dirs=$(get_profile_dirs)
    
    # Check user profiles first (higher priority)
    if [[ -d "$HOME/.claudebox/profiles" ]] && [[ -x "$HOME/.claudebox/profiles/${profile}.sh" ]]; then
        "$HOME/.claudebox/profiles/${profile}.sh" "$command"
        return $?
    fi
    
    # Then check system profiles
    if [[ -d "$SCRIPT_DIR/tooling/profiles" ]] && [[ -x "$SCRIPT_DIR/tooling/profiles/${profile}.sh" ]]; then
        "$SCRIPT_DIR/tooling/profiles/${profile}.sh" "$command"
        return $?
    fi
    
    return 1
}

# Get all available profile names
get_all_profile_names() {
    local profiles=()
    local profile_dirs
    profile_dirs=$(get_profile_dirs)
    
    for dir in $profile_dirs; do
        if [[ -d "$dir" ]]; then
            for script in "$dir"/*.sh; do
                if [[ -f "$script" ]] && [[ -x "$script" ]]; then
                    local name
                    name=$(basename "$script" .sh)
                    # Add if not already in list
                    local found=false
                    for p in "${profiles[@]}"; do
                        if [[ "$p" == "$name" ]]; then
                            found=true
                            break
                        fi
                    done
                    if [[ "$found" == "false" ]]; then
                        profiles+=("$name")
                    fi
                fi
            done
        fi
    done
    
    printf '%s ' "${profiles[@]}"
}

# Check if a profile exists
profile_exists() {
    local profile="$1"
    local profile_dirs
    profile_dirs=$(get_profile_dirs)
    
    for dir in $profile_dirs; do
        if [[ -f "$dir/${profile}.sh" ]] && [[ -x "$dir/${profile}.sh" ]]; then
            return 0
        fi
    done
    return 1
}

# Get profile description
get_profile_description() {
    local profile="$1"
    local info
    info=$(execute_profile "$profile" "info" 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$info" ]]; then
        # Extract description part after the |
        printf '%s\n' "$info" | cut -d'|' -f2
    else
        printf '\n'
    fi
}

# Get profile packages
get_profile_packages() {
    local profile="$1"
    execute_profile "$profile" "packages" 2>/dev/null || printf '\n'
}

# Get profile Dockerfile content
get_profile_dockerfile() {
    local profile="$1"
    execute_profile "$profile" "dockerfile" 2>/dev/null || printf '\n'
}

# Expand profile with its dependencies
expand_profile() {
    local profile="$1"
    local expanded=()
    local visited=()
    
    # Recursive function to expand dependencies
    expand_deps() {
        local p="$1"
        # Check if already visited
        for v in "${visited[@]}"; do
            [[ "$v" == "$p" ]] && return
        done
        visited+=("$p")
        
        # Get dependencies
        local deps
        deps=$(execute_profile "$p" "depends" 2>/dev/null || echo "")
        
        # Process dependencies first (depth-first)
        for dep in $deps; do
            if profile_exists "$dep"; then
                expand_deps "$dep"
            fi
        done
        
        # Add this profile
        expanded+=("$p")
    }
    
    expand_deps "$profile"
    printf '%s ' "${expanded[@]}"
}

# -------- Profile file management ---------------------------------------------
get_profile_file_path() {
    # Use the parent directory name, not the slot name
    local parent_name=$(generate_parent_folder_name "$PROJECT_DIR")
    local parent_dir="$HOME/.claudebox/projects/$parent_name"
    mkdir -p "$parent_dir"
    echo "$parent_dir/profiles.ini"
}

read_config_value() {
    local config_file="$1"
    local section="$2"
    local key="$3"

    [[ -f "$config_file" ]] || return 1

    awk -F ' *= *' -v section="[$section]" -v key="$key" '
        $0 == section { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && $1 == key { print $2; exit }
    ' "$config_file"
}

read_profile_section() {
    local profile_file="$1"
    local section="$2"
    local result=()

    if [[ -f "$profile_file" ]] && grep -q "^\[$section\]" "$profile_file"; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^\[.*\]$ ]] && break
            result+=("$line")
        done < <(sed -n "/^\[$section\]/,/^\[/p" "$profile_file" | tail -n +2 | grep -v '^\[')
    fi

    printf '%s\n' "${result[@]}"
}

update_profile_section() {
    local profile_file="$1"
    local section="$2"
    shift 2
    local new_items=("$@")

    local existing_items=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && existing_items+=("$line")
    done < <(read_profile_section "$profile_file" "$section")

    local all_items=()
    for item in "${existing_items[@]}"; do
        [[ -n "$item" ]] && all_items+=("$item")
    done

    for item in "${new_items[@]}"; do
        local found=false
        for existing in "${all_items[@]}"; do
            [[ "$existing" == "$item" ]] && found=true && break
        done
        [[ "$found" == "false" ]] && all_items+=("$item")
    done

    {
        if [[ -f "$profile_file" ]]; then
            awk -v sect="$section" '
                BEGIN { in_section=0; skip_section=0 }
                /^\[/ {
                    if ($0 == "[" sect "]") { skip_section=1; in_section=1 }
                    else { skip_section=0; in_section=0 }
                }
                !skip_section { print }
                /^\[/ && !skip_section && in_section { in_section=0 }
            ' "$profile_file"
        fi

        echo "[$section]"
        for item in "${all_items[@]}"; do
            echo "$item"
        done
        echo ""
    } > "${profile_file}.tmp" && mv "${profile_file}.tmp" "$profile_file"
}

get_current_profiles() {
    local profiles_file="${PROJECT_PARENT_DIR:-$HOME/.claudebox/projects/$(generate_parent_folder_name "$PWD")}/profiles.ini"
    local current_profiles=()
    
    if [[ -f "$profiles_file" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && current_profiles+=("$line")
        done < <(read_profile_section "$profiles_file" "profiles")
    fi
    
    printf '%s\n' "${current_profiles[@]}"
}

# -------- Profile installation functions for Docker builds -------------------
# Legacy compatibility function - maps old function calls to new system
# This can be removed once main.sh is updated
get_profile_core() { get_profile_dockerfile "core"; }
get_profile_build_tools() { get_profile_dockerfile "build-tools"; }
get_profile_shell() { get_profile_dockerfile "shell"; }
get_profile_networking() { get_profile_dockerfile "networking"; }
get_profile_c() { get_profile_dockerfile "c"; }
get_profile_openwrt() { get_profile_dockerfile "openwrt"; }
get_profile_rust() { get_profile_dockerfile "rust"; }
get_profile_python() { get_profile_dockerfile "python"; }
get_profile_go() { get_profile_dockerfile "go"; }
get_profile_javascript() { get_profile_dockerfile "javascript"; }
get_profile_java() { get_profile_dockerfile "java"; }
get_profile_ruby() { get_profile_dockerfile "ruby"; }
get_profile_php() { get_profile_dockerfile "php"; }
get_profile_database() { get_profile_dockerfile "database"; }
get_profile_devops() { get_profile_dockerfile "devops"; }
get_profile_web() { get_profile_dockerfile "web"; }
get_profile_embedded() { get_profile_dockerfile "embedded"; }
get_profile_datascience() { get_profile_dockerfile "datascience"; }
get_profile_security() { get_profile_dockerfile "security"; }
get_profile_ml() { get_profile_dockerfile "ml"; }

# Export dynamic profile functions
export -f _read_ini get_profile_dirs execute_profile get_all_profile_names profile_exists
export -f get_profile_description get_profile_packages get_profile_dockerfile expand_profile
export -f get_profile_file_path read_config_value read_profile_section update_profile_section get_current_profiles
# Export legacy compatibility functions (can be removed after main.sh update)
export -f get_profile_core get_profile_build_tools get_profile_shell get_profile_networking get_profile_c get_profile_openwrt
export -f get_profile_rust get_profile_python get_profile_go get_profile_javascript get_profile_java get_profile_ruby
export -f get_profile_php get_profile_database get_profile_devops get_profile_web get_profile_embedded get_profile_datascience
export -f get_profile_security get_profile_ml