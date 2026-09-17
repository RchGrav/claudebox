#!/usr/bin/env bash
# Slot Commands - Container slot management
# ============================================================================
# Commands: create, slots, slot, revoke
# Manages multiple container instances per project

_cmd_create() {
    # Debug: Check counter before creation
    local parent_dir
    parent_dir=$(get_parent_dir "$PROJECT_DIR")
    local counter_before
    counter_before=$(read_counter "$parent_dir")
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] Counter before creation: $counter_before" >&2
    fi
    
    # Create a new slot
    local slot_name
    slot_name=$(create_container "$PROJECT_DIR")
    local slot_dir="$parent_dir/$slot_name"
    
    # Debug: Check counter after creation
    local counter_after
    counter_after=$(read_counter "$parent_dir")
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] Counter after creation: $counter_after" >&2
        echo "[DEBUG] Created slot name: $slot_name" >&2
        echo "[DEBUG] Slot directory: $slot_dir" >&2
    fi
    
    # Show updated slots list directly
    list_project_slots "$PROJECT_DIR"
    
    return 0
}

_cmd_slots() {
    list_project_slots "$PROJECT_DIR"
    return 0
}

_cmd_slot() {
    # Extract slot number - it should be the first argument
    local slot_num="${1:-}"
    shift || true  # Remove slot number from arguments
    
    # Validate slot number
    if [[ -z "$slot_num" ]] || [[ ! "$slot_num" =~ ^[0-9]+$ ]] || (( 10#$slot_num < 1 )); then
        error "Usage: claudebox slot <number> [claude arguments...]"
        return 1
    fi
    
    # Get the slot directory
    local slot_dir
    slot_dir=$(get_slot_dir "$PROJECT_DIR" "$slot_num")
    local slot_name
    slot_name=$(basename "$slot_dir")
    
    # Check if slot exists
    if [[ ! -d "$slot_dir" ]]; then
        error "Slot $slot_num does not exist. Run 'claudebox slots' to see available slots."
        return 1
    fi
    
    # Set up environment for this specific slot
    local parent_dir
    parent_dir=$(get_parent_dir "$PROJECT_DIR")
    export PROJECT_SLOT_DIR="$slot_dir"
    export PROJECT_PARENT_DIR="$parent_dir"
    IMAGE_NAME=$(get_image_name)
    export IMAGE_NAME
    export CLAUDEBOX_SLOT_NUMBER="$slot_num"
    
    info "Using slot $slot_num: $slot_name"
    
    # Sync commands before launching container
    sync_commands_to_project "$parent_dir"
    
    # Now we need to run the container with the slot selected
    # Get parent folder name for container naming
    local parent_folder_name
    parent_folder_name=$(generate_parent_folder_name "$PROJECT_DIR")
    local container_name="claudebox-${parent_folder_name}-${slot_name}"

    if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        if [[ $# -gt 0 ]]; then
            error "Slot $slot_num is already running. Run 'claudebox slot $slot_num' to attach, or stop it first with 'claudebox kill $slot_name'."
            return 1
        fi
        if [[ ${CLAUDEBOX_CLIPBOARD:-false} == true ]]; then
            local container_env
            local bridge_url=""
            local bridge_token=""
            local env_line
            container_env=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container_name" 2>/dev/null || true)
            while IFS= read -r env_line; do
                case "$env_line" in
                    CLAUDEBOX_CLIPBOARD_URL=*) bridge_url="${env_line#CLAUDEBOX_CLIPBOARD_URL=}" ;;
                    CLAUDEBOX_CLIPBOARD_TOKEN=*) bridge_token="${env_line#CLAUDEBOX_CLIPBOARD_TOKEN=}" ;;
                esac
            done <<< "$container_env"
            if ! clipboard_bridge_probe "$bridge_url" "$bridge_token"; then
                error "Slot $slot_num is already running without live clipboard support. Stop it with 'claudebox kill $slot_name', then start it with 'claudebox --clipboard slot $slot_num'."
                return 1
            fi
        fi
        docker attach "$container_name"
        return $?
    fi
    
    # If we're in tmux, get the pane ID and pass it through
    local tmux_pane_id=""
    if [[ -n "${TMUX:-}" ]]; then
        tmux_pane_id=$(tmux display-message -p '#{pane_id}')
        export CLAUDEBOX_TMUX_PANE="$tmux_pane_id"
    fi
    
    # Run container with remaining arguments passed to claude
    run_claudebox_container "$container_name" "interactive" "$@"
}

_cmd_revoke() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] Starting _cmd_revoke with PROJECT_DIR=$PROJECT_DIR" >&2
    fi
    local parent
    parent=$(get_parent_dir "$PROJECT_DIR")
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] parent=$parent" >&2
    fi
    local max
    max=$(read_counter "$parent")
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] max=$max" >&2
    fi
    
    if [ "$max" -eq 0 ]; then
        echo "No slots to revoke"
        return 0
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] Checking argument: ${1:-}" >&2
    fi
    
    # Check for "all" argument
    if [ "${1:-}" = "all" ]; then
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Processing revoke all" >&2
        fi
        local removed_count=0
        local existing_count=0
        
        # First count how many slots actually exist
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Starting count loop, max=$max" >&2
        fi
        for ((idx=1; idx<=max; idx++)); do
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] Count loop idx=$idx" >&2
            fi
            local name
            name=$(generate_container_name "$PROJECT_DIR" "$idx")
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] Generated name=$name" >&2
            fi
            local dir="$parent/$name"
            if [ -d "$dir" ]; then
                ((existing_count++)) || true
            fi
        done
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Finished count loop, existing_count=$existing_count, max=$max" >&2
        fi
        
        # Now remove them
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Starting removal loop" >&2
        fi
        for ((idx=max; idx>=1; idx--)); do
            local name
            name=$(generate_container_name "$PROJECT_DIR" "$idx")
            local dir="$parent/$name"
            
            if [ -d "$dir" ]; then
                # Check if container is running
                if docker ps --format "{{.Names}}" | grep -q "^claudebox-.*-${name}$"; then
                    info "Slot $idx is in use, skipping"
                else
                    if [[ "$VERBOSE" == "true" ]]; then
                        echo "[DEBUG] Removing slot $idx: $dir" >&2
                    fi
                    if rm -rf "$dir"; then
                        ((removed_count++)) || true
                    else
                        error "Failed to remove slot $idx: $dir"
                    fi
                fi
            else
                if [[ "$VERBOSE" == "true" ]]; then
                    echo "[DEBUG] Slot $idx not found: $dir" >&2
                fi
            fi
        done
        
        # If we removed all existing slots, set counter to 0
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] removed_count=$removed_count, existing_count=$existing_count" >&2
        fi
        if [ $removed_count -eq $existing_count ]; then
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] Setting counter to 0" >&2
            fi
            write_counter "$parent" 0
        else
            # Otherwise prune the counter
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] Pruning counter" >&2
            fi
            prune_slot_counter "$PROJECT_DIR"
        fi
        
        # Show updated slots list
        list_project_slots "$PROJECT_DIR"
    else
        # Revoke highest slot only
        local name
        name=$(generate_container_name "$PROJECT_DIR" "$max")
        local dir="$parent/$name"
        
        if [ ! -d "$dir" ]; then
            # Slot doesn't exist, just prune the counter
            prune_slot_counter "$PROJECT_DIR"
            local new_max
            new_max=$(read_counter "$parent")
            info "Slot $max doesn't exist. Counter adjusted to $new_max"
        else
            # Check if container is running
            if docker ps --format "{{.Names}}" | grep -q "^claudebox-.*-${name}$"; then
                error "Cannot revoke slot $max - it is currently in use"
            fi
            
            # Remove the slot
            rm -rf "$dir"
            write_counter "$parent" $((max - 1))
        fi
        
        # Show updated slots list
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] About to call list_project_slots" >&2
        fi
        list_project_slots "$PROJECT_DIR"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] list_project_slots returned" >&2
        fi
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] Exiting _cmd_revoke" >&2
    fi
    return 0
}

