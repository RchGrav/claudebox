#!/usr/bin/env bash
# Clean Commands - Cleanup operations
# ============================================================================
# Commands: clean
# Manages Docker and project cleanup

_cmd_clean() {
    case "${1:-}" in
        docker)
            # Check if any ClaudeBox resources exist
            local containers
            containers=$(docker ps -a --filter "label=claudebox.project" -q 2>/dev/null)
            local cb_containers
            cb_containers=$(docker ps -a --format "{{.Names}}" 2>/dev/null | grep "^claudebox-" || true)
            local images
            images=$(docker images --filter "reference=claudebox*" -q 2>/dev/null)
            local volumes
            volumes=$(docker volume ls -q --filter "name=claudebox" 2>/dev/null)
            
            if [[ -z "$containers" ]] && [[ -z "$cb_containers" ]] && [[ -z "$images" ]] && [[ -z "$volumes" ]]; then
                info "No ClaudeBox Docker resources found"
                echo
                exit 0
            fi
            
            # Remove all claudebox containers
            if [[ -n "$containers" ]]; then
                docker ps -a --filter "label=claudebox.project" -q | xargs -r docker rm -f 2>/dev/null || true
            fi
            if [[ -n "$cb_containers" ]]; then
                docker ps -a --format "{{.Names}}" | grep "^claudebox-" | xargs -r docker rm -f 2>/dev/null || true
            fi

            # Remove ALL claudebox images (including base)
            if [[ -n "$images" ]]; then
                docker images --filter "reference=claudebox-*" -q | xargs -r docker rmi -f 2>/dev/null || true
                docker images --filter "reference=claudebox" -q | xargs -r docker rmi -f 2>/dev/null || true
            fi

            # Remove dangling images
            docker images -f "dangling=true" -q | xargs -r docker rmi -f 2>/dev/null || true

            # Prune build cache
            docker builder prune -af 2>/dev/null || true

            # Remove volumes
            if [[ -n "$volumes" ]]; then
                docker volume ls -q --filter "name=claudebox" | xargs -r docker volume rm 2>/dev/null || true
            fi

            success "ClaudeBox Docker resources removed"
            echo
            exit 0
            ;;
        project)
            # Handle project cleaning with optional name parameter
            local search="${2:-}"
            
            if [[ -n "$search" ]]; then
                # Clean specific project by name (using same logic as project/open command)
                # Convert search to lowercase for case-insensitive matching
                local search_lower
                search_lower=$(echo "$search" | tr '[:upper:]' '[:lower:]')
                local matches=()
                
                # Search through all project directories
                for parent_dir in "$HOME/.claudebox/projects"/*/ ; do
                    [[ -d "$parent_dir" ]] || continue
                    
                    local dir_name
                    dir_name=$(basename "$parent_dir")
                    local dir_lower
                    dir_lower=$(echo "$dir_name" | tr '[:upper:]' '[:lower:]')
                    
                    # Check if search matches directory name (partial match)
                    if [[ "$dir_lower" == *"$search_lower"* ]]; then
                        # Read the actual project path
                        if [[ -f "$parent_dir/.project_path" ]]; then
                            local project_path
                            project_path=$(cat "$parent_dir/.project_path")
                            matches+=("$project_path|$dir_name")
                        fi
                    fi
                done
                
                # Handle results
                if [ ${#matches[@]} -eq 0 ]; then
                    error "No project found matching: $search"
                elif [ ${#matches[@]} -eq 1 ]; then
                    # Single match - clean it
                    local project_info="${matches[0]}"
                    local project_path="${project_info%|*}"
                    local project_name="${project_info#*|}"
                    _clean_project "$project_name" "$project_path"
                else
                    # Multiple matches - show menu
                    cecho "Multiple projects found matching '$search':" "$YELLOW"
                    echo
                    local i=1
                    for match in "${matches[@]}"; do
                        local path="${match%|*}"
                        local name="${match#*|}"
                        printf "  %d. %s (%s)\n" "$i" "$name" "$path"
                        ((i++))
                    done
                    echo
                    printf "Enter number (1-%d) or q to quit: " "${#matches[@]}"
                    read -r choice
                    
                    if [[ "$choice" == "q" ]] || [[ -z "$choice" ]]; then
                        exit 0
                    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#matches[@]}" ]; then
                        local selected="${matches[$((choice-1))]}"
                        local project_path="${selected%|*}"
                        local project_name="${selected#*|}"
                        _clean_project "$project_name" "$project_path"
                    else
                        error "Invalid selection"
                    fi
                fi
            else
                # Clean current project
                local project_name
                project_name=$(generate_parent_folder_name "$PROJECT_DIR")
                _clean_project "$project_name" "$PROJECT_DIR"
            fi
            exit 0
            ;;
        projects)
            # Clean all projects
            info "Cleaning all ClaudeBox projects..."
            echo
            
            local count=0
            for parent_dir in "$HOME/.claudebox/projects"/*/ ; do
                [[ -d "$parent_dir" ]] || continue
                
                local project_name
                project_name=$(basename "$parent_dir")
                local project_path=""
                
                if [[ -f "$parent_dir/.project_path" ]]; then
                    project_path=$(cat "$parent_dir/.project_path")
                fi
                
                _clean_project "$project_name" "$project_path"
                ((count++))
            done
            
            if [ $count -eq 0 ]; then
                info "No projects found to clean"
            else
                echo
                success "Cleaned $count projects"
            fi
            echo
            exit 0
            ;;
        *)
            logo_small
            echo
            cecho "ClaudeBox Clean Options:" "$CYAN"
            echo
            echo -e "  ${GREEN}clean docker${NC}             Remove all Docker resources"
            echo -e "  ${GREEN}clean project [name]${NC}     Clean current or named project"
            echo -e "  ${GREEN}clean projects${NC}           Clean all projects"
            echo
            cecho "Examples:" "$YELLOW"
            echo "  claudebox clean docker      # Remove all Docker resources"
            echo "  claudebox clean project     # Clean current project"
            echo "  claudebox clean project abc # Clean project 'abc'"
            echo "  claudebox clean projects    # Clean all projects"
            echo
            exit 0
            ;;
    esac
}

