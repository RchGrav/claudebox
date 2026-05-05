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
            if [[ "$VERBOSE" == "true" ]]; then
                info "Symlink already correct: $LINK_TARGET → $SCRIPT_PATH"
            fi
            return 0
        else
            # Remove incorrect symlink
            rm -f "$LINK_TARGET"
            if [[ "$VERBOSE" == "true" ]]; then
                info "Removing outdated symlink"
            fi
        fi
    elif [[ -e "$LINK_TARGET" ]]; then
        # Something else exists at this path
        error "Cannot create symlink: $LINK_TARGET already exists and is not a symlink"
    fi

    # Create new symlink
    if ln -s "$SCRIPT_PATH" "$LINK_TARGET"; then
        success "Symlink updated: $LINK_TARGET → $SCRIPT_PATH"

        # Check if the directory is in PATH
        if [[ ":$PATH:" != *":$(dirname "$LINK_TARGET"):"* ]]; then
            echo ""
            warn "IMPORTANT: $(dirname "$LINK_TARGET") is not in your PATH"
            info "To use the 'claudebox' command, add this line to your ~/.zshrc or ~/.bashrc:"
            echo ""
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
            echo ""
            info "Then reload your shell or run: source ~/.zshrc"
            echo ""
            exit 0
        fi
    else
        warn "Could not create symlink at $LINK_TARGET"
        warn "Try running with sudo or ensure $(dirname "$LINK_TARGET") is writable"
        warn "Error: $?"
    fi
}


