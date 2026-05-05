#!/usr/bin/env bash
# Info Commands - Information display
# ============================================================================
# Commands: info, projects, allowlist
# Shows system, project, and configuration information

_cmd_projects() {
    cecho "ClaudeBox Projects:" "$CYAN"
    echo
    printf "%10s  %s  %s\n" "Size" "🐳" "Path"
    printf "%10s  %s  %s\n" "----" "--" "----"

    if ! list_all_projects; then
        echo
        warn "No ClaudeBox projects found."
        echo
        cecho "Start a new project:" "$GREEN"
        echo "  cd /your/project/directory"
        echo "  claudebox"
    fi
    echo
    exit 0
}

_cmd_allowlist() {
    # Allowlist is stored in parent directory, not slot directory
    local allowlist_file="$PROJECT_PARENT_DIR/allowlist"

    cecho "🔒 ClaudeBox Firewall Allowlist" "$CYAN"
    echo
    cecho "Current Project: $PROJECT_DIR" "$WHITE"
    echo

    if [[ -f "$allowlist_file" ]]; then
        cecho "Allowlist file:" "$GREEN"
        echo "  $allowlist_file"
        echo
        cecho "Allowed domains:" "$CYAN"
        # Display allowlist contents
        while IFS= read -r line; do
            if [[ -n "$line" ]] && [[ ! "$line" =~ ^#.* ]]; then
                echo "  $line"
            fi
        done < "$allowlist_file"
        echo
    else
        cecho "Allowlist file:" "$YELLOW"
        echo "  Not yet created (will be created on first run)"
        echo "  Location: $allowlist_file"
    fi

    echo
    cecho "Default Allowed Domains:" "$CYAN"
    echo "  api.anthropic.com, console.anthropic.com, statsig.anthropic.com, sentry.io"
    echo
    cecho "To edit allowlist:" "$YELLOW"
    echo "  \$EDITOR $allowlist_file"
    echo
    cecho "Note:" "$WHITE"
    echo "  Changes take effect on next container start"
    echo "  Use --disable-firewall flag to bypass all restrictions"

    exit 0
}

_cmd_info() {
    # Compute project folder name early for paths
    local project_folder_name
    project_folder_name=$(get_project_folder_name "$PROJECT_DIR")
    IMAGE_NAME="claudebox-${project_folder_name}"
    PROJECT_SLOT_DIR="$HOME/.claudebox/projects/$project_folder_name"

    cecho "╔═══════════════════════════════════════════════════════════════════╗" "$CYAN"
    cecho "║                    ClaudeBox Information Panel                    ║" "$CYAN"
    cecho "╚═══════════════════════════════════════════════════════════════════╝" "$CYAN"
    echo

    # Current Project Info
    cecho "📁 Current Project" "$WHITE"
    echo "   Path:       $PROJECT_DIR"
    echo "   Project ID: $project_folder_name"
    echo "   Data Dir:   $PROJECT_SLOT_DIR"
    echo

    # ClaudeBox Installation
    cecho "📦 ClaudeBox Installation" "$WHITE"
    echo "   Script:  $SCRIPT_PATH"
    echo "   Symlink: $LINK_TARGET"
    echo

    # Saved CLI Flags
    cecho "🚀 Saved CLI Flags" "$WHITE"
    if [[ -f "$HOME/.claudebox/default-flags" ]]; then
        local saved_flags=()
        while IFS= read -r flag; do
            [[ -n "$flag" ]] && saved_flags+=("$flag")
        done < "$HOME/.claudebox/default-flags"
        if [[ ${#saved_flags[@]} -gt 0 ]]; then
            echo -e "   Flags: ${GREEN}${saved_flags[*]}${NC}"
        else
            echo -e "   ${YELLOW}No flags saved${NC}"
        fi
    else
        echo -e "   ${YELLOW}No saved flags${NC}"
    fi
    echo

    # Claude Commands
    cecho "📝 Claude Commands" "$WHITE"
    local cmd_count=0
    if [[ -d "$CLAUDEBOX_GLOBAL_CLAUDE_COMMANDS_DIR" ]]; then
        cmd_count=$(ls -1 "$CLAUDEBOX_GLOBAL_CLAUDE_COMMANDS_DIR"/*.md 2>/dev/null | wc -l)
    fi
    local project_cmd_count=0
    if [[ -e "$PROJECT_PARENT_DIR/commands" ]]; then
        project_cmd_count=$(ls -1 "$PROJECT_PARENT_DIR/commands"/*.md 2>/dev/null | wc -l)
    fi

    if [[ $cmd_count -gt 0 ]] || [[ $project_cmd_count -gt 0 ]]; then
        echo "   Host:    $cmd_count command(s)"
        if [[ $cmd_count -gt 0 ]] && [[ -d "$CLAUDEBOX_GLOBAL_CLAUDE_COMMANDS_DIR" ]]; then
            for cmd_file in "$CLAUDEBOX_GLOBAL_CLAUDE_COMMANDS_DIR"/*.md; do
                [[ -f "$cmd_file" ]] || continue
                echo "            - $(basename "$cmd_file" .md)"
            done
        fi
        echo "   Project: $project_cmd_count command(s) (shared)"
        if [[ $project_cmd_count -gt 0 ]] && [[ -e "$PROJECT_PARENT_DIR/commands" ]]; then
            for cmd_file in "$PROJECT_PARENT_DIR/commands"/*.md; do
                [[ -f "$cmd_file" ]] || continue
                echo "            - $(basename "$cmd_file" .md)"
            done
        fi
    else
        echo -e "   ${YELLOW}No custom commands found${NC}"
        echo -e "   Location: ~/.claudebox/.claude/commands/ (host), project/commands/ (shared)"
    fi
    echo

    # Project Profiles
    cecho "🛠️ Project Profiles & Packages" "$WHITE"
    local current_profile_file
    current_profile_file=$(get_profile_file_path)
    if [[ -f "$current_profile_file" ]]; then
        local current_profiles=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && current_profiles+=("$line")
        done < <(read_profile_section "$current_profile_file" "profiles")
        local current_packages=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && current_packages+=("$line")
        done < <(read_profile_section "$current_profile_file" "packages")

        if [[ ${#current_profiles[@]} -gt 0 ]]; then
            echo -e "   Installed:  ${GREEN}${current_profiles[*]}${NC}"
        else
            echo -e "   Installed:  ${YELLOW}None${NC}"
        fi

        if [[ ${#current_packages[@]} -gt 0 ]]; then
            echo "   Packages:   ${current_packages[*]}"
        fi
    else
        echo -e "   Status:     ${YELLOW}No profiles installed${NC}"
    fi

    echo -e "   Available:  ${CYAN}core${NC}, python, c, rust, go, flutter, javascript, java, ruby, php"
    echo -e "               database, devops, web, ml, security, embedded, networking"
    echo -e "   ${CYAN}Hint:${NC} Run 'claudebox profile' for profile help "
    echo

    cecho "🐳 Docker Status" "$WHITE"
    if [[ -n "${IMAGE_NAME:-}" ]] && docker image inspect "$IMAGE_NAME" &>/dev/null; then
        local image_info=$(docker images --filter "reference=$IMAGE_NAME" --format "{{.Size}}")
        echo -e "   Image:      ${GREEN}Ready${NC} ($IMAGE_NAME - $image_info)"

        local image_created=$(docker inspect "$IMAGE_NAME" --format '{{.Created}}' | cut -d'T' -f1)
        local layer_count=$(docker history "$IMAGE_NAME" --no-trunc --format "{{.CreatedBy}}" | wc -l)
        echo "   Created:    $image_created"
        echo "   Layers:     $layer_count"
    else
        echo -e "   Image:      ${YELLOW}Not built${NC}"
    fi

    local running_containers=$(docker ps --filter "ancestor=$IMAGE_NAME" -q 2>/dev/null)
    if [[ -n "$running_containers" ]]; then
        local container_count=$(echo "$running_containers" | wc -l)
        echo -e "   Containers: ${GREEN}$container_count running${NC}"

        for container_id in $running_containers; do
            local container_stats="$(docker stats --no-stream --format "{{.Container}}: {{.CPUPerc}} CPU, {{.MemUsage}}" "$container_id" 2>/dev/null || echo "")"
            if [[ -n "$container_stats" ]]; then
                echo "               - $container_stats"
            fi
        done
    else
        echo "   Containers: None running"
    fi
    echo

    # All Projects Summary
    cecho "📊 All Projects Summary" "$WHITE"
    local total_projects=$(ls -1d "$HOME/.claudebox/projects"/*/ 2>/dev/null | wc -l)
    echo "   Projects:   $total_projects total"

    local total_size=$(docker images --filter "reference=claudebox-*" --format "{{.Size}}" | awk '{
        size=$1; unit=$2;
        if (unit == "GB") size = size * 1024;
        else if (unit == "KB") size = size / 1024;
        total += size
    } END {
        if (total > 1024) printf "%.1fGB", total/1024;
        else printf "%.1fMB", total
    }')
    local image_count=$(docker images --filter "reference=claudebox-*" -q | wc -l)
    echo "   Images:     $image_count ClaudeBox images using $total_size"

    local docker_stats=$(docker system df --format "table {{.Type}}\t{{.Total}}\t{{.Active}}\t{{.Size}}\t{{.Reclaimable}}" 2>/dev/null | tail -n +2)
    if [[ -n "$docker_stats" ]]; then
        echo "   System:"
        while IFS=$'\t' read -r type total active size reclaim; do
            echo "               - $type: $total total, $active active ($size, $reclaim reclaimable)"
        done <<< "$docker_stats"
    fi
    echo

    exit 0
}

export -f _cmd_projects _cmd_allowlist _cmd_info