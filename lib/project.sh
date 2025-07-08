#!/usr/bin/env bash
# Multi-slot container management system with CRC32 hashing
# Enables multiple authenticated Claude instances per project

# ============================================================================
# CRC32 Functions
# ============================================================================

# Compute CRC-32 of a 32-bit word (big-endian or decimal input)
crc32_word() {
    local val=$1 hex
    if [[ $val =~ ^0[xX] ]]; then
        hex=${val#0x}
    else
        printf -v hex '%08X' "$val"
    fi
    hex=$(printf '%08s' "$hex" | tr ' ' '0')
    printf '%s' "$hex" | xxd -r -p | cksum | cut -d' ' -f1
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
    local slug; slug=$(slugify_path "$path")
    local base_crc; base_crc=$(crc32_string "$path")
    local cur=$base_crc
    for ((i=0; i<idx; i++)); do
        cur=$(crc32_word "$cur")
    done
    printf '%s_%08x' "$slug" "$cur"
}

# Compute parent project directory: ~/.claudebox/projects/<slug>_<crc-of-index-0>
get_parent_dir() {
    echo "$HOME/.claudebox/projects/$(generate_container_name "$1" 0)"
}

# Verify and (re)create profiles.ini symlink in all slots
verify_symlinks() {
    local parent="$1"
    for dir in "$parent"/*/; do
        [[ -d "$dir" ]] || continue
        local link="$dir/profiles.ini"
        if [[ ! -L "$link" ]] || [[ ! -e "$link" ]]; then
            ln -sfn "../profiles.ini" "$link"
        fi
    done
}

# Initialize project directory: create parent, counter, central profiles.ini, and verify children
init_project_dir() {
    local path="$1" parent
    parent=$(get_parent_dir "$path")
    mkdir -p "$parent"
    # initialize counter if missing
    [[ -f "$parent/.project_container_counter" ]] || printf '1' > "$parent/.project_container_counter"
    # ensure central profiles.ini
    [[ -f "$parent/profiles.ini" ]] || touch "$parent/profiles.ini"
    # ensure child symlinks are valid
    verify_symlinks "$parent"
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
lock_counter() {
    local p="$1" lockdir="$p/.counter.lock"
    while ! mkdir "$lockdir" 2>/dev/null; do
        sleep 0.05
    done
}

unlock_counter() {
    local p="$1" lockdir="$p/.counter.lock"
    rmdir "$lockdir"
}

# Create or reuse a container slot:
# - Reuse missing "dead" slots first
# - Otherwise create next new slot
# - Symlink shared profiles.ini
# - Protect counter updates with lock
create_container() {
    local path="$1" parent idx max name dir
    init_project_dir "$path"
    parent=$(get_parent_dir "$path")

    # lock counter and read max
    lock_counter "$parent"
    max=$(read_counter "$parent")

    # attempt dead-slot reuse
    for ((idx=0; idx<max; idx++)); do
        name=$(generate_container_name "$path" "$idx")
        dir="$parent/$name"
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            ln -sfn "../profiles.ini" "$dir/profiles.ini"
            unlock_counter "$parent"
            echo "$name"
            return
        fi
    done

    # no dead slot: provision new at index=max
    idx=$max
    name=$(generate_container_name "$path" "$idx")
    dir="$parent/$name"
    mkdir -p "$dir"
    ln -sfn "../profiles.ini" "$dir/profiles.ini"
    write_counter "$parent" $((max + 1))
    unlock_counter "$parent"
    echo "$name"
}

# Determine next container to start (skipping in-use & stale locks)
determine_next_start_container() {
    local path="$1" parent max idx name dir lockfile pid
    parent=$(get_parent_dir "$path")
    max=$(read_counter "$parent")
    for ((idx=0; idx<max; idx++)); do
        name=$(generate_container_name "$path" "$idx")
        dir="$parent/$name"
        # Skip non-existent slots - they haven't been created yet
        [[ -d "$dir" ]] || continue
        
        lockfile="$dir/lock"
        # unlocked slot => ready
        [[ -f "$lockfile" ]] || { echo "$name"; return 0; }
        pid=$(<"$lockfile")
        # stale lock => ready
        if ! ps -p "$pid" > /dev/null; then
            rm -f "$lockfile"
            echo "$name"; return 0
        fi
    done
    return 1
}

# ============================================================================
# Legacy/Compatibility Functions (adapted for slot-based system)
# ============================================================================

# Get the project folder name - now returns the next available slot
get_project_folder_name() {
    local path="$1"
    # First ensure project is initialized
    init_project_dir "$path"
    
    # Find next available slot
    local slot_name
    if slot_name=$(determine_next_start_container "$path"); then
        echo "$slot_name"
    else
        # No slots available
        error "No container slots available. Please run 'claudebox create' to create a new container slot."
    fi
}

# Get Docker image name for a specific slot
get_image_name() {
    local project_folder_name=$(get_project_folder_name "${PROJECT_DIR}")
    printf 'claudebox-%s' "${project_folder_name}"
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
        
        if docker image inspect "$image_name" &>/dev/null; then
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

# List all slots for current project
list_project_slots() {
    local path="${1:-$PWD}"
    local parent=$(get_parent_dir "$path")
    
    if [[ ! -d "$parent" ]]; then
        echo "No project found for path: $path"
        return 1
    fi
    
    local max=$(read_counter "$parent")
    echo "Project: $(basename "$parent")"
    echo "Total slots: $max"
    echo
    
    for ((idx=0; idx<max; idx++)); do
        local name=$(generate_container_name "$path" "$idx")
        local dir="$parent/$name"
        local status="[DEAD]"
        
        if [[ -d "$dir" ]]; then
            if [[ -f "$dir/lock" ]]; then
                local pid=$(<"$dir/lock")
                if ps -p "$pid" > /dev/null; then
                    status="[ACTIVE: PID $pid]"
                else
                    status="[STALE LOCK]"
                fi
            else
                status="[AVAILABLE]"
            fi
            
            # Check if authenticated
            if [[ -d "$dir/.claude" ]]; then
                status="$status [AUTHENTICATED]"
            else
                status="$status [NOT AUTHENTICATED]"
            fi
        fi
        
        printf "  Slot %d: %s %s\n" "$idx" "$name" "$status"
    done
}

# Get slot directory by index
get_slot_dir() {
    local path="$1"
    local idx="${2:-0}"
    local parent=$(get_parent_dir "$path")
    local name=$(generate_container_name "$path" "$idx")
    echo "$parent/$name"
}

# Export all functions
export -f crc32_word crc32_string crc32_file
export -f slugify_path generate_container_name get_parent_dir
export -f verify_symlinks init_project_dir
export -f read_counter write_counter lock_counter unlock_counter
export -f create_container determine_next_start_container
export -f get_project_folder_name get_image_name _get_project_slug
export -f get_project_by_path list_all_projects resolve_project_path
export -f list_project_slots get_slot_dir