# Helper function to clean a specific project
_clean_project() {
    local project_name="$1"
    local project_path="${2:-unknown}"
    
    info "Cleaning project: $project_name ($project_path)"
    
    local parent_dir="$HOME/.claudebox/projects/$project_name"
    
    # Remove all slot directories
    local slots_removed=0
    for slot_dir in "$parent_dir"/*/ ; do
        if [[ -d "$slot_dir" ]] && [[ "$slot_dir" != "$parent_dir/" ]]; then
            local slot_name
            slot_name=$(basename "$slot_dir")
            # Skip profiles.ini and other project-level files
            if [[ "$slot_name" =~ ^[a-f0-9]{8}$ ]]; then
                rm -rf "$slot_dir"
                ((slots_removed++)) || true
            fi
        fi
    done
    
    # Remove containers for this project
    local containers
    containers=$(docker ps -a --format "{{.Names}}" 2>/dev/null | grep "^claudebox-${project_name}-" || true)
    if [[ -n "$containers" ]]; then
        echo "$containers" | xargs -r docker rm -f 2>/dev/null || true
    fi
    
    # Remove project image (but not core)
    local image_name="claudebox-${project_name}"
    if docker image inspect "$image_name" >/dev/null 2>&1; then
        docker rmi -f "$image_name" 2>/dev/null || true
    fi
    
    # Remove the entire project directory
    if [[ -d "$parent_dir" ]]; then
        rm -rf "$parent_dir"
        success "  Removed project directory and $slots_removed slots"
    else
        info "  No project directory found"
    fi
}

_cmd_undo() {
    local backups_dir="$HOME/.claudebox/backups"
    if [[ ! -d "$backups_dir" ]] || [[ -z "$(ls -A "$backups_dir" 2>/dev/null)" ]]; then
        error "No backups found"
    fi
    
    # Get oldest backup (smallest timestamp)
    local oldest
    oldest=$(for backup in "$backups_dir"/*; do printf '%s\n' "${backup##*/}"; done | sort -n | head -1)
    local installed_path
    installed_path=$(which claudebox 2>/dev/null || echo "/usr/local/bin/claudebox")
    
    info "Restoring oldest backup from $(date -d @"$oldest" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$oldest" '+%Y-%m-%d %H:%M:%S')"
    
    if [[ -w "$installed_path" ]] || [[ -w "$(dirname "$installed_path")" ]]; then
        cp "$backups_dir/$oldest" "$installed_path"
        chmod +x "$installed_path"
    else
        sudo cp "$backups_dir/$oldest" "$installed_path"
        sudo chmod +x "$installed_path"
    fi
    
    success "✓ Restored claudebox from backup"
    exit 0
}

_cmd_redo() {
    local backups_dir="$HOME/.claudebox/backups"
    if [[ ! -d "$backups_dir" ]] || [[ -z "$(ls -A "$backups_dir" 2>/dev/null)" ]]; then
        error "No backups found"
    fi
    
    # Get newest backup (largest timestamp)
    local newest
    newest=$(for backup in "$backups_dir"/*; do printf '%s\n' "${backup##*/}"; done | sort -n | tail -1)
    local installed_path
    installed_path=$(which claudebox 2>/dev/null || echo "/usr/local/bin/claudebox")
    
    info "Restoring newest backup from $(date -d @"$newest" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$newest" '+%Y-%m-%d %H:%M:%S')"
    
    if [[ -w "$installed_path" ]] || [[ -w "$(dirname "$installed_path")" ]]; then
        cp "$backups_dir/$newest" "$installed_path"
        chmod +x "$installed_path"
    else
        sudo cp "$backups_dir/$newest" "$installed_path"
        sudo chmod +x "$installed_path"
    fi
    
    success "✓ Restored claudebox from backup"
    exit 0
}

# Export functions
export -f _cmd_clean _clean_project _cmd_undo _cmd_redo