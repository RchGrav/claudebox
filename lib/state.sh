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

setup_project_folder() {
    mkdir -p "$PROJECT_CLAUDEBOX_DIR/.claude"
    mkdir -p "$PROJECT_CLAUDEBOX_DIR/.config"
    mkdir -p "$PROJECT_CLAUDEBOX_DIR/.cache"
    if [[ ! -f "$PROJECT_CLAUDEBOX_DIR/.claude.json" ]]; then
        echo '{}' > "$PROJECT_CLAUDEBOX_DIR/.claude.json"
    fi

    local config_file="$PROJECT_CLAUDEBOX_DIR/config.ini"
    if [[ ! -f "$config_file" ]]; then
        cat > "$config_file" <<EOF
[project]
path = $PROJECT_DIR

[profiles]

[packages]
EOF
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

export -f update_symlink setup_project_folder setup_shared_commands setup_claude_agent_command