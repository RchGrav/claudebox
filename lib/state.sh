#!/usr/bin/env bash
# Folder creation, symlink maintenance and similar idempotent host operations.

# Create or refresh ~/.local/bin/claudebox → actual script location
update_symlink() {
    # Ensure the directory exists
    mkdir -p "$(dirname "$LINK_TARGET")"

    # Check if symlink exists and points to the correct location
    if [[ -L "$LINK_TARGET" ]]; then
        local current_target
        current_target=$(readlink "$LINK_TARGET" 2>/dev/null || echo "")
        if [[ "$current_target" == "$SCRIPT_PATH" ]]; then
            [[ "$VERBOSE" == "true" ]] && info "Symlink already correct: $LINK_TARGET → $SCRIPT_PATH"
            return 0
        else
            # Remove incorrect symlink
            rm -f "$LINK_TARGET"
            [[ "$VERBOSE" == "true" ]] && info "Removing outdated symlink"
        fi
    elif [[ -e "$LINK_TARGET" ]]; then
        # Something else exists at this path
        error "Cannot create symlink: $LINK_TARGET already exists and is not a symlink"
    fi

    # Create new symlink
    if ln -s "$SCRIPT_PATH" "$LINK_TARGET"; then
        success "Symlink updated: $LINK_TARGET → $SCRIPT_PATH"
    else
        warn "Could not create symlink at $LINK_TARGET"
        warn "Try running with sudo or ensure $(dirname "$LINK_TARGET") is writable"
        warn "Error: $?"
    fi
}


