#!/usr/bin/env bash
# Resume Command - Interactive cross-slot session picker
# ============================================================================
# Commands: resume
# - resume: Pick and resume a session from any slot via fzf

# Cache platform once at source time
_RESUME_PLATFORM="$(uname -s)"

# ============================================================================
# Cross-platform helpers
# ============================================================================

_resume_get_mtime() {
    case "$_RESUME_PLATFORM" in
        Darwin) stat -f %m "$1" 2>/dev/null || printf '0' ;;
        *)      stat -c %Y "$1" 2>/dev/null || printf '0' ;;
    esac
}

_resume_get_size() {
    case "$_RESUME_PLATFORM" in
        Darwin) stat -f %z "$1" 2>/dev/null || printf '0' ;;
        *)      stat -c %s "$1" 2>/dev/null || printf '0' ;;
    esac
}

_resume_format_date() {
    case "$_RESUME_PLATFORM" in
        Darwin) date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || printf 'unknown' ;;
        *)      date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || printf 'unknown' ;;
    esac
}

_resume_human_size() {
    local bytes="$1"
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec "$bytes" 2>/dev/null || printf '%sB' "$bytes"
    else
        awk "BEGIN { s=$bytes; u=\"B\";
            if(s>=1024){s/=1024;u=\"K\"} if(s>=1024){s/=1024;u=\"M\"} if(s>=1024){s/=1024;u=\"G\"}
            printf \"%.1f%s\",s,u }"
    fi
}

# ============================================================================
# Container / session status helpers
# ============================================================================

_resume_is_container_running() {
    local slot_hash="$1" ps_file="$2"
    grep -q "^claudebox-.*-${slot_hash}$" "$ps_file" 2>/dev/null
}

_resume_get_container_name() {
    local slot_hash="$1" ps_file="$2"
    grep "^claudebox-.*-${slot_hash}$" "$ps_file" 2>/dev/null | head -1
}

_resume_is_session_active() {
    local slot_dir="$1" session_id="$2" slot_hash="$3" ps_file="$4"
    local sessions_dir="$slot_dir/.claude/sessions"
    local container_name

    if [ ! -d "$sessions_dir" ]; then
        return 1
    fi

    container_name=$(_resume_get_container_name "$slot_hash" "$ps_file")
    if [ -z "$container_name" ]; then
        return 1
    fi

    for pid_file in "$sessions_dir"/*.json; do
        if [ ! -f "$pid_file" ]; then
            continue
        fi
        local file_sid file_pid
        file_sid=$(jq -r '.sessionId // empty' "$pid_file" 2>/dev/null)
        if [ "$file_sid" = "$session_id" ]; then
            file_pid=$(jq -r '.pid // empty' "$pid_file" 2>/dev/null)
            if [ -n "$file_pid" ]; then
                if docker exec "$container_name" kill -0 "$file_pid" 2>/dev/null; then
                    return 0
                fi
            fi
        fi
    done
    return 1
}

_resume_read_counter() {
    local parent_dir="$1"
    local counter_file="$parent_dir/.project_container_counter"
    local max=1
    if [ -f "$counter_file" ]; then
        max=$(cat "$counter_file" 2>/dev/null | tr -dc '0-9')
        if [ -z "$max" ]; then
            max=1
        fi
    fi
    printf '%s' "$max"
}

# ============================================================================
# Phase 1: Collect session descriptions from history.jsonl
# ============================================================================

_resume_build_descriptions() {
    local projects_dir="$1" desc_file="$2" debug="$3"

    local parent_dir
    for parent_dir in "$projects_dir"/*/; do
        if [ ! -d "$parent_dir" ]; then
            continue
        fi
        local slot_dir
        for slot_dir in "$parent_dir"/*/; do
            if [ ! -d "$slot_dir" ]; then
                continue
            fi
            local hfile="$slot_dir/.claude/history.jsonl"
            if [ ! -f "$hfile" ]; then
                continue
            fi
            if [ "$debug" = "true" ]; then
                printf '[debug] reading history: %s\n' "$hfile" >&2
            fi
            jq -r 'select(.sessionId != null and .display != null and (.display | startswith("/") | not))
                    | [.sessionId, .display[:80]] | @tsv' "$hfile" 2>/dev/null \
                >> "$desc_file" || true
        done
    done
    # Deduplicate — keep first occurrence per session
    if [ -s "$desc_file" ]; then
        local tmp="${desc_file}.dedup"
        awk -F'\t' '!seen[$1]++' "$desc_file" > "$tmp"
        mv "$tmp" "$desc_file"
    fi
}

# ============================================================================
# Phase 2: Discover sessions across project slots
# ============================================================================

# Scan a single slot directory for session .jsonl files
_resume_scan_workspace() {
    local slot_dir="$1" slot_id="$2" slot_idx="$3" project_path="$4" project_name="$5"
    local running="$6" docker_ps_file="$7" sessions_file="$8" titles_file="$9"
    local ws_dir="$slot_dir/.claude/projects/-workspace"

    local f
    for f in "$ws_dir"/*.jsonl; do
        if [ ! -f "$f" ]; then
            continue
        fi
        case "$f" in */subagents/*) continue ;; esac

        local sid mtime size
        sid=$(basename "$f" .jsonl)
        mtime=$(_resume_get_mtime "$f")
        size=$(_resume_get_size "$f")

        if [ "$size" -lt 5000 ] 2>/dev/null; then
            continue
        fi

        # Extract custom title
        local title
        title=$(jq -r 'select(.type == "custom-title") | .customTitle' "$f" 2>/dev/null | tail -1)
        if [ -n "$title" ]; then
            printf '%s\t%s\n' "$sid" "$title" >> "$titles_file"
        fi

        local active="false"
        if [ "$running" = "true" ]; then
            if _resume_is_session_active "$slot_dir" "$sid" "$slot_id" "$docker_ps_file"; then
                active="true"
            fi
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$mtime" "$sid" "$slot_id" "$slot_idx" "$project_path" "$project_name" "$size" "$running" "$active" \
            >> "$sessions_file"
    done
}

_resume_discover_sessions() {
    local projects_dir="$1" all_projects="$2" debug="$3"
    local sessions_file="$4" titles_file="$5" docker_ps_file="$6"

    local current_parent_name=""
    if [ "$all_projects" != "true" ]; then
        current_parent_name=$(generate_parent_folder_name "$PROJECT_DIR")
        if [ "$debug" = "true" ]; then
            printf '[debug] filtering to project: %s -> %s\n' "$PROJECT_DIR" "$current_parent_name" >&2
        fi
    fi

    local parent_dir
    for parent_dir in "$projects_dir"/*/; do
        if [ ! -d "$parent_dir" ]; then
            continue
        fi

        # Filter to current project unless -A
        if [ "$all_projects" != "true" ]; then
            local this_parent
            this_parent=$(basename "$parent_dir")
            if [ "$this_parent" != "$current_parent_name" ]; then
                continue
            fi
        fi

        local project_path_file="$parent_dir/.project_path"
        if [ ! -f "$project_path_file" ]; then
            continue
        fi
        local project_path
        read -r project_path < "$project_path_file" || true

        local max
        max=$(_resume_read_counter "$parent_dir")

        local project_name
        project_name=$(basename "$project_path")

        if [ "$debug" = "true" ]; then
            printf '[debug] project: %s  path: %s  max_slots: %s\n' "$project_name" "$project_path" "$max" >&2
        fi

        # Enumerate slots via CRC32 chain
        local idx
        for ((idx=1; idx<=max; idx++)); do
            local slot_hash
            slot_hash=$(generate_container_name "$project_path" "$idx")
            local slot_dir="$parent_dir/$slot_hash"
            local ws_dir="$slot_dir/.claude/projects/-workspace"

            if [ "$debug" = "true" ]; then
                printf '[debug]   slot #%s -> hash %s  exists=%s\n' \
                    "$idx" "$slot_hash" \
                    "$([ -d "$slot_dir" ] && printf 'yes' || printf 'no')" >&2
            fi

            if [ ! -d "$ws_dir" ]; then
                continue
            fi

            local running="false"
            if _resume_is_container_running "$slot_hash" "$docker_ps_file"; then
                running="true"
            fi

            _resume_scan_workspace "$slot_dir" "$slot_hash" "$idx" \
                "$project_path" "$project_name" "$running" \
                "$docker_ps_file" "$sessions_file" "$titles_file"
        done

        # Fallback: scan slot dirs not matched by CRC32 chain
        local slot_dir
        for slot_dir in "$parent_dir"/*/; do
            if [ ! -d "$slot_dir" ]; then
                continue
            fi
            local dir_name
            dir_name=$(basename "$slot_dir")
            case "$dir_name" in
                commands|allowlist|*.ini|*.sh|*.md) continue ;;
            esac
            if grep -qF "	${dir_name}	" "$sessions_file" 2>/dev/null; then
                continue
            fi

            local ws_dir="$slot_dir/.claude/projects/-workspace"
            if [ ! -d "$ws_dir" ]; then
                continue
            fi

            if [ "$debug" = "true" ]; then
                printf '[debug]   unmatched slot dir: %s\n' "$dir_name" >&2
            fi

            local found_idx="?"
            for ((idx=1; idx<=max; idx++)); do
                local check_hash
                check_hash=$(generate_container_name "$project_path" "$idx")
                if [ "$check_hash" = "$dir_name" ]; then
                    found_idx="$idx"
                    break
                fi
            done

            local running="false"
            if _resume_is_container_running "$dir_name" "$docker_ps_file"; then
                running="true"
            fi

            _resume_scan_workspace "$slot_dir" "$dir_name" "$found_idx" \
                "$project_path" "$project_name" "$running" \
                "$docker_ps_file" "$sessions_file" "$titles_file"
        done
    done
}

# ============================================================================
# Phase 3: Build fzf input from discovered sessions
# ============================================================================

_resume_build_fzf_input() {
    local sessions_file="$1" titles_file="$2" desc_file="$3"
    local fzf_file="$4" tmpdir="$5" limit="$6" show_all="$7"

    # Colors (local to avoid leaking)
    local c_reset c_yellow c_cyan c_dim c_red
    c_reset=$'\033[0m'
    c_yellow=$'\033[33m'
    c_cyan=$'\033[36m'
    c_dim=$'\033[2m'
    c_red=$'\033[31m'

    # Sort by mtime desc, dedup by session_id
    sort -t$'\t' -k1,1rn "$sessions_file" | awk -F'\t' '!seen[$2]++' > "$tmpdir/sorted.tsv"

    # Apply limit
    if [ "$show_all" = "true" ]; then
        cp "$tmpdir/sorted.tsv" "$tmpdir/limited.tsv"
    else
        head -n "$limit" "$tmpdir/sorted.tsv" > "$tmpdir/limited.tsv"
    fi

    if [ ! -s "$tmpdir/limited.tsv" ]; then
        return 1
    fi

    while IFS=$'\t' read -r mtime sid slot_hash slot_idx project_path project_name size running active; do
        if [ -z "$sid" ]; then
            continue
        fi

        local date_str size_h title desc display status status_display
        date_str=$(_resume_format_date "$mtime")
        size_h=$(_resume_human_size "$size")
        title=$(grep -F "${sid}	" "$titles_file" 2>/dev/null | head -1 | cut -f2- || true)
        desc=$(grep -F "${sid}	" "$desc_file" 2>/dev/null | head -1 | cut -f2- || true)

        if [ -n "$title" ]; then
            display="${c_cyan}${title}${c_reset}"
            if [ -n "$desc" ]; then
                display="${display}  ${c_dim}${desc}${c_reset}"
            fi
        elif [ -n "$desc" ]; then
            display="$desc"
        else
            display="${c_dim}(no description)${c_reset}"
        fi

        if [ "$active" = "true" ]; then
            status="ACTIVE"
            status_display="${c_red}ACTIVE${c_reset}"
        elif [ "$running" = "true" ]; then
            status="RUNNING"
            status_display="${c_yellow}busy${c_reset}  "
        else
            status="IDLE"
            status_display="${c_dim}idle${c_reset}  "
        fi

        printf '%s  %6s  %b  %-12s  #%-3s  %b\t%s\t%s\t%s\t%s\t%s\n' \
            "$date_str" "$size_h" "$status_display" "$project_name" "$slot_idx" "$display" \
            "$sid" "$slot_hash" "$slot_idx" "$project_path" "$status" \
            >> "$fzf_file"
    done < "$tmpdir/limited.tsv"

    [ -s "$fzf_file" ]
}

# ============================================================================
# Phase 4: Resume the selected session
# ============================================================================

_resume_execute() {
    local sid="$1" slot_hash="$2" slot_idx="$3" project_path="$4" status="$5"
    local projects_dir="$6" docker_ps_file="$7"

    local c_reset c_green c_yellow c_bold c_red
    c_reset=$'\033[0m'
    c_green=$'\033[32m'
    c_yellow=$'\033[33m'
    c_bold=$'\033[1m'
    c_red=$'\033[31m'

    case "$status" in
        ACTIVE)
            printf '%s%sThis session is currently active in slot #%s%s\n' "$c_bold" "$c_red" "$slot_idx" "$c_reset" >&2
            printf 'Cannot resume an active session. Use the running container directly.\n' >&2
            return 1
            ;;

        RUNNING)
            printf '%sSlot #%s is busy — finding an idle slot...%s\n' "$c_yellow" "$slot_idx" "$c_reset" >&2

            local resume_parent_dir="$projects_dir/$(generate_parent_folder_name "$project_path")"
            local source_jsonl="$resume_parent_dir/$slot_hash/.claude/projects/-workspace/${sid}.jsonl"

            if [ ! -f "$source_jsonl" ]; then
                printf 'Error: session file not found: %s\n' "$source_jsonl" >&2
                return 1
            fi

            # Find an idle slot
            local idle_hash="" idle_idx=""
            local resume_max
            resume_max=$(_resume_read_counter "$resume_parent_dir")
            local idx
            for ((idx=1; idx<=resume_max; idx++)); do
                local hash
                hash=$(generate_container_name "$project_path" "$idx")
                if [ "$hash" = "$slot_hash" ]; then
                    continue
                fi
                if [ ! -d "$resume_parent_dir/$hash" ]; then
                    continue
                fi
                if ! _resume_is_container_running "$hash" "$docker_ps_file"; then
                    idle_hash="$hash"
                    idle_idx="$idx"
                    break
                fi
            done

            if [ -z "$idle_hash" ]; then
                printf 'No idle slots available. Close a running session first.\n' >&2
                return 1
            fi

            local target_ws="$resume_parent_dir/$idle_hash/.claude/projects/-workspace"
            mkdir -p "$target_ws"
            cp "$source_jsonl" "$target_ws/"
            printf '%sCopied session to slot #%s (%s)%s\n' "$c_green" "$idle_idx" "$idle_hash" "$c_reset" >&2

            slot_idx="$idle_idx"
            ;;

        IDLE)
            # Slot is not running — start it with --resume
            ;;
    esac

    printf '%sResuming session in slot #%s...%s\n' "$c_green" "$slot_idx" "$c_reset" >&2

    cd "$project_path"
    local parent_folder_name
    parent_folder_name=$(generate_parent_folder_name "$project_path")
    local slot_name
    slot_name=$(generate_container_name "$project_path" "$slot_idx")
    local container_name="claudebox-${parent_folder_name}-${slot_name}"

    export PROJECT_DIR="$project_path"
    export PROJECT_SLOT_DIR="$projects_dir/$parent_folder_name/$slot_name"
    export PROJECT_PARENT_DIR="$projects_dir/$parent_folder_name"
    export IMAGE_NAME="claudebox-${parent_folder_name}"
    export CLAUDEBOX_SLOT_NUMBER="$slot_idx"

    run_claudebox_container "$container_name" "interactive" --resume "$sid"
}

# ============================================================================
# Main command entry point
# ============================================================================

_cmd_resume() {
    # ---- Parse arguments ----
    local limit=50
    local show_all=false
    local all_projects=false
    local debug=false

    while [ $# -gt 0 ]; do
        case "$1" in
            -n)
                if [ -z "${2:-}" ]; then
                    printf 'Error: -n requires a numeric argument\n' >&2
                    return 1
                fi
                if ! printf '%s' "$2" | grep -qE '^[0-9]+$'; then
                    printf 'Error: -n requires a numeric argument, got: %s\n' "$2" >&2
                    return 1
                fi
                limit="$2"; shift 2
                ;;
            -a) show_all=true; shift ;;
            -A|--all-projects) all_projects=true; shift ;;
            -d|--debug) debug=true; shift ;;
            -h|--help)
                printf 'Usage: claudebox resume [-n NUM] [-a] [-A] [-h]\n'
                printf '  -n NUM   Pick from last NUM sessions (default: 50)\n'
                printf '  -a       Show all sessions (no limit)\n'
                printf '  -A       Show sessions from all projects (default: current directory only)\n'
                printf '  -h       Show this help\n'
                return 0
                ;;
            *) shift ;;  # ignore unknown flags (e.g. control flags passed by claudebox)
        esac
    done

    # ---- Dependency checks ----
    local dep
    for dep in fzf jq docker; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            printf 'Error: %s is required but not found in PATH\n' "$dep" >&2
            return 1
        fi
    done

    local projects_dir="$HOME/.claudebox/projects"
    if [ ! -d "$projects_dir" ]; then
        printf 'No claudebox projects found at %s\n' "$projects_dir" >&2
        return 1
    fi

    if [ "$all_projects" != "true" ]; then
        if [ -z "${PROJECT_DIR:-}" ]; then
            printf 'Error: not in a claudebox project directory. Use -A to show all projects.\n' >&2
            return 1
        fi
    fi

    # ---- Temp files ----
    local tmpdir
    tmpdir=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" RETURN

    local sessions_file="$tmpdir/sessions.tsv"
    local desc_file="$tmpdir/desc.tsv"
    local titles_file="$tmpdir/titles.tsv"
    local docker_ps_file="$tmpdir/docker_ps.txt"
    local fzf_file="$tmpdir/fzf_input.tsv"

    touch "$titles_file" "$desc_file"
    docker ps --format '{{.Names}}' > "$docker_ps_file" 2>/dev/null || true

    printf 'Scanning sessions...\n' >&2

    # ---- Run phases ----
    _resume_build_descriptions "$projects_dir" "$desc_file" "$debug"

    _resume_discover_sessions "$projects_dir" "$all_projects" "$debug" \
        "$sessions_file" "$titles_file" "$docker_ps_file"

    if [ ! -s "$sessions_file" ]; then
        printf 'No sessions found.\n' >&2
        return 0
    fi

    if ! _resume_build_fzf_input "$sessions_file" "$titles_file" "$desc_file" \
            "$fzf_file" "$tmpdir" "$limit" "$show_all"; then
        printf 'No sessions found.\n' >&2
        return 0
    fi

    # ---- fzf picker ----
    local c_bold c_reset
    c_bold=$'\033[1m'
    c_reset=$'\033[0m'

    local header
    header=$(printf '%s  %6s  %-6s  %-12s  %-4s  %s' \
        "DATE            " "SIZE" "STATUS" "PROJECT" "SLOT" "DESCRIPTION")

    local selection
    selection=$(cat "$fzf_file" | fzf \
        --ansi \
        --header="${c_bold}${header}${c_reset}" \
        --no-multi \
        --layout=reverse \
        --no-sort \
        --delimiter=$'\t' \
        --with-nth=1 \
        --tabstop=4 \
        --bind='esc:abort' \
        --prompt='Resume session > ' \
    ) || return 0

    # ---- Extract selection and resume ----
    local sid slot_hash slot_idx project_path status
    sid=$(printf '%s' "$selection" | cut -f2)
    slot_hash=$(printf '%s' "$selection" | cut -f3)
    slot_idx=$(printf '%s' "$selection" | cut -f4)
    project_path=$(printf '%s' "$selection" | cut -f5)
    status=$(printf '%s' "$selection" | cut -f6)

    _resume_execute "$sid" "$slot_hash" "$slot_idx" "$project_path" "$status" \
        "$projects_dir" "$docker_ps_file"
}

export -f _cmd_resume
export -f _resume_get_mtime _resume_get_size _resume_format_date _resume_human_size
export -f _resume_is_container_running _resume_get_container_name _resume_is_session_active
export -f _resume_read_counter
export -f _resume_build_descriptions _resume_discover_sessions _resume_scan_workspace
export -f _resume_build_fzf_input _resume_execute
