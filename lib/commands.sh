#!/usr/bin/env bash
# Command Module Loader and Reference
# ============================================================================
# This is the central command management system for ClaudeBox.
# All command implementations are organized into logical modules below.

# ============================================================================
# CORE COMMANDS - Essential ClaudeBox operations
# ============================================================================
# Commands: help, shell, update
# - help: Shows ClaudeBox help and Claude CLI help
# - shell: Opens an interactive shell in the container
# - update: Updates Claude CLI and optionally ClaudeBox itself
# shellcheck source=lib/commands.core.sh
source "${LIB_DIR}/commands.core.sh"

# ============================================================================
# PROFILE COMMANDS - Development profile management
# ============================================================================
# Commands: profiles, profile, add, remove, install
# - profiles: Lists all available development profiles
# - profile: Shows profile management help
# - add: Adds development profiles to the project
# - remove: Removes profiles from the project
# - install: Installs additional apt packages
# shellcheck source=lib/commands.profile.sh
source "${LIB_DIR}/commands.profile.sh"

# ============================================================================
# SLOT COMMANDS - Container slot management
# ============================================================================
# Commands: create, slots, slot, revoke
# - create: Creates a new container slot for parallel instances
# - slots: Lists all container slots for the project
# - slot: Launches a specific numbered slot
# - revoke: Removes container slots
# shellcheck source=lib/commands.slot.sh
source "${LIB_DIR}/commands.slot.sh"

# ============================================================================
# INFO COMMANDS - Information display
# ============================================================================
# Commands: info, projects, allowlist
# - info: Shows comprehensive project and system information
# - projects: Lists all ClaudeBox projects system-wide
# - allowlist: Shows/manages the firewall allowlist
# shellcheck source=lib/commands.info.sh
source "${LIB_DIR}/commands.info.sh"

# ============================================================================
# CLEAN COMMANDS - Cleanup and maintenance
# ============================================================================
# Commands: clean, undo, redo
# - clean: Various cleanup operations (containers, images, cache, etc.)
# - undo: Restores the oldest backup of claudebox script
# - redo: Restores the newest backup of claudebox script
# shellcheck source=lib/commands.clean.sh
source "${LIB_DIR}/commands.clean.sh"

# ============================================================================
# SYSTEM COMMANDS - System utilities and special features
# ============================================================================
# Commands: save, unlink, rebuild, tmux, project
# - save: Saves default command-line flags
# - unlink: Removes the claudebox symlink
# - rebuild: Forces a Docker image rebuild
# - tmux: Launches ClaudeBox with tmux support
# - project: Opens a project by name from anywhere
# shellcheck source=lib/commands.system.sh
source "${LIB_DIR}/commands.system.sh"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Show menu when no slots exist
show_no_slots_menu() {
    logo_small
    echo
    cecho "No available slots found" "$YELLOW"
    echo
    printf "To continue, you'll need an available container slot.\n"
    echo
    printf '%b' "  ${CYAN}claudebox create${NC}  - Create a new slot\n"
    printf '%b' "  ${CYAN}claudebox slots${NC}   - View existing slots\n"
    echo
    printf '%b' "  ${DIM}Hint: Create multiple slots to run parallel authenticated${NC}\n"
    printf '%b' "  ${DIM}Claude sessions in the same project.${NC}\n"
    echo
    exit 1
}

# Show menu when no ready slots are available
show_no_ready_slots_menu() {
    logo_small
    printf '\n'
    cecho "No ready slots available!" "$YELLOW"
    printf '\n'
    printf '%s\n' "You must have at least one slot that is authenticated and inactive."
    printf '\n'
    printf '%s\n' "Run 'claudebox slots' to check your slots"
    printf '%s\n' "Run 'claudebox create' to create a new slot"
    printf '\n'
    printf '%s\n' "To use a specific slot: claudebox slot <number>"
    printf '\n'
}

