#!/usr/bin/env bash
# Multi-slot container management system with CRC32 hashing
# Enables multiple authenticated Claude instances per project

# ============================================================================
# CRC32 Functions
# ============================================================================

# Compute CRC-32 of a string (for chaining)
crc32_word() {
    local val=$1
    # Simply hash the value as a string - no need for hex conversion
    printf '%s' "$val" | cksum | cut -d' ' -f1
}

# Compute CRC-32 of an arbitrary string; returns decimal 0..2^32-1
crc32_string() {
    printf '%s' "$1" | cksum | cut -d' ' -f1
}

# Compute CRC-32 of a file
crc32_file() {
    if [[ -f "$1" ]]; then
        cksum "$1" | cut -d' ' -f1
    else
        echo "0"
    fi
}

# ============================================================================
# Container Slot Management
# ============================================================================

# Slugify a filesystem path: strip leading '/', replace '/'→'_', remove unsafe chars
slugify_path() {
    local path=${1#/}
    path=${path//\//_}
    printf '%s' "${path//[^a-zA-Z0-9_]/_}"
}

# Generate a container name for a given path and index
generate_container_name() {
    local path="$1" idx="$2"
    local base_crc; base_crc=$(crc32_string "$path")
    local cur=$base_crc
    for ((i=0; i<idx; i++)); do
        cur=$(crc32_word "$cur")
    done
    printf '%08x' "$cur"
}

# Generate the parent folder name (with descriptive prefix)
generate_parent_folder_name() {
    local path="$1"
    local slug; slug=$(slugify_path "$path")
    # Convert to lowercase for Docker compatibility
    slug=$(echo "$slug" | tr '[:upper:]' '[:lower:]')
    local base_crc; base_crc=$(crc32_string "$path")
    printf '%s_%08x' "$slug" "$base_crc"
}

# Compute parent project directory: ~/.claudebox/projects/<slug>_<crc-of-index-0>
get_parent_dir() {
    echo "$HOME/.claudebox/projects/$(generate_parent_folder_name "$1")"
}


# Initialize project directory: create parent, counter, central profiles.ini
init_project_dir() {
    local path="$1" parent
    parent=$(get_parent_dir "$path")
    mkdir -p "$parent"
    # initialize counter if missing
    [[ -f "$parent/.project_container_counter" ]] || printf '1' > "$parent/.project_container_counter"
    # ensure central profiles.ini
    [[ -f "$parent/profiles.ini" ]] || touch "$parent/profiles.ini"
    # store project path
    echo "$path" > "$parent/.project_path"
    # set up commands symlink in parent (once per project)
    setup_claude_agent_command "$parent"
    # Sync commands to project
    sync_commands_to_project "$parent"
    
    # Copy common.sh to project parent directory if it doesn't exist
    local common_sh_target="$parent/common.sh"
    if [[ ! -f "$common_sh_target" ]]; then
        local common_sh_source="${CLAUDEBOX_SCRIPT_DIR:-${SCRIPT_DIR}}/lib/common.sh"
        if [[ -f "$common_sh_source" ]]; then
            cp "$common_sh_source" "$common_sh_target"
        fi
    fi
}

# Read/write per-project counter with locking
read_counter() {
    local p="$1" val=1
    [[ -f "$p/.project_container_counter" ]] && read -r val < "$p/.project_container_counter"
    echo "$val"
}

write_counter() {
    local p="$1" val="$2"
    printf '%d' "$val" > "$p/.project_container_counter"
}

# Acquire/release a lock on the counter via mkdir

# Initialize a container slot directory
init_slot_dir() {
    local dir="$1"
    mkdir -p "$dir"
    
    # Check if claude/ directory exists in the claudebox root to seed .claude
    local claude_source="${CLAUDEBOX_SCRIPT_DIR:-${SCRIPT_DIR}}/claude"
    if [[ -d "$claude_source" ]]; then
        # Copy the claude folder to .claude to seed it
        cp -r "$claude_source" "$dir/.claude"
    else
        # Fall back to creating empty .claude directory
        mkdir -p "$dir/.claude"
    fi
    
    mkdir -p "$dir/.config"
    mkdir -p "$dir/.cache"
    # Don't pre-create .claude.json - let Claude create it naturally
}

# Create or reuse a container slot:
# - Reuse missing "dead" slots first
# - Otherwise create next new slot
# - Initialize directories and .claude.json
create_container() {
    local path="$1" parent idx max name dir
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] create_container called with path: $path" >&2
    fi
    init_project_dir "$path"
    parent=$(get_parent_dir "$path")
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] parent dir: $parent" >&2
    fi

    # read max (no locking needed for single-user system)
    max=$(read_counter "$parent")
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] counter max: $max" >&2
    fi

    # attempt dead-slot reuse (starting from slot 1)
    for ((idx=1; idx<=max; idx++)); do
        name=$(generate_container_name "$path" "$idx")
        dir="$parent/$name"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] checking slot $idx: name=$name, dir=$dir" >&2
        fi
        if [[ ! -d "$dir" ]]; then
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] slot $idx doesn't exist, creating it" >&2
            fi
            init_slot_dir "$dir"
            echo "$name"
            return
        fi
    done

    # no dead slot: provision new at index=max+1
    idx=$((max + 1))
    name=$(generate_container_name "$path" "$idx")
    dir="$parent/$name"
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] creating new slot $idx: name=$name, dir=$dir" >&2
    fi
    init_slot_dir "$dir"
    write_counter "$parent" $idx
    echo "$name"
}

