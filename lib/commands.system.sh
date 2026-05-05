#!/usr/bin/env bash
# System Commands - System-level operations and utilities
# ============================================================================
# Commands: save, unlink, rebuild, tmux, open
# System utilities and special features


_cmd_save() {
    local defaults_file="${CLAUDEBOX_HOME}/default-flags"

    if [[ $# -eq 0 ]]; then
        if [[ -f "$defaults_file" ]]; then
            rm -f "$defaults_file"
            success "Cleared saved default flags"
        else
            info "No saved default flags to clear"
        fi
    else
        mkdir -p "${CLAUDEBOX_HOME}"
        printf '%s\n' "$@" > "$defaults_file"
        success "Saved default flags: $*"
    fi
    exit 0
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

_cmd_rebuild() {
    # Set rebuild flag and continue with normal execution
    export REBUILD=true

    # Remove 'rebuild' from the arguments and continue
    # This allows "claudebox rebuild" to rebuild then launch Claude
    # or "claudebox rebuild shell" to rebuild then open shell
    _forward_to_container "${@}"
}

_cmd_kill() {
    local target="${1:-}"
    local killed_containers=0

    if [[ "$target" == "all" ]]; then
        # Kill ALL claudebox containers
        info "Killing all ClaudeBox containers..."

        local containers=$(docker ps --filter "name=^claudebox-" --format "{{.Names}}")
        if [[ -n "$containers" ]]; then
            while IFS= read -r container; do
                if [[ -n "$container" ]]; then
                    docker stop "$container" >/dev/null 2>&1 && ((killed_containers++)) || true
                fi
            done <<< "$containers"
            success "Stopped $killed_containers container(s)"
        else
            info "No ClaudeBox containers found"
        fi
    elif [[ -n "$target" ]]; then
        # Kill specific container by hash or name
        local matching_container=""

        # Check if it's a hash (8 hex chars)
        if [[ "$target" =~ ^[a-f0-9]{8}$ ]]; then
            matching_container=$(docker ps --filter "name=claudebox-.*-$target$" --format "{{.Names}}" | head -1)
        else
            # Try partial name match
            matching_container=$(docker ps --filter "name=claudebox-.*$target" --format "{{.Names}}" | head -1)
        fi

        if [[ -n "$matching_container" ]]; then
            info "Killing container: $matching_container"
            if docker stop "$matching_container" >/dev/null 2>&1; then
                success "Killed container: $matching_container"
            else
                error "Failed to kill container: $matching_container"
            fi
        else
            error "No container found matching: $target"
        fi
    else
        # No argument - show active containers
        local containers=$(docker ps --filter "name=^claudebox-" --format "{{.Names}}")

        if [[ -z "$containers" ]]; then
            info "No active ClaudeBox containers"
            exit 0
        fi

        logo_small
        echo
        cecho "Active ClaudeBox Containers" "$CYAN"
        echo

        echo "$containers" | while IFS= read -r container; do
            local slot_hash=${container##*-}
            local project_part=${container#claudebox-}
            project_part=${project_part%-$slot_hash}
            echo "  $slot_hash - $project_part"
        done
        echo

        echo "Usage:"
        printf "  %-25s %s\n" "claudebox kill <hash>" "Kill specific container"
        printf "  %-25s %s\n" "claudebox kill <name>" "Kill by partial name"
        printf "  %-25s %s\n" "claudebox kill all" "Kill ALL containers"
        echo
    fi

    exit 0
}

_cmd_tmux() {
    # If no arguments OR first argument is a flag, show menu
    if [[ $# -eq 0 ]] || [[ "${1:-}" =~ ^- ]]; then
        logo_small
        echo
        cecho "Tmux Integration for ClaudeBox" "$CYAN"
        echo

        # Check available slots - derive project info like clean does
        local available_count=0
        local authenticated_count=0

        # Get project folder name for current directory
        local project_folder_name=$(generate_parent_folder_name "$PROJECT_DIR" 2>/dev/null || echo "")
        local parent_dir="$HOME/.claudebox/projects/$project_folder_name"

        if [[ -n "$project_folder_name" ]] && [[ -d "$parent_dir" ]]; then
            local max_slot=$(read_counter "$parent_dir" 2>/dev/null || echo "0")
            for ((idx=1; idx<=max_slot; idx++)); do
                local slot_name=$(generate_container_name "$PROJECT_DIR" "$idx")
                local slot_dir="$parent_dir/$slot_name"

                if [[ -d "$slot_dir" ]]; then
                    ((available_count++)) || true
                    if [[ -f "$slot_dir/.claude/.credentials.json" ]]; then
                        ((authenticated_count++)) || true
                    fi
                fi
            done
        fi

        cecho "Available Slots:" "$GREEN"
        printf "  You have %d slot(s) (%d authenticated)\n" "$available_count" "$authenticated_count"
        echo
        printf "  %-20s %s\n" "claudebox slots" "Manage slots for this project"
        echo

        echo "Usage:"
        printf "  %-20s %s\n" "tmux <N>" "Launch N panes (e.g., tmux 3 for 3 panes)"
        printf "  %-20s %s\n" "tmux 2 1" "Multiple windows (2 panes in window 1, 1 pane in window 2)"
        printf "  %-20s %s\n" "tmux conf" "Install tmux configuration"
        echo

        cecho "Tmux Shortcuts (after tmux conf):" "$GREEN"
        echo "  • Ctrl+Alt+Arrow: Navigate panes"
        echo "  • Ctrl+Alt+0: Zoom toggle"
        echo "  • Ctrl+a: Prefix key"
        echo
        exit 0
    fi

    # Handle tmux subcommands
    if [[ "${1:-}" == "conf" ]]; then
        _install_tmux_conf
        exit 0
    fi

    if [[ "${1:-}" == "kill" ]]; then
        # If a session name is provided as an argument, use it
        # Otherwise, try to use current directory's project name
        local session_arg="${2:-}"
        local killed_containers=0
        local killed_sessions=0

        if [[ "$session_arg" == "all" ]]; then
            # Kill ALL - the dangerous command is explicit
            info "Killing ALL ClaudeBox tmux sessions and containers..."

            # Get all claudebox tmux sessions
            local sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^claudebox-" || true)

            if [[ -n "$sessions" ]]; then
                while IFS= read -r session; do
                    if [[ -n "$session" ]]; then
                        tmux kill-session -t "$session" 2>/dev/null && ((killed_sessions++)) || true
                    fi
                done <<< "$sessions"
            fi

            # Kill ALL claudebox containers
            local containers=$(docker ps --filter "name=^claudebox-" --format "{{.Names}}")
            if [[ -n "$containers" ]]; then
                while IFS= read -r container; do
                    if [[ -n "$container" ]]; then
                        docker stop "$container" >/dev/null 2>&1 && ((killed_containers++)) || true
                    fi
                done <<< "$containers"
            fi

            if [[ $killed_sessions -gt 0 ]] || [[ $killed_containers -gt 0 ]]; then
                if [[ $killed_sessions -gt 0 ]]; then
                    success "Killed $killed_sessions tmux session(s)"
                fi
                if [[ $killed_containers -gt 0 ]]; then
                    success "Stopped $killed_containers container(s)"
                fi
            else
                info "No ClaudeBox sessions or containers found"
            fi
            exit 0
        elif [[ -z "$session_arg" ]]; then
            # No argument - show the menu (moved this up to catch empty args)
            # Show menu of active sessions
            local sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^claudebox-" || true)
            local containers=$(docker ps --filter "name=^claudebox-" --format "{{.Names}}")

            if [[ -z "$sessions" ]] && [[ -z "$containers" ]]; then
                info "No active ClaudeBox sessions or containers"
                exit 0
            fi

            logo_small
            echo
            cecho "ClaudeBox Active Sessions" "$CYAN"
            echo

            if [[ -n "$sessions" ]]; then
                cecho "Tmux Sessions:" "$GREEN"
                echo "$sessions" | while IFS= read -r session; do
                    # Extract project name from session
                    local proj_name=${session#claudebox-}
                    echo "  $session"

                    # Show containers for this session
                    local session_containers=$(echo "$containers" | grep "^$session-" || true)
                    if [[ -n "$session_containers" ]]; then
                        echo "$session_containers" | while IFS= read -r container; do
                            local slot_hash=${container##*-}
                            echo "    └─ $slot_hash"
                        done
                    fi
                done
                echo
            fi

            # Show orphaned containers (no tmux session)
            local orphans=""
            if [[ -n "$containers" ]] && [[ -n "$sessions" ]]; then
                # Build pattern from sessions
                local pattern=$(echo "$sessions" | sed 's/^/^/' | sed 's/$/-/' | tr '\n' '|' | sed 's/|$//')
                orphans=$(echo "$containers" | grep -v -E "$pattern" || true)
            elif [[ -n "$containers" ]]; then
                # No sessions, all containers are orphans
                orphans="$containers"
            fi

            if [[ -n "$orphans" ]]; then
                cecho "Orphaned Containers (no tmux session):" "$YELLOW"
                echo "$orphans" | while IFS= read -r container; do
                    echo "  $container"
                done
                echo
            fi

            echo "Usage:"
            printf "  %-30s %s\n" "claudebox tmux kill <name>" "Kill specific session/container"
            printf "  %-30s %s\n" "claudebox tmux kill <hash>" "Kill specific container by hash"
            printf "  %-30s %s\n" "claudebox tmux kill all" "Kill ALL sessions and containers"
            echo

            exit 0
        elif [[ -n "$session_arg" ]]; then
            # Check if this looks like a container hash (8 hex chars)
            if [[ "$session_arg" =~ ^[a-f0-9]{8}$ ]]; then
                # This is a container hash - kill just that container (Lost Boys child rule)
                local matching_container=$(docker ps --filter "name=claudebox-.*-$session_arg$" --format "{{.Names}}" | head -1)

                if [[ -n "$matching_container" ]]; then
                    info "Killing container: $matching_container"
                    if docker stop "$matching_container" >/dev/null 2>&1; then
                        ((killed_containers++)) || true
                        success "Killed container: $matching_container"

                        # Find which pane has this container and kill just that pane
                        # This is tricky - for now just kill the container
                        info "Note: Tmux pane may still be visible but container is stopped"
                    fi
                else
                    error "No container found with hash: $session_arg"
                    exit 1
                fi
            else
                # Not a container hash - look for session matches (Lost Boys parent rule)
                local matching_sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "claudebox-.*$session_arg" || true)
                local match_count=0
                if [[ -n "$matching_sessions" ]]; then
                    match_count=$(echo "$matching_sessions" | wc -l | tr -d ' ')
                fi

                if [[ $match_count -eq 0 ]]; then
                    # Try exact match with claudebox- prefix
                    if tmux has-session -t "claudebox-$session_arg" 2>/dev/null; then
                        matching_sessions="claudebox-$session_arg"
                        match_count=1
                    else
                        error "No ClaudeBox sessions found matching: $session_arg"
                        exit 1
                    fi
                elif [[ $match_count -gt 1 ]]; then
                    # Multiple matches - show them and exit
                    error "Multiple sessions match '$session_arg':"
                    echo "$matching_sessions" | while IFS= read -r session; do
                        echo "  $session"
                    done
                    echo
                    echo "Please be more specific."
                    exit 1
                fi

                # Single match - kill parent and all children
                local session_name="$matching_sessions"

                # Kill ALL containers for this session (all children die with parent)
                local containers=$(docker ps --filter "name=^$session_name-" --format "{{.Names}}")
                if [[ -n "$containers" ]]; then
                    info "Stopping all containers for session: $session_name"
                    while IFS= read -r container; do
                        if [[ -n "$container" ]]; then
                            docker stop "$container" >/dev/null 2>&1 && ((killed_containers++)) || true
                        fi
                    done <<< "$containers"
                fi

                # Kill the tmux session (parent dies)
                if tmux has-session -t "$session_name" 2>/dev/null; then
                    tmux kill-session -t "$session_name"
                    ((killed_sessions++)) || true
                    success "Killed session: $session_name (Lost Boys rule - all children died with parent)"
                fi
            fi
        fi
        # This else block should never be reached now

        # Report results
        if [[ $killed_sessions -gt 0 ]] || [[ $killed_containers -gt 0 ]]; then
            if [[ $killed_sessions -gt 0 ]]; then
                success "Killed $killed_sessions tmux session(s)"
            fi
            if [[ $killed_containers -gt 0 ]]; then
                success "Stopped $killed_containers container(s)"
            fi
        else
            info "No ClaudeBox sessions or containers found"
        fi

        exit 0
    fi

    # Check if tmux is installed on the host
    if ! command -v tmux >/dev/null 2>&1; then
        error "tmux is not installed on the host system.
Please install tmux first:
  Ubuntu/Debian: sudo apt-get install tmux
  macOS: brew install tmux
  RHEL/CentOS: sudo yum install tmux"
    fi

    # Let Claude Code manage pane names automatically

    # Parse layout parameter if provided
    local layout="${1:-}"
    local total_slots_needed=1
    local window_configs=()

    # Collect all numeric arguments for layout
    local window_panes=()
    for arg in "$@"; do
        if [[ "$arg" =~ ^[0-9]+$ ]]; then
            window_panes+=("$arg")
        elif [[ "$arg" =~ ^- ]]; then
            # Stop at first flag
            break
        fi
    done

    # Check if we're in a valid project directory for layout commands
    if [[ ${#window_panes[@]} -gt 0 ]] || [[ -n "$layout" ]]; then
        # We need slots for layouts, so check if this is a valid project
        local project_folder_name
        project_folder_name=$(get_project_folder_name "$PROJECT_DIR" 2>/dev/null || echo "NONE")

        if [[ "$project_folder_name" == "NONE" ]]; then
            error "Tmux layouts require a valid project directory.
Please cd to your project directory first.
Current directory: $PWD"
        fi
    fi

    # Set up slot variables first - we need PROJECT_PARENT_DIR for slot validation
    if [[ -z "${IMAGE_NAME:-}" ]]; then
        local project_folder_name
        project_folder_name=$(get_project_folder_name "$PROJECT_DIR" 2>/dev/null || echo "NONE")

        if [[ "$project_folder_name" == "NONE" ]]; then
            show_no_slots_menu  # This will exit
        fi

        IMAGE_NAME=$(get_image_name)
        PROJECT_SLOT_DIR="$PROJECT_PARENT_DIR/$project_folder_name"
        export PROJECT_SLOT_DIR
    fi

    if [[ ${#window_panes[@]} -gt 0 ]]; then
        # Calculate total slots needed
        total_slots_needed=0
        for panes in "${window_panes[@]}"; do
            ((total_slots_needed += panes)) || true
        done

        # Special case: single "1" means just run regular tmux
        if [[ ${#window_panes[@]} -eq 1 ]] && [[ "${window_panes[0]}" == "1" ]]; then
            layout=""
        else
            layout="multi"
            # window_panes array contains the layout
        fi
    else
        layout=""
    fi


    # Generate container name
    local slot_name=$(basename "$PROJECT_SLOT_DIR")
    local parent_folder_name=$(generate_parent_folder_name "$PROJECT_DIR")
    local container_name="claudebox-${parent_folder_name}-${slot_name}"

    # Check if we're already in a tmux session
    if [[ -n "${TMUX:-}" ]]; then
        info "Already in a tmux session. Running ClaudeBox directly..."
        # Just run the container normally - socket will be auto-mounted
        run_claudebox_container "$container_name" "interactive" "$@"
    else
        # Create new tmux session with layout if specified
        if [[ -n "$layout" ]]; then

                # Get available slots (not currently running)
                local available_slots=()
                local max_slot=$(read_counter "$PROJECT_PARENT_DIR")

                for ((idx=1; idx<=max_slot; idx++)); do
                    local slot_name=$(generate_container_name "$PROJECT_DIR" "$idx")
                    local slot_dir="$PROJECT_PARENT_DIR/$slot_name"

                    # Check if slot exists and is not currently running
                    if [[ -d "$slot_dir" ]] && ! docker ps --format "{{.Names}}" | grep -q "^claudebox-.*-${slot_name}$"; then
                        available_slots+=("$idx")
                    fi
                done

                # Initialize slot_index for all layout types
                local slot_index=0

                # Simple layout - use quick tmux without persistent session
                if [[ "$layout" =~ ^[0-9]+$ ]] && [[ $layout -le 4 ]]; then
                    # For simple layouts (1-4 panes), create non-persistent session
                    local session_name="claudebox-$(basename "$PROJECT_DIR")"
                    local captured_panes=()

                    # Create first pane and capture its ID atomically
                    local first_slot="${available_slots[0]}"
                    # new-session doesn't support -P -F, so we create it and get the pane ID immediately after
                    if ! tmux new-session -s "$session_name" -d "env CLAUDEBOX_SLOT_NUMBER=$first_slot $SCRIPT_PATH slot $first_slot"; then
                        error "Failed to create tmux session. Make sure slot $first_slot exists."
                    fi
                    tmux rename-window -t "$session_name" 'ClaudeBox Multi'

                    # Get the first pane ID (session creation always creates exactly one pane)
                    local first_pane_id=$(tmux display -t "$session_name:0.0" -p '#{pane_id}')
                    captured_panes+=("$first_pane_id")

                    if [[ "$VERBOSE" == "true" ]]; then
                        echo "[DEBUG] Created first pane: $first_pane_id" >&2
                    fi

                    # Create additional panes one by one and capture their IDs atomically
                    local slot_index=1
                    for ((i=1; i<$layout; i++)); do
                        local slot="${available_slots[$slot_index]}"

                        # Split and create new pane - capture ID atomically with -P -F
                        local new_pane_id=$(tmux split-window -t "$session_name" -e "CLAUDEBOX_SLOT_NUMBER=$slot" -P -F '#{pane_id}' "$SCRIPT_PATH slot $slot")

                        captured_panes+=("$new_pane_id")
                        if [[ "$VERBOSE" == "true" ]]; then
                            echo "[DEBUG] Created pane $((i+1)): $new_pane_id" >&2
                        fi

                        ((slot_index++)) || true
                    done

                    # Enable pane border status
                    tmux set-option -t "$session_name" -g pane-border-status top

                    # Add tiled layout if more than 2 panes
                    if [[ $layout -gt 2 ]]; then
                        tmux select-layout -t "$session_name" tiled
                    fi

                    # Wait for containers and Claude to be ready
                    sleep 8

                    # Send activate command only to authenticated slots
                    if [[ "$VERBOSE" == "true" ]]; then
                        echo "[DEBUG] Checking authentication for ${#captured_panes[@]} panes" >&2
                    fi

                    for ((i=0; i<${#captured_panes[@]}; i++)); do
                        local pane_id="${captured_panes[$i]}"
                        local slot_num="${available_slots[$i]}"
                        local slot_name=$(generate_container_name "$PROJECT_DIR" "$slot_num")
                        local slot_dir="$PROJECT_PARENT_DIR/$slot_name"

                        # Check if this slot is authenticated
                        if [[ -f "$slot_dir/.claude/.credentials.json" ]]; then
                            if [[ "$VERBOSE" == "true" ]]; then
                                echo "[DEBUG] Sending activate command to authenticated slot $slot_num (pane $pane_id)" >&2
                            fi
                            tmux send-keys -t "$pane_id" C-c  # Clear any partial input first
                            sleep 0.1
                            tmux send-keys -t "$pane_id" "/cbox:tmux:activate $pane_id"
                            sleep 0.1
                            tmux send-keys -t "$pane_id" Enter
                        else
                            if [[ "$VERBOSE" == "true" ]]; then
                                echo "[DEBUG] Skipping unauthenticated slot $slot_num (pane $pane_id)" >&2
                            fi
                        fi
                    done

                    # Attach to the session
                    tmux attach-session -t "$session_name"


                    exit 0
                else
                    # Complex layout - multiple windows/panes
                    local session_name="claudebox-$(basename "$PROJECT_DIR")"
                    local captured_panes=()
                    local slot_index=0
                    local first_created=false

                    # Create panes one by one, capturing IDs atomically
                    for panes in "${window_panes[@]}"; do
                        for ((i=0; i<panes; i++)); do
                            if [[ $slot_index -ge ${#available_slots[@]} ]]; then
                                error "Not enough available slots for layout"
                            fi

                            local slot="${available_slots[$slot_index]}"

                            if [[ "$first_created" == "false" ]]; then
                                # Create the session with first pane
                                tmux new-session -s "$session_name" -d "env CLAUDEBOX_SLOT_NUMBER=$slot $SCRIPT_PATH slot $slot"
                                tmux rename-window -t "$session_name" 'ClaudeBox Multi'

                                # Get the first pane ID (session creation always creates exactly one pane)
                                local first_pane_id=$(tmux display -t "$session_name:0.0" -p '#{pane_id}')
                                captured_panes+=("$first_pane_id")

                                if [[ "$VERBOSE" == "true" ]]; then
                                    echo "[DEBUG] Created first pane: $first_pane_id" >&2
                                fi

                                first_created=true
                            else
                                # Split and create new pane - capture ID atomically with -P -F
                                local new_pane_id=$(tmux split-window -t "$session_name" -e "CLAUDEBOX_SLOT_NUMBER=$slot" -P -F '#{pane_id}' "$SCRIPT_PATH slot $slot")

                                captured_panes+=("$new_pane_id")
                                if [[ "$VERBOSE" == "true" ]]; then
                                    echo "[DEBUG] Created pane $((${#captured_panes[@]})): $new_pane_id" >&2
                                fi
                            fi

                            ((slot_index++)) || true
                        done
                    done

                    # Enable pane border status
                    tmux set-option -t "$session_name" -g pane-border-status top

                    # Add tiled layout if more than 2 panes
                    if [[ ${#captured_panes[@]} -gt 2 ]]; then
                        tmux select-layout -t "$session_name" tiled
                    fi

                    # Wait for containers to start
                    sleep 2

                    # Wait for all slots to have running containers (like slots command does)
                    local all_ready=false
                    local wait_count=0
                    while [[ "$all_ready" == "false" ]] && [[ $wait_count -lt 30 ]]; do
                        all_ready=true
                        for ((idx=0; idx<$slot_index; idx++)); do
                            local slot="${available_slots[$idx]}"
                            local slot_name=$(generate_container_name "$PROJECT_DIR" "$slot")

                            # Check if container is running - exactly like slots command
                            if ! docker ps --format "{{.Names}}" | grep -q "^claudebox-.*-${slot_name}$"; then
                                all_ready=false
                                break
                            fi
                        done

                        if [[ "$all_ready" == "false" ]]; then
                            sleep 0.5
                            ((wait_count++)) || true
                        fi
                    done

                    # Additional wait to ensure Claude is fully started inside containers
                    sleep 6

                    # Send activate command only to authenticated slots
                    if [[ "$VERBOSE" == "true" ]]; then
                        echo "[DEBUG] Checking authentication for ${#captured_panes[@]} panes" >&2
                    fi

                    for ((i=0; i<${#captured_panes[@]}; i++)); do
                        local pane_id="${captured_panes[$i]}"
                        local slot_num="${available_slots[$i]}"
                        local slot_name=$(generate_container_name "$PROJECT_DIR" "$slot_num")
                        local slot_dir="$PROJECT_PARENT_DIR/$slot_name"

                        # Check if this slot is authenticated
                        if [[ -f "$slot_dir/.claude/.credentials.json" ]]; then
                            if [[ "$VERBOSE" == "true" ]]; then
                                echo "[DEBUG] Sending activate command to authenticated slot $slot_num (pane $pane_id)" >&2
                            fi
                            tmux send-keys -t "$pane_id" C-c  # Clear any partial input first
                            sleep 0.1
                            tmux send-keys -t "$pane_id" "/cbox:tmux:activate $pane_id"
                            sleep 0.1
                            tmux send-keys -t "$pane_id" Enter
                        else
                            if [[ "$VERBOSE" == "true" ]]; then
                                echo "[DEBUG] Skipping unauthenticated slot $slot_num (pane $pane_id)" >&2
                            fi
                        fi
                    done

                    # Attach to the session
                    tmux attach-session -t "$session_name"

                    exit 0
                fi
        else
            # No layout - just run normally
            exec tmux new-session "$SCRIPT_PATH" "$@"
        fi
    fi

    exit 0
}

_cmd_project() {
    local search="${1:-}"
    shift || true

    if [[ -z "$search" ]]; then
        error "Usage: claudebox project <project-name> [command...]\nExample: claudebox project myproject\nExample: claudebox project cc618e36 shell"
    fi

    # Convert search to lowercase for case-insensitive matching
    local search_lower=$(echo "$search" | tr '[:upper:]' '[:lower:]')
    local matches=()

    # Search through all project directories
    for parent_dir in "$HOME/.claudebox/projects"/*/ ; do
        [[ -d "$parent_dir" ]] || continue

        local dir_name=$(basename "$parent_dir")
        local dir_lower=$(echo "$dir_name" | tr '[:upper:]' '[:lower:]')

        # Check if search matches directory name (partial match)
        if [[ "$dir_lower" == *"$search_lower"* ]]; then
            # Read the actual project path
            if [[ -f "$parent_dir/.project_path" ]]; then
                local project_path=$(cat "$parent_dir/.project_path")
                matches+=("$project_path|$dir_name")
            fi
        fi
    done

    # Handle results
    if [ ${#matches[@]} -eq 0 ]; then
        error "No projects found matching '$search'"
    elif [ ${#matches[@]} -eq 1 ]; then
        # Single match - use it
        local project_path="${matches[0]%%|*}"
        local project_name="${matches[0]##*|}"

        #info "Opening project: $project_name"
        #info "Path: $project_path"
        #echo

        # Just run claudebox with PROJECT_DIR set to the target project
        # No need to change directories at all!
        if [[ $# -eq 0 ]]; then
            # No arguments - run interactive claude
            # Force stdin to be considered a terminal to prevent -p flag
            PROJECT_DIR="$project_path" exec "$SCRIPT_PATH" < /dev/tty
        else
            # Pass through arguments
            PROJECT_DIR="$project_path" exec "$SCRIPT_PATH" "$@" < /dev/tty
        fi
    else
        # Multiple matches - show them
        error "Multiple projects match '$search':"
        for match in "${matches[@]}"; do
            local path="${match%%|*}"
            local name="${match##*|}"
            echo "  $name -> $path"
        done
        echo
        echo "Please be more specific."
    fi
}

# Special command handler for commands that need container modification
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

_cmd_import() {
    local host_commands="$CLAUDEBOX_GLOBAL_CLAUDE_COMMANDS_DIR"
    local parent_dir=$(get_parent_dir "$PROJECT_DIR")
    local project_commands="$parent_dir/commands"

    # Check if host commands directory exists
    if [[ ! -d "$host_commands" ]]; then
        warn "No commands found at $host_commands"
        info "Create markdown files in ~/.claudebox/.claude/commands to use with Claude"
        return 1
    fi

    # List available commands
    local commands=()
    while IFS= read -r -d '' file; do
        commands+=("$(basename "$file")")
    done < <(find "$host_commands" -maxdepth 1 -name "*.md" -type f -print0 | sort -z)

    if [[ ${#commands[@]} -eq 0 ]]; then
        warn "No markdown command files found in $host_commands"
        return 1
    fi

    # Show available commands
    cecho "Available commands to import:" "$CYAN"
    echo
    local i=1
    for cmd in "${commands[@]}"; do
        printf "  %2d. %s\n" "$i" "$cmd"
        ((i++)) || true
    done
    echo
    printf "  %2s. %s\n" "a" "Import all commands"
    echo

    # Get user selection
    read -p "Select command(s) to import (number, 'a' for all, or 'q' to quit): " selection

    case "$selection" in
        q|Q)
            info "Import cancelled"
            return 0
            ;;
        a|A|all|ALL)
            # Import all commands
            local imported=0
            for cmd in "${commands[@]}"; do
                if cp "$host_commands/$cmd" "$project_commands/"; then
                    ((imported++)) || true
                fi
            done
            success "✓ Imported $imported command(s) to project"
            ;;
        [0-9]*)
            # Import specific command
            if [[ $selection -ge 1 && $selection -le ${#commands[@]} ]]; then
                local cmd="${commands[$((selection-1))]}"
                if cp "$host_commands/$cmd" "$project_commands/"; then
                    success "✓ Imported $cmd to project"
                else
                    error "Failed to import $cmd"
                fi
            else
                error "Invalid selection: $selection"
            fi
            ;;
        *)
            error "Invalid selection: $selection"
            ;;
    esac

    # Show current project commands
    echo
    info "Current project commands:"
    ls -la "$project_commands"
}

_install_tmux_conf() {
    local tmux_conf_template="${SCRIPT_DIR}/templates/tmux.conf"
    local user_tmux_conf="$HOME/.tmux.conf"

    # Check if template exists
    if [[ ! -f "$tmux_conf_template" ]]; then
        error "tmux configuration template not found at: $tmux_conf_template"
    fi

    # Check if tmux is installed
    if ! command -v tmux >/dev/null 2>&1; then
        warn "tmux is not installed on your system."
        echo "Please install tmux first:"
        echo "  Ubuntu/Debian: sudo apt-get install tmux"
        echo "  macOS: brew install tmux"
        echo "  RHEL/CentOS: sudo yum install tmux"
        echo
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Installation cancelled"
            return 0
        fi
    fi

    # Backup existing config if it exists
    if [[ -f "$user_tmux_conf" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="$user_tmux_conf.backup_$timestamp"

        info "Backing up existing tmux configuration..."
        if cp "$user_tmux_conf" "$backup_file"; then
            success "Backed up to: $backup_file"
        else
            error "Failed to backup existing configuration"
        fi
    fi

    # Install new configuration
    info "Installing ClaudeBox tmux configuration..."
    if cp "$tmux_conf_template" "$user_tmux_conf"; then
        success "✓ Installed tmux configuration to: $user_tmux_conf"
        echo
        cecho "Features enabled:" "$GREEN"
        echo "  • Vi-style navigation (hjkl)"
        echo "  • Quick pane layouts (Ctrl+Alt+1/2/3/4)"
        echo "  • Fast pane switching (Ctrl+Alt+Arrows)"
        echo "  • Zoom toggle (Ctrl+Alt+0)"
        echo "  • Session persistence with tmux-resurrect"
        echo "  • System clipboard integration"
        echo

        # Check if TPM is installed
        if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
            cecho "Note: Tmux Plugin Manager (TPM) not found." "$YELLOW"
            echo "To install TPM and enable all features:"
            echo
            echo "  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm"
            echo
            echo "Then inside tmux, press: Prefix + I (Ctrl-a then Shift-i)"
        else
            cecho "TPM detected. Press Prefix + I inside tmux to install/update plugins." "$GREEN"
        fi

        # Reload tmux if running
        if [[ -n "${TMUX:-}" ]]; then
            echo
            info "Reloading tmux configuration..."
            tmux source-file "$user_tmux_conf" && success "✓ Configuration reloaded"
        fi
    else
        error "Failed to install tmux configuration"
    fi
}

export -f _cmd_save _cmd_unlink _cmd_rebuild _cmd_tmux _cmd_project _cmd_special _cmd_import _install_tmux_conf _cmd_kill