# Show help function
show_help() {
    # Optional parameters
    local message="${1:-}"
    local footer="${2:-}"
    
    # ClaudeBox specific commands
    local our_commands="  profiles                        List all available profiles
  projects                        List all projects with paths
  add <profiles...>               Add development profiles
  remove <profiles...>            Remove development profiles
  install <packages>              Install apt packages
  import                          Import commands from host to project
  save [flags...]                 Save default flags
  shell                           Open transient shell
  shell admin                     Open admin shell (sudo enabled)
  allowlist                       Show/edit firewall allowlist
  info                            Show comprehensive project info
  clean                           Menu of cleanup tasks
  create                          Create new authenticated container slot
  slots                           List all container slots
  slot <number>                   Launch a specific container slot
  project <name>                  Open project by name/hash from anywhere
  tmux                            Launch ClaudeBox with tmux support enabled"
    
    # Check if we're in a project directory
    local project_folder_name
    project_folder_name=$(get_project_folder_name "$PROJECT_DIR" 2>/dev/null || echo "NONE")
    
    if [[ "$project_folder_name" != "NONE" ]] && [[ -n "${IMAGE_NAME:-}" ]] && docker image inspect "$IMAGE_NAME" &>/dev/null; then
        # In project directory with Docker image - show brief ClaudeBox help and note about Claude commands
        echo
        logo_small
        echo
        echo "Usage: claudebox [OPTIONS] [COMMAND]"
        echo
        echo "Docker Environment for Claude CLI"
        echo
        echo "Options:"
        echo "  -h, --help                      Display help for command"
        echo "  --verbose                        Show detailed output"
        echo "  --clipboard                      Enable macOS image paste and text copy"
        echo "  --enable-sudo                    Enable sudo without password"
        echo "  --disable-firewall               Disable network restrictions"
        echo
        echo "ClaudeBox Commands:"
        echo "$our_commands"
        echo
        cecho "For Claude CLI commands, run:" "$CYAN"
        cecho "  claudebox help claude" "$CYAN"
        echo
        cecho "For full command reference, run:" "$CYAN"
        cecho "  claudebox help full" "$CYAN"
        echo
    else
        # No Docker image - show compact menu
        echo
        logo_small
        echo
        echo "Usage: claudebox [OPTIONS] [COMMAND]"
        echo
        if [[ -n "$message" ]]; then
            echo "$message"
        else
            echo "Docker Environment for Claude CLI"
        fi
        echo
        echo "Options:"
        echo "  -h, --help                      Display help for command"
        echo "  --verbose                        Show detailed output"
        echo "  --clipboard                      Enable macOS image paste and text copy"
        echo "  --enable-sudo                    Enable sudo without password"
        echo "  --disable-firewall               Disable network restrictions"
        echo
        echo "Commands:"
        echo "$our_commands"
        echo
        if [[ -n "$footer" ]]; then
            cecho "$footer" "$YELLOW"
            echo
        fi
    fi
}

# Show Claude help (runs Claude's help in container)
show_claude_help() {
    if [[ -n "${IMAGE_NAME:-}" ]] && docker image inspect "$IMAGE_NAME" &>/dev/null; then
        # Get Claude's help and just change claude to claudebox in the header
        local claude_help
        claude_help=$(docker run --rm "$IMAGE_NAME" claude --help 2>&1 | grep -v "iptables")
        
        # Just change claude to claudebox in the first line
        local processed_help
        processed_help=$(echo "$claude_help" | sed '1s/claude/claudebox/g')
        
        # Output everything at once
        echo
        logo_small
        echo
        echo "$processed_help"
    else
        error "No Docker image found for this project. Run 'claudebox' first to build the image."
    fi
}