# Determine next container to start (skipping running containers)
# This is the old function that just finds any non-running slot
determine_next_start_container() {
    local path="$1" parent max idx name dir
    parent=$(get_parent_dir "$path")
    max=$(read_counter "$parent")
    for ((idx=1; idx<=max; idx++)); do
        name=$(generate_container_name "$path" "$idx")
        dir="$parent/$name"
        # Skip non-existent slots - they haven't been created yet
        [ -d "$dir" ] || continue
        
        # Check if a container with this slot name is running
        if ! docker ps --format "{{.Names}}" | grep -q "^claudebox-.*-${name}$"; then
            echo "$name"
            return 0
        fi
    done
    return 1
}

# Find the first authenticated and inactive slot
find_ready_slot() {
    local path="$1" parent max idx name dir
    parent=$(get_parent_dir "$path")
    max=$(read_counter "$parent")
    
    for ((idx=1; idx<=max; idx++)); do
        name=$(generate_container_name "$path" "$idx")
        dir="$parent/$name"
        
        # Skip non-existent slots
        [ -d "$dir" ] || continue
        
        # Check if authenticated
        [ -f "$dir/.claude/.credentials.json" ] || continue
        
        # Check if not running (inactive)
        if ! docker ps --format "{{.Names}}" | grep -q "^claudebox-.*-${name}$"; then
            echo "$name"
            return 0
        fi
    done
    
    # No ready slots found
    return 1
}

# Find any inactive slot (authenticated or not)
find_inactive_slot() {
    local path="$1" parent max idx name dir
    parent=$(get_parent_dir "$path")
    max=$(read_counter "$parent")
    
    for ((idx=1; idx<=max; idx++)); do
        name=$(generate_container_name "$path" "$idx")
        dir="$parent/$name"
        
        # Skip non-existent slots
        [ -d "$dir" ] || continue
        
        # Check if not running (inactive)
        if ! docker ps --format "{{.Names}}" | grep -q "^claudebox-.*-${name}$"; then
            echo "$name"
            return 0
        fi
    done
    
    # No inactive slots found
    return 1
}

# ============================================================================
# Main Functions
# ============================================================================

# Get the project folder name - returns the next available slot
get_project_folder_name() {
    local path="$1"
    # First ensure project is initialized
    init_project_dir "$path"
    
    # Find next available slot
    local slot_name
    if slot_name=$(determine_next_start_container "$path"); then
        echo "$slot_name"
    else
        # No slots available - return special marker
        echo "NONE"
    fi
}

# Get Docker image name for a specific slot
get_image_name() {
    local parent_folder_name=$(generate_parent_folder_name "${PROJECT_DIR}")
    printf 'claudebox-%s' "${parent_folder_name}"
}

# For backwards compatibility
_get_project_slug() {
    get_project_folder_name "$1"
}

