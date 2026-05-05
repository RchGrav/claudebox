#!/usr/bin/env bash
# Unified CLI parser for ClaudeBox
# Implements the four-bucket architecture for clean, predictable CLI handling

# ============================================================================
# CLI PARSER - SINGLE SOURCE OF TRUTH
# ============================================================================

# Four flag buckets (Bash 3.2 compatible - no associative arrays)
readonly HOST_ONLY_FLAGS=(--verbose rebuild)
readonly CONTROL_FLAGS=(--enable-sudo --disable-firewall)
readonly SCRIPT_COMMANDS=(shell create slot slots revoke profiles projects profile info help -h --help add remove install allowlist clean save project tmux kill update import unlink undo redo config mcp migrate-installer)

# parse_cli_args - Central CLI parsing with four-bucket architecture
# Usage: parse_cli_args "$@"
# Sets global variables:
#   host_flags: Array of host-only flags (help, version, etc)
#   control_flags: Array of control flags (verbose, enable-sudo, etc)
#   script_command: Single command for ClaudeBox to execute
#   pass_through: Array of args to pass to Claude in container
# Note: Each argument goes into exactly ONE bucket - no duplication
parse_cli_args() {
    # Initialize bucket arrays
    host_flags=()
    control_flags=()
    script_command=""
    pass_through=()

    # Single parsing loop - each arg goes into exactly ONE bucket
    local found_script_command=false
    local arg=""

    for arg in "$@"; do
        if [[ " ${HOST_ONLY_FLAGS[*]} " == *" $arg "* ]]; then
            # Bucket 1: Host-only flags
            host_flags+=("$arg")
        elif [[ " ${CONTROL_FLAGS[*]} " == *" $arg "* ]]; then
            # Bucket 2: Control flags (pass to container)
            control_flags+=("$arg")
        elif [[ "$found_script_command" == "false" ]] && [[ " ${SCRIPT_COMMANDS[*]} " == *" $arg "* ]]; then
            # Bucket 3: Script commands (first one wins)
            script_command="$arg"
            found_script_command=true
        else
            # Bucket 4: Pass-through (everything else)
            pass_through+=("$arg")
        fi
    done

    # Export results for use by main script
    CLI_HOST_FLAGS=("${host_flags[@]+"${host_flags[@]}"}")
    CLI_CONTROL_FLAGS=("${control_flags[@]+"${control_flags[@]}"}")
    export CLI_SCRIPT_COMMAND="$script_command"
    CLI_PASS_THROUGH=("${pass_through[@]+"${pass_through[@]}"}")
}

# Process host-only flags and set environment variables
process_host_flags() {
    local flag=""
    for flag in "${CLI_HOST_FLAGS[@]+"${CLI_HOST_FLAGS[@]}"}"; do
        case "$flag" in
            --verbose)
                export VERBOSE=true
                ;;
            rebuild)
                export REBUILD=true
                ;;
            tmux)
                export CLAUDEBOX_WRAP_TMUX=true
                ;;
        esac
    done
}

_is_close_command_match() {
    local left="$1"
    local right="$2"
    local left_len=${#left}
    local right_len=${#right}
    local len_diff=$((left_len - right_len))
    local edits=0
    local left_index=0
    local right_index=0

    if [[ "$left" == "$right" ]]; then
        return 0
    fi

    if (( len_diff < 0 )); then
        len_diff=$(( -len_diff ))
    fi
    if (( len_diff > 1 )); then
        return 1
    fi

    while (( left_index < left_len && right_index < right_len )); do
        if [[ "${left:$left_index:1}" == "${right:$right_index:1}" ]]; then
            ((left_index++))
            ((right_index++))
            continue
        fi

        ((edits++))
        if (( edits > 1 )); then
            return 1
        fi

        if (( left_len == right_len )); then
            ((left_index++))
            ((right_index++))
        elif (( left_len > right_len )); then
            ((left_index++))
        else
            ((right_index++))
        fi
    done

    if (( left_index < left_len || right_index < right_len )); then
        ((edits++))
    fi

    (( edits <= 1 ))
}

get_script_command_suggestion() {
    local input="$1"
    local normalized_input=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
    local candidate=""
    local normalized_candidate=""

    if [[ -z "$normalized_input" ]] || [[ "$normalized_input" == -* ]]; then
        return 1
    fi

    for candidate in "${SCRIPT_COMMANDS[@]+"${SCRIPT_COMMANDS[@]}"}"; do
        case "$candidate" in
            -h|--help)
                continue
                ;;
        esac

        normalized_candidate=$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')
        if _is_close_command_match "$normalized_input" "$normalized_candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

# Get command requirements - returns one of:
# "none" - pure host command, no Docker or image needed
# "image" - needs image name but not Docker running
# "docker" - needs Docker running and will run container
get_command_requirements() {
    local cmd="${1:-}"
    local subcommand="${2:-}"

    case "$cmd" in
        # Pure host commands - no Docker or image needed
        profiles|projects|help|-h|--help|slots|create|revoke|clean|import|unlink|kill|undo|redo)
            echo "none"
            ;;
        # Commands that need image name but not Docker
        info|profile|add|remove|install|allowlist|save)
            echo "image"
            ;;
        # Commands that need Docker and will run containers
        shell|project|rebuild|update|config|mcp|migrate-installer|tmux|slot|"")
            echo "docker"
            ;;
        # Unknown commands are forwarded to Claude in container
        *)
            echo "docker"
            ;;
    esac
}

# Legacy function for compatibility
requires_docker_image() {
    local cmd="${1:-}"
    local req=$(get_command_requirements "$cmd")
    [[ "$req" == "docker" ]]
}

# Check if current command requires a slot
requires_slot() {
    local cmd="${1:-}"

    # Commands that need a slot
    case "$cmd" in
        shell|update|config|mcp|migrate-installer|create|slot|"")
            return 0  # true - needs slot
            ;;
        *)
            return 1  # false - doesn't need slot
            ;;
    esac
}

# Debug output for parsed arguments (only if VERBOSE=true)
debug_parsed_args() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "[DEBUG] CLI Parser Results:" >&2
        echo "[DEBUG]   Host flags: ${CLI_HOST_FLAGS[*]-}" >&2
        echo "[DEBUG]   Control flags: ${CLI_CONTROL_FLAGS[*]-}" >&2
        echo "[DEBUG]   Script command: ${CLI_SCRIPT_COMMAND}" >&2
        echo "[DEBUG]   Pass-through: ${CLI_PASS_THROUGH[*]-}" >&2
    fi
}

# Export all functions
export -f parse_cli_args process_host_flags _is_close_command_match get_script_command_suggestion get_command_requirements requires_docker_image requires_slot debug_parsed_args