# Ensure shared commands folder exists and is up to date
setup_shared_commands() {
    local shared_commands="$HOME/.claudebox/commands"
    local script_dir="$(dirname "$SCRIPT_PATH")"
    local commands_source="$script_dir/commands"
    
    # Create shared commands directory if it doesn't exist
    mkdir -p "$shared_commands"
    
    # Copy/update commands from script directory if it exists
    if [[ -d "$commands_source" ]]; then
        # Copy new or updated files (preserve existing user files)
        cp -n "$commands_source/"* "$shared_commands/" 2>/dev/null || true
        
        # For existing files, only update if source is newer
        for file in "$commands_source"/*; do
            if [[ -f "$file" ]]; then
                local basename=$(basename "$file")
                local dest_file="$shared_commands/$basename"
                if [[ -f "$dest_file" ]] && [[ "$file" -nt "$dest_file" ]]; then
                    cp "$file" "$dest_file"
                    if [[ "$VERBOSE" == "true" ]]; then
                        info "Updated command: $basename"
                    fi
                fi
            fi
        done
        
        if [[ "$VERBOSE" == "true" ]]; then
            info "Synchronized commands to shared folder: $shared_commands"
        fi
    fi
}

setup_claude_agent_command() {
    # Check if PROJECT_CLAUDEBOX_DIR is set
    [[ -z "${PROJECT_CLAUDEBOX_DIR:-}" ]] && return 0
    
    # Create commands symlink in project's .claude folder (mounts to ~/.claude in container)
    local shared_commands="$HOME/.claudebox/commands"
    local commands_dest="$PROJECT_CLAUDEBOX_DIR/.claude/commands"
    
    # Only create symlink if commands destination doesn't already exist
    if [[ ! -e "$commands_dest" ]]; then
        # Ensure parent directory exists
        mkdir -p "$PROJECT_CLAUDEBOX_DIR/.claude"
        
        # Create symlink to shared commands
        ln -s "$shared_commands" "$commands_dest"
        
        if [[ "$VERBOSE" == "true" ]]; then
            info "Created commands symlink: $commands_dest -> $shared_commands"
        fi
    fi
}

# Calculate checksums for different Docker build layers
calculate_docker_layer_checksums() {
    local project_dir="${1:-$PROJECT_DIR}"
    local script_dir="$(dirname "$SCRIPT_PATH")"
    
    # Layer 1: Base Dockerfile (rarely changes)
    local dockerfile_checksum=""
    if [[ -f "$script_dir/assets/templates/Dockerfile.tmpl" ]]; then
        if command -v md5sum >/dev/null 2>&1; then
            dockerfile_checksum=$(md5sum "$script_dir/assets/templates/Dockerfile.tmpl" 2>/dev/null | cut -d' ' -f1)
        elif command -v md5 >/dev/null 2>&1; then
            dockerfile_checksum=$(md5 -q "$script_dir/assets/templates/Dockerfile.tmpl" 2>/dev/null)
        fi
    fi
    
    # Layer 2: Entrypoint and init scripts (occasional changes)
    local scripts_checksum=""
    for file in "$script_dir/assets/templates/docker-entrypoint.tmpl" "$script_dir/assets/templates/init-firewall"; do
        if [[ -f "$file" ]]; then
            if command -v md5sum >/dev/null 2>&1; then
                scripts_checksum+=$(md5sum "$file" 2>/dev/null | cut -d' ' -f1)
            elif command -v md5 >/dev/null 2>&1; then
                scripts_checksum+=$(md5 -q "$file" 2>/dev/null)
            fi
        fi
    done
    
    # Layer 3: Profile configuration (frequent changes)
    local profiles_checksum=""
    local profiles_ini="$PROJECT_PARENT_DIR/profiles.ini"
    if [[ -f "$profiles_ini" ]]; then
        if command -v md5sum >/dev/null 2>&1; then
            profiles_checksum=$(md5sum "$profiles_ini" 2>/dev/null | cut -d' ' -f1)
        elif command -v md5 >/dev/null 2>&1; then
            profiles_checksum=$(md5 -q "$profiles_ini" 2>/dev/null)
        fi
    fi
    
    # Return layer checksums
    echo "dockerfile:${dockerfile_checksum:0:8}"
    echo "scripts:${scripts_checksum:0:8}"
    echo "profiles:${profiles_checksum:0:8}"
}

# Check if Docker image needs rebuild and which layers changed
needs_docker_rebuild() {
    local project_dir="${1:-$PROJECT_DIR}"
    local image_name="${2:-$IMAGE_NAME}"
    local checksum_file="$PROJECT_PARENT_DIR/.docker_layer_checksums"
    
    # If no image exists, need rebuild
    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Image doesn't exist, rebuild needed" >&2
        return 0
    fi
    
    # Calculate current layer checksums
    local current_checksums=$(calculate_docker_layer_checksums "$project_dir")
    
    # If no checksum file, need rebuild
    if [[ ! -f "$checksum_file" ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] No checksum file, rebuild needed" >&2
        return 0
    fi
    
    # Compare layer checksums
    local stored_checksums=$(cat "$checksum_file" 2>/dev/null || echo "")
    if [[ "$current_checksums" != "$stored_checksums" ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Layer checksums changed, rebuild needed" >&2
        
        # Show which layers changed
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Changed layers:" >&2
            while IFS= read -r current_line; do
                local layer="${current_line%%:*}"
                local current_hash="${current_line#*:}"
                local stored_hash=$(echo "$stored_checksums" | grep "^$layer:" | cut -d: -f2)
                if [[ "$current_hash" != "$stored_hash" ]]; then
                    echo "[DEBUG]   $layer: $stored_hash → $current_hash" >&2
                fi
            done <<< "$current_checksums"
        fi
        
        return 0
    fi
    
    [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] All layer checksums match, no rebuild needed" >&2
    return 1
}

# Save Docker layer checksums after successful build
save_docker_layer_checksums() {
    local project_dir="${1:-$PROJECT_DIR}"
    local checksum_file="$PROJECT_PARENT_DIR/.docker_layer_checksums"
    local checksums=$(calculate_docker_layer_checksums "$project_dir")
    
    echo "$checksums" > "$checksum_file"
    [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] Saved layer checksums:" >&2
    [[ "$VERBOSE" == "true" ]] && echo "$checksums" | sed 's/^/[DEBUG]   /' >&2
}

export -f update_symlink setup_shared_commands setup_claude_agent_command calculate_docker_layer_checksums needs_docker_rebuild save_docker_layer_checksums