# Get project by path - now checks parent directories
get_project_by_path() {
    local search_path="$1"
    local abs_path=$(realpath "$search_path" 2>/dev/null || echo "$search_path")
    
    # Check all parent directories in ~/.claudebox/projects/
    for parent_dir in "$HOME/.claudebox/projects"/*/ ; do
        [[ -d "$parent_dir" ]] || continue
        
        # Check if profiles.ini exists (indicates valid project)
        [[ -f "$parent_dir/profiles.ini" ]] || continue
        
        # For now, we can't easily reverse-lookup the original path
        # This would need to be stored somewhere
        # Return empty for now - this function may need redesign
        :
    done
    return 1
}

# List all projects - now shows parent directories with slot info
list_all_projects() {
    local projects_found=0
    
    # Iterate through parent directories
    for parent_dir in "$HOME/.claudebox/projects"/*/ ; do
        [[ -d "$parent_dir" ]] || continue
        projects_found=1
        
        local parent_name=$(basename "$parent_dir")
        local profiles_file="$parent_dir/profiles.ini"
        local slot_count=0
        local active_slots=0
        
        # Count slots
        if [[ -f "$parent_dir/.project_container_counter" ]]; then
            slot_count=$(read_counter "$parent_dir")
        fi
        
        # Count active slots (with lock files)
        for slot_dir in "$parent_dir"/*/ ; do
            [[ -d "$slot_dir" ]] || continue
            [[ -f "$slot_dir/lock" ]] && ((active_slots++))
        done
        
        # Check if Docker image exists
        local image_name="claudebox-${parent_name}"
        local image_status="❌"
        local image_size="-"
        
        if docker image inspect "$image_name" >/dev/null 2>&1; then
            image_status="✅"
            image_size=$(docker images --filter "reference=$image_name" --format "{{.Size}}")
        fi
        
        printf "%10s  %s  Slots: %d/%d  %s\n" "$image_size" "$image_status" "$active_slots" "$slot_count" "$parent_name"
    done
    
    [[ $projects_found -eq 0 ]] && return 1
    return 0
}

# Resolve project path - adapted for new structure
resolve_project_path() {
    local input_path="${1:-$PWD}"
    
    # Check if it's already a container name
    if [[ "$input_path" =~ _[a-f0-9]{8}$ ]]; then
        echo "$input_path"
        return 0
    fi
    
    # Otherwise, get the parent directory for this path
    local parent_name=$(get_project_folder_name "$input_path")
    echo "$parent_name"
    return 0
}

# ============================================================================
# New Multi-Slot Functions
# ============================================================================

# Auto-prune counter to remove trailing missing slots
prune_slot_counter() {
    local path="$1"
    local parent=$(get_parent_dir "$path")
    local max=$(read_counter "$parent")
    
    # Find highest existing slot
    local highest=0
    for ((idx=1; idx<=max; idx++)); do
        local name=$(generate_container_name "$path" "$idx")
        local dir="$parent/$name"
        if [ -d "$dir" ]; then
            highest=$idx
        fi
    done
    
    # Update counter if we can prune
    if [ $highest -lt $max ]; then
        write_counter "$parent" $highest
    fi
    # Always return 0 for success
    return 0
}

# List all slots for current project
list_project_slots() {
    local path="${1:-$PWD}"
    local parent=$(get_parent_dir "$path")
    
    if [ ! -d "$parent" ]; then
        echo "No project found for path: $path"
        return 1
    fi
    
    # Prune counter first
    prune_slot_counter "$path"
    local max=$(read_counter "$parent")
    
    logo_small
    echo
    
    if [ $max -eq 0 ]; then
        echo "Commands:"
        printf "  %-20s %s\n" "claudebox create" "Create new slot"
        echo
        echo "  Hint: Make sure you are in"
        echo "  a project root folder."
        echo
        echo "No slots created yet for $path"
        echo
        return 0
    fi
    
    echo "Commands:"
    echo
    printf "  %-20s %s\n" "claudebox create" "Create new slot"
    printf "  %-20s %s\n" "claudebox slot <n>" "Launch specific slot"
    printf "  %-20s %s\n" "claudebox revoke" "Remove highest slot"
    printf "  %-20s %s\n" "claudebox revoke all" "Remove all unused slots"
    echo
    
    echo "Slots for $path:"
    echo
    
    # Header
    printf "  Slot     Authentication       Status     Folder\n"
    printf "  ────   ─────────────────     ─────────  ────────\n"
    
    for ((idx=1; idx<=max; idx++)); do
        local name=$(generate_container_name "$path" "$idx")
        local dir="$parent/$name"
        local auth_icon="💀"
        local auth_text="Removed"
        local run_icon=""
        local run_text="N/A"
        
        if [ -d "$dir" ]; then
            # Check authentication status
            if [ -f "$dir/.claude/.credentials.json" ]; then
                auth_icon="✔️"
                auth_text="Authenticated"
            else
                auth_icon="🔒"
                auth_text="Unauthenticated"
            fi
            
            # Check if a container with this slot name is running
            if docker ps --format "{{.Names}}" | grep -q "^claudebox-.*-${name}$"; then
                run_icon="🟢"
                run_text="Active"
            else
                run_icon="🔴"
                run_text="Inactive"
            fi
        fi
        
        # Format with 2-space indent
        printf "   %-4s %s %-15s  %s  %-6s  %s\n" "$idx" "$auth_icon" "$auth_text" "$run_icon" "$run_text" "$name"
    done
    
    echo
    echo "Parent directory: $parent"
    echo
}

# Get slot directory by index
get_slot_dir() {
    local path="$1"
    local idx="${2:-0}"
    local parent=$(get_parent_dir "$path")
    local name=$(generate_container_name "$path" "$idx")
    echo "$parent/$name"
}

# Get slot index by name
get_slot_index() {
    local slot_name="$1"
    local parent_dir="$2"
    local path=$(dirname "$parent_dir")  # Get original path from parent
    local max=$(read_counter "$parent_dir")
    
    for ((idx=1; idx<=max; idx++)); do
        local name=$(generate_container_name "$path" "$idx")
        if [[ "$name" == "$slot_name" ]]; then
            echo "$idx"
            return 0
        fi
    done
    echo "-1"
    return 1
}

# Sync commands from bundled and user sources to project
sync_commands_to_project() {
    local project_parent="$1"
    local commands_dir="$project_parent/commands"
    local cbox_checksum_file="$project_parent/.commands_cbox_checksum"
    local user_checksum_file="$project_parent/.commands_user_checksum"
    
    # Source directories
    local cbox_source="${CLAUDEBOX_SCRIPT_DIR:-${SCRIPT_DIR}}/commands"
    local user_source="$HOME/.claude/commands"
    
    # Create commands directory if it doesn't exist
    mkdir -p "$commands_dir"
    
    # Calculate checksums of source directories
    local cbox_checksum=""
    local user_checksum=""
    
    # Get checksum of cbox commands if directory exists
    if [[ -d "$cbox_source" ]]; then
        # Find all files, get their content checksum, sort for consistency
        cbox_checksum=$(find "$cbox_source" -type f -exec sha256sum {} \; 2>/dev/null | sort | sha256sum | cut -d' ' -f1)
    fi
    
    # Get checksum of user commands if directory exists
    if [[ -d "$user_source" ]]; then
        user_checksum=$(find "$user_source" -type f -exec sha256sum {} \; 2>/dev/null | sort | sha256sum | cut -d' ' -f1)
    fi
    
    # Check if cbox commands need syncing
    local sync_cbox=false
    if [[ -d "$cbox_source" ]]; then
        if [[ ! -f "$cbox_checksum_file" ]]; then
            sync_cbox=true
        else
            local stored_cbox=$(cat "$cbox_checksum_file" 2>/dev/null || echo "")
            if [[ "$cbox_checksum" != "$stored_cbox" ]]; then
                sync_cbox=true
            fi
        fi
    fi
    
    # Check if user commands need syncing
    local sync_user=false
    if [[ -d "$user_source" ]]; then
        if [[ ! -f "$user_checksum_file" ]]; then
            sync_user=true
        else
            local stored_user=$(cat "$user_checksum_file" 2>/dev/null || echo "")
            if [[ "$user_checksum" != "$stored_user" ]]; then
                sync_user=true
            fi
        fi
    fi
    
    # Sync cbox commands
    if [[ "$sync_cbox" == "true" ]] && [[ -d "$cbox_source" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Syncing cbox commands to $commands_dir/cbox" >&2
        fi
        
        # Remove old cbox commands and recreate
        rm -rf "$commands_dir/cbox"
        mkdir -p "$commands_dir/cbox"
        
        # Copy preserving directory structure
        # Use find to handle subdirectories properly
        cd "$cbox_source"
        find . -type f | while read -r file; do
            local dir=$(dirname "$file")
            mkdir -p "$commands_dir/cbox/$dir"
            cp "$file" "$commands_dir/cbox/$file"
        done
        cd - >/dev/null
        
        # Save checksum
        echo "$cbox_checksum" > "$cbox_checksum_file"
    fi
    
    # Sync user commands
    if [[ "$sync_user" == "true" ]] && [[ -d "$user_source" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Syncing user commands to $commands_dir/user" >&2
        fi
        
        # Remove old user commands and recreate
        rm -rf "$commands_dir/user"
        mkdir -p "$commands_dir/user"
        
        # Copy preserving directory structure
        cd "$user_source"
        find . -type f | while read -r file; do
            local dir=$(dirname "$file")
            mkdir -p "$commands_dir/user/$dir"
            cp "$file" "$commands_dir/user/$file"
        done
        cd - >/dev/null
        
        # Save checksum
        echo "$user_checksum" > "$user_checksum_file"
    fi
    
    # Sync user agents (similar to commands)
    local agents_source="$HOME/.claude/agents"
    local agents_dir="$project_parent/agents"
    local agents_checksum_file="$project_parent/.agents_checksum"
    local agents_checksum=""
    
    # Calculate checksum for agents if directory exists
    if [[ -d "$agents_source" ]]; then
        agents_checksum=$(find "$agents_source" -type f -exec stat -f "%m" {} \; 2>/dev/null | sort | md5 2>/dev/null || \
                         find "$agents_source" -type f -exec stat -c "%Y" {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1)
        
        # Check if sync needed
        local sync_agents=false
        if [[ ! -f "$agents_checksum_file" ]]; then
            sync_agents=true
        elif [[ "$(cat "$agents_checksum_file" 2>/dev/null)" != "$agents_checksum" ]]; then
            sync_agents=true
        fi
        
        # Sync agents if needed
        if [[ "$sync_agents" == "true" ]]; then
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] Syncing agents to $agents_dir" >&2
            fi
            
            # Remove old agents and recreate
            rm -rf "$agents_dir"
            mkdir -p "$agents_dir"
            
            # Copy preserving directory structure
            cd "$agents_source"
            find . -type f | while read -r file; do
                local dir=$(dirname "$file")
                mkdir -p "$agents_dir/$dir"
                cp "$file" "$agents_dir/$file"
            done
            cd - >/dev/null
            
            # Save checksum
            echo "$agents_checksum" > "$agents_checksum_file"
        fi
    fi
    
    # Clean up agents directory if source doesn't exist
    if [[ ! -d "$agents_source" ]] && [[ -d "$agents_dir" ]]; then
        rm -rf "$agents_dir"
        rm -f "$agents_checksum_file"
    fi
    
    # Clean up empty directories if sources don't exist
    if [[ ! -d "$cbox_source" ]] && [[ -d "$commands_dir/cbox" ]]; then
        rm -rf "$commands_dir/cbox"
        rm -f "$cbox_checksum_file"
    fi
    
    if [[ ! -d "$user_source" ]] && [[ -d "$commands_dir/user" ]]; then
        rm -rf "$commands_dir/user"
        rm -f "$user_checksum_file"
    fi
}

# Export all functions
export -f crc32_word crc32_string crc32_file
export -f slugify_path generate_container_name generate_parent_folder_name get_parent_dir
export -f init_project_dir init_slot_dir
export -f read_counter write_counter
export -f create_container determine_next_start_container find_ready_slot find_inactive_slot
export -f get_project_folder_name get_image_name _get_project_slug
export -f get_project_by_path list_all_projects resolve_project_path
export -f list_project_slots get_slot_dir get_slot_index prune_slot_counter
export -f sync_commands_to_project