# Show full combined help
show_full_help() {
    if [[ -n "${IMAGE_NAME:-}" ]] && docker image inspect "$IMAGE_NAME" &>/dev/null; then
        # Get Claude's help and blend our additions
        local claude_help
        claude_help=$(docker run --rm "$IMAGE_NAME" claude --help 2>&1 | grep -v "iptables")
        
        # Process and combine everything in memory
        local full_help
        full_help=$(echo "$claude_help" | \
            sed '1s/claude/claudebox/g' | \
            sed '/^Commands:/i\
  --verbose                        Show detailed output\
  --clipboard                      Enable macOS image paste and text copy\
  --enable-sudo                    Enable sudo without password\
  --disable-firewall               Disable network restrictions\
' | \
            sed '$ a\
  profiles                        List all available profiles\
  projects                        List all projects with paths\
  add <profiles...>               Add development profiles\
  remove <profiles...>            Remove development profiles\
  install <packages>              Install apt packages\
  import                          Import commands from host to project\
  save [flags...]                 Save default flags\
  shell                           Open transient shell\
  shell admin                     Open admin shell (sudo enabled)\
  allowlist                       Show/edit firewall allowlist\
  info                            Show comprehensive project info\
  clean                           Menu of cleanup tasks\
  create                          Create new authenticated container slot\
  slots                           List all container slots\
  slot <number>                   Launch a specific container slot\
  project <name>                  Open project by name/hash from anywhere\
  tmux                            Launch ClaudeBox with tmux support enabled')
        
        # Output everything at once
        echo
        logo_small
        echo
        echo "$full_help"
    else
        # No Docker image - show compact menu (same as show_help)
        show_help "" ""
    fi
}

# Forward unknown commands to container
_forward_to_container() {
    run_claudebox_container "" "interactive" "$@"
}

# ============================================================================
# MAIN DISPATCHER
# ============================================================================
# Routes commands to their handlers based on the parsed CLI_SCRIPT_COMMAND
dispatch_command() {
    local cmd="${1:-}"; shift || true
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] dispatch_command called with: cmd='$cmd' remaining args='$*'" >&2
    fi
    
    case "${cmd}" in
        # Core commands
        help|-h|--help)   _cmd_help "$@" ;;
        shell)            _cmd_shell "$@" ;;
        update)           _cmd_update "$@" ;;
        
        # Profile commands
        profiles)         _cmd_profiles "$@" ;;
        profile)          _cmd_profile "$@" ;;
        add)              _cmd_add "$@" ;;
        remove)           _cmd_remove "$@" ;;
        install)          _cmd_install "$@" ;;
        
        # Slot commands
        create)           _cmd_create "$@" ;;
        slots)            _cmd_slots "$@" ;;
        slot)             _cmd_slot "$@" ;;
        revoke)           _cmd_revoke "$@" ;;
        
        # Info commands
        projects)         _cmd_projects "$@" ;;
        allowlist)        _cmd_allowlist "$@" ;;
        info)             _cmd_info "$@" ;;
        
        # Clean commands
        clean)            _cmd_clean "$@" ;;
        undo)             _cmd_undo "$@" ;;
        redo)             _cmd_redo "$@" ;;
        
        # System commands
        save)             _cmd_save "$@" ;;
        unlink)           _cmd_unlink "$@" ;;
        rebuild)          _cmd_rebuild "$@" ;;
        tmux)             _cmd_tmux "$@" ;;
        project)          _cmd_project "$@" ;;
        import)           _cmd_import "$@" ;;
        kill)             _cmd_kill "$@" ;;
        
        # Special commands that modify container
        config|mcp|migrate-installer) 
                          _cmd_special "$cmd" "$@" ;;
        
        # Unknown command - forward to Claude in container
        *)                _forward_to_container "${cmd}" "$@" ;;
    esac
    
    local exit_code=$?
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] dispatch_command returning with exit code: $exit_code" >&2
    fi
    return $exit_code
}

# Export all public functions
export -f dispatch_command show_help show_claude_help show_full_help show_no_slots_menu show_no_ready_slots_menu _forward_to_container