# Ensure shared commands folder exists and is up to date
setup_shared_commands() {
    local shared_commands="$CLAUDEBOX_GLOBAL_CLAUDE_COMMANDS_DIR"
    local legacy_claude_commands="$HOME/.claude/commands"
    local legacy_claudebox_commands="$CLAUDEBOX_HOME/commands"
    # Script is now at root, so SCRIPT_DIR is the root dir
    local commands_source="$SCRIPT_DIR/commands"

    # Create shared commands directory if it doesn't exist
    mkdir -p "$shared_commands"

    # Preserve existing user commands from legacy locations.
    local legacy_commands=""
    local file=""
    for legacy_commands in "$legacy_claude_commands" "$legacy_claudebox_commands"; do
        if [[ -d "$legacy_commands" ]] && [[ "$legacy_commands" != "$shared_commands" ]]; then
            for file in "$legacy_commands"/*; do
                if [[ -f "$file" ]]; then
                    local basename=$(basename "$file")
                    local dest_file="$shared_commands/$basename"
                    if [[ ! -e "$dest_file" ]]; then
                        cp "$file" "$dest_file"
                    fi
                fi
            done
        fi
    done

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
    # Takes parent directory as argument
    local parent_dir="${1:-}"
    [[ -z "$parent_dir" ]] && return 0

    # Copy bundled commands to parent folder
    local bundled_commands="$SCRIPT_DIR/commands"
    local commands_dest="$parent_dir/commands"

    # Only copy if commands destination doesn't already exist
    if [[ ! -e "$commands_dest" ]]; then
        if [[ -d "$bundled_commands" ]]; then
            # Copy bundled commands
            cp -r "$bundled_commands" "$commands_dest"

            if [[ "$VERBOSE" == "true" ]]; then
                info "Copied bundled commands to: $commands_dest"
            fi
        else
            # Create empty commands directory
            mkdir -p "$commands_dest"

            if [[ "$VERBOSE" == "true" ]]; then
                info "Created empty commands directory: $commands_dest"
            fi
        fi
    fi
}

# Calculate checksums for different Docker build layers
calculate_docker_layer_checksums() {
    local project_dir="${1:-$PROJECT_DIR}"
    # Since script is now at root, use SCRIPT_DIR which is already set
    local root_dir="$SCRIPT_DIR"
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] calculate_docker_layer_checksums: SCRIPT_PATH=$SCRIPT_PATH, root_dir=$root_dir" >&2
    fi

    # Layer 1: Base Dockerfile (rarely changes)
    local dockerfile_checksum=""
    if [[ -f "$root_dir/build/Dockerfile" ]]; then
        dockerfile_checksum=$(md5_file "$root_dir/build/Dockerfile")
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Dockerfile checksum: $dockerfile_checksum" >&2
        fi
    fi

    # Layer 2: Entrypoint and init scripts (occasional changes)
    local scripts_checksum=""
    local combined_content=""
    for file in "$root_dir/build/docker-entrypoint" "$root_dir/build/init-firewall"; do
        if [[ -f "$file" ]]; then
            local file_md5=$(md5_file "$file")
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] File: $file, MD5: $file_md5" >&2
            fi
            combined_content="${combined_content}${file_md5}"
        else
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] File not found: $file" >&2
            fi
        fi
    done
    # Compute MD5 of the combined MD5s
    if [[ -n "$combined_content" ]]; then
        scripts_checksum=$(md5_string "$combined_content")
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Combined scripts checksum: $scripts_checksum" >&2
        fi
    fi

    # Layer 3: Profile configuration (frequent changes)
    local profiles_checksum=""
    local profiles_ini="$PROJECT_PARENT_DIR/profiles.ini"
    if [[ -f "$profiles_ini" ]]; then
        profiles_checksum=$(md5_file "$profiles_ini")
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Profiles checksum: $profiles_checksum" >&2
        fi
    fi

    # Return layer checksums (first 8 chars of MD5 hex)
    echo "dockerfile:${dockerfile_checksum:0:8}"
    echo "scripts:${scripts_checksum:0:8}"
    echo "profiles:${profiles_checksum:0:8}"
}

# Check if Docker image needs rebuild and which layers changed
needs_docker_rebuild() {
    local project_dir="${1:-$PROJECT_DIR}"
    local image_name="${2:-$IMAGE_NAME}"
    local checksum_file="$PROJECT_PARENT_DIR/.docker_layer_checksums"
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] needs_docker_rebuild called with project_dir=$project_dir, image_name=$image_name" >&2
    fi

    # If no image exists, need rebuild
    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Image doesn't exist, rebuild needed" >&2
        fi
        return 0
    fi

    # Calculate current layer checksums
    local current_checksums=$(calculate_docker_layer_checksums "$project_dir")

    # If no checksum file, need rebuild
    if [[ ! -f "$checksum_file" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] No checksum file, rebuild needed" >&2
        fi
        return 0
    fi

    # Compare layer checksums
    local stored_checksums=$(cat "$checksum_file" 2>/dev/null || echo "")
    if [[ "$current_checksums" != "$stored_checksums" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Layer checksums changed, rebuild needed" >&2
        fi

        # Check if templates changed (dockerfile or scripts layers)
        local templates_changed=false

        # Show which layers changed
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Changed layers:" >&2
            while IFS= read -r current_line; do
                local layer="${current_line%%:*}"
                local current_hash="${current_line#*:}"
                local stored_hash=$(echo "$stored_checksums" | grep "^$layer:" | cut -d: -f2)
                if [[ "$current_hash" != "$stored_hash" ]]; then
                    echo "[DEBUG]   $layer: $stored_hash → $current_hash" >&2
                    if [[ "$layer" == "dockerfile" ]] || [[ "$layer" == "scripts" ]]; then
                        templates_changed=true
                    fi
                fi
            done <<< "$current_checksums"
        else
            # Still need to check if templates changed even without verbose
            while IFS= read -r current_line; do
                local layer="${current_line%%:*}"
                local current_hash="${current_line#*:}"
                local stored_hash=$(echo "$stored_checksums" | grep "^$layer:" | cut -d: -f2)
                if [[ "$current_hash" != "$stored_hash" ]]; then
                    if [[ "$layer" == "dockerfile" ]] || [[ "$layer" == "scripts" ]]; then
                        templates_changed=true
                        break
                    fi
                fi
            done <<< "$current_checksums"
        fi

        # If templates changed, we need to force no-cache
        if [[ "$templates_changed" == "true" ]]; then
            export CLAUDEBOX_FORCE_NO_CACHE=true
        fi

        return 0
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] All layer checksums match, no rebuild needed" >&2
    fi
    return 1
}

# Save Docker layer checksums after successful build
save_docker_layer_checksums() {
    local project_dir="${1:-$PROJECT_DIR}"
    local checksum_file="$PROJECT_PARENT_DIR/.docker_layer_checksums"

    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] save_docker_layer_checksums called" >&2
    fi
    local checksums=$(calculate_docker_layer_checksums "$project_dir")

    echo "$checksums" > "$checksum_file"
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] Saved layer checksums to $checksum_file:" >&2
        echo "$checksums" | sed 's/^/[DEBUG]   /' >&2
    fi
}

export -f update_symlink setup_shared_commands setup_claude_agent_command calculate_docker_layer_checksums needs_docker_rebuild save_docker_layer_checksums