_cmd_kill() {
    local target="${1:-}"
    
    # If no argument, show help
    if [[ -z "$target" ]]; then
        logo_small
        echo
        cecho "Kill running ClaudeBox containers:" "$CYAN"
        echo
        cecho "WARNING: This forcefully terminates containers!" "$YELLOW"
        echo
        
        # Show running containers with their slot hashes
        local found=false
        local parent
        parent=$(get_parent_dir "$PROJECT_DIR")
        local max
        max=$(read_counter "$parent")
        
        echo "Running containers in this project:"
        echo
        for ((idx=1; idx<=max; idx++)); do
            local name
            name=$(generate_container_name "$PROJECT_DIR" "$idx")
            local full_container
            full_container="claudebox-$(basename "$parent")-${name}"
            
            if docker ps --format "{{.Names}}" | grep -q "^${full_container}$"; then
                printf "  Slot %d: %s\n" "$idx" "$name"
                found=true
            fi
        done
        
        if [[ "$found" == "false" ]]; then
            info "No running containers found"
        else
            echo
            cecho "Usage:" "$YELLOW"
            echo "  claudebox kill <slot-hash>  # Kill specific container"
            echo "  claudebox kill all          # Kill all containers"
            echo
            cecho "Example:" "$DIM"
            echo "  claudebox kill 337503c6    # Kill container by slot hash"
            echo "  claudebox kill all          # Kill all running containers"
        fi
        echo
        return 0
    fi
    
    # Kill all containers
    if [[ "$target" == "all" ]]; then
        local parent
        parent=$(get_parent_dir "$PROJECT_DIR")
        local project_name
        project_name=$(basename "$parent")
        local containers
        containers=$(docker ps --format "{{.Names}}" | grep "^claudebox-${project_name}-" || true)
        
        if [[ -z "$containers" ]]; then
            info "No running containers to kill"
            echo
            return 0
        fi
        
        warn "Killing all containers for this project..."
        echo "$containers" | while IFS= read -r container; do
            echo "  Killing: $container"
            docker kill "$container" >/dev/null 2>&1 || true
        done
        success "All containers killed"
        echo
        return 0
    fi
    
    # Kill specific container by slot hash
    local parent
    parent=$(get_parent_dir "$PROJECT_DIR")
    local project_name
    project_name=$(basename "$parent")
    local full_container="claudebox-${project_name}-${target}"
    
    if docker ps --format "{{.Names}}" | grep -q "^${full_container}$"; then
        warn "Killing container: $full_container"
        docker kill "$full_container" >/dev/null 2>&1 || error "Failed to kill container"
        success "Container killed"
    else
        error "Container not found: $target"
        echo "Run 'claudebox kill' to see running containers"
    fi
    echo
}

export -f _cmd_create _cmd_slots _cmd_slot _cmd_revoke _cmd_kill
