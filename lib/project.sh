#!/usr/bin/env bash
# Functions that map a working directory → a deterministic project slug.

# Cross-platform sha256sum function
# macOS uses shasum, Linux uses sha256sum
_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$@"
    else
        error "Neither sha256sum nor shasum found. Cannot compute hash."
    fi
}

get_project_folder_name() {
    local clean_name=$(echo "$1" | sed 's|^/||; s|[^a-zA-Z0-9]|_|g; s|_+|_|g; s|^_||; s|_$||' | tr '[:upper:]' '[:lower:]')
    local hash=$(echo -n "$1" | _sha256 | cut -c1-6)
    echo "${clean_name}_${hash}"
}

# For backwards compatibility with the scaffold pattern
_get_project_slug() {
    get_project_folder_name "$1"
}

get_image_name() { 
    local project_folder_name=$(get_project_folder_name "${PROJECT_DIR}")
    printf 'claudebox-%s' "${project_folder_name}"
}

get_project_by_path() {
    local search_path="$1"
    local abs_path=$(realpath "$search_path" 2>/dev/null || echo "$search_path")
    for project_dir in "$HOME/.claudebox/projects"/*/ ; do
        [[ -d "$project_dir" ]] || continue
        local config_file="$project_dir/config.ini"
        [[ -f "$config_file" ]] || continue
        local stored_path=$(read_config_value "$config_file" "project" "path")
        if [[ "$stored_path" == "$abs_path" ]]; then
            basename "$project_dir"
            return 0
        fi
    done
    return 1
}

list_all_projects() {
    local projects_found=0
    # shellcheck disable=SC2231 # We want pathname expansion even when no dirs
    for project_dir in "$HOME/.claudebox/projects"/*/ ; do
        [[ -d "$project_dir" ]] || continue
        projects_found=1
        local project_id=$(basename "$project_dir")
        local original_path="(unknown)"
        local image_status="❌"
        local image_size="-"
        local config_file="$project_dir/config.ini"
        if [[ -f "$config_file" ]]; then
            local path_value=$(read_config_value "$config_file" "project" "path")
            [[ -n "$path_value" ]] && original_path="$path_value"
        fi
        local image_name="claudebox-${project_id}"
        if docker image inspect "$image_name" &>/dev/null; then
            image_status="✅"
            image_size=$(docker images --filter "reference=$image_name" --format "{{.Size}}")
        fi
        printf "%10s  %s  %s\n" "$image_size" "$image_status" "$original_path"
    done
    [[ $projects_found -eq 0 ]] && return 1
    return 0
}

resolve_project_path() {
    local input_path="${1:-$PWD}"

    if [[ "$input_path" =~ _[a-f0-9]{6}$ ]] && [[ -d "$HOME/.claudebox/$input_path" ]]; then
        echo "$input_path"
        return 0
    fi

    local project_id=$(get_project_by_path "$input_path")
    if [[ -n "$project_id" ]]; then
        echo "$project_id"
        return 0
    fi

    return 1
}

export -f get_project_folder_name get_image_name _get_project_slug _sha256 get_project_by_path list_all_projects resolve_project_path