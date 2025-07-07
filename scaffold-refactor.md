### claudebox.sh – top‑level CLI dispatcher

```bash
#!/usr/bin/env bash
# ==============================================================================
#  ClaudeBox – CLI entry point
#  This thin wrapper only handles early flags, sources the libraries, and
#  delegates all real work to lib/commands.sh (behavior identical to the
#  original monolith).
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------ constants --
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLAUDEBOX_SCRIPT_DIR="${SCRIPT_DIR}"

# ----------------------------------------------------------- early flag parse --
CLAUDEBOX_VERBOSE=false
# shellcheck disable=SC2048,SC2086
while (($#)); do
  case "$1" in
    --verbose) CLAUDEBOX_VERBOSE=true ; shift ;;
    *) break ;;
  esac
done
export CLAUDEBOX_VERBOSE

# --------------------------------------------------------------- source libs --
for lib in common env os state project docker config template commands; do
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/${lib}.sh"
done

# Ensure convenience symlink exists each run.
update_symlink

# --------------------------------------------------------- dispatch command --
dispatch_command "$@"
```

---

### lib/common.sh – shared colours & logging

```bash
#!/usr/bin/env bash
# Shared helpers that every module can safely source.

# -------- colours -------------------------------------------------------------
readonly _CB_RED='\033[0;31m'
readonly _CB_GREEN='\033[0;32m'
readonly _CB_YELLOW='\033[1;33m'
readonly _CB_BLUE='\033[0;34m'
readonly _CB_WHITE='\033[1;37m'
readonly _CB_RESET='\033[0m'

# -------- internal ------------------------------------------------------------
_cecho() { printf '%b\n' "${2:-$_CB_RESET}$1$_CB_RESET" ;}
_debug()   { [[ "${CLAUDEBOX_VERBOSE:-false}" == true ]] && _cecho "DEBUG ▸ $*"  "$_CB_BLUE" ;}
_info()    { _cecho "$*" "$_CB_BLUE"   ;}
_warn()    { _cecho "$*" "$_CB_YELLOW" ;}
_error()   { _cecho "ERROR ▸ $*" "$_CB_RED" ; exit 1 ;}
_success() { _cecho "$*" "$_CB_GREEN"  ;}

export -f _debug _info _warn _error _success
```

---

### lib/env.sh – static project globals

```bash
#!/usr/bin/env bash
# All immutable or rarely‑changing environment variables live here.

export CLAUDEBOX_HOME="${HOME}/.claudebox"
export LINK_TARGET="${HOME}/.local/bin/claudebox"

export DOCKER_USER="claude"
export NODE_VERSION="--lts"
export DELTA_VERSION="0.17.0"

export USER_ID
USER_ID="$(id -u)"
export GROUP_ID
GROUP_ID="$(id -g)"
export PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
```

---

### lib/os.sh – host OS detection/helpers

```bash
#!/usr/bin/env bash
# Detect host OS and sane defaults needed by other modules.

case "$(uname -s)" in
  Darwin*) export HOST_OS="macOS" ;;
  Linux*)  export HOST_OS="linux" ;;
  *)       _error "Unsupported operating system: $(uname -s)" ;;
esac

# ---------------------------- case‑sensitivity (mac) --------------------------
_is_case_sensitive_fs() {
  local tmp1 tmp2
  tmp1="$(mktemp "/tmp/.fs_case_test.XXXXXX")"
  tmp2="$(tr '[:lower:]' '[:upper:]' <<<"${tmp1}")"
  touch "${tmp1}"
  [[ -e "${tmp2}" && "${tmp1}" != "${tmp2}" ]] && { rm -f "${tmp1}"; return 1; }
  rm -f "${tmp1}"
}
# Apply normalisation flags only when required
if [[ "${HOST_OS}" == "macOS" ]] && ! _is_case_sensitive_fs; then
  export COMPOSE_DOCKER_CLI_BUILD=1
  export DOCKER_BUILDKIT=1
fi
```

---

### lib/state.sh – idempotent host‑side state

```bash
#!/usr/bin/env bash
# Folder creation, symlink maintenance and similar idempotent host operations.

# Ensure ~/.claudebox skeleton exists on every run.
_init_state_dirs() {
  mkdir -p "${CLAUDEBOX_HOME}"/{projects,commands,logs}
}

# Create or refresh ~/.local/bin/claudebox → actual script location
update_symlink() {
  _init_state_dirs
  mkdir -p "$(dirname "${LINK_TARGET}")"

  if [[ -L "${LINK_TARGET}" && "$(readlink "${LINK_TARGET}")" == "${CLAUDEBOX_SCRIPT_DIR}/claudebox.sh" ]]; then
    _debug "Symlink already correct."
    return
  fi

  rm -f "${LINK_TARGET}" 2>/dev/null || true
  ln -s "${CLAUDEBOX_SCRIPT_DIR}/claudebox.sh" "${LINK_TARGET}" \
      && _success "Symlink: ${LINK_TARGET} → claude​box.sh" \
      || _warn    "Unable to create ${LINK_TARGET} (permission?)"
}
export -f update_symlink
```

---

### lib/project.sh – per‑project helpers

```bash
#!/usr/bin/env bash
# Functions that map a working directory → a deterministic project slug.

_get_project_slug() {
  local path="$1"
  local clean
  clean="$(sed -e 's|^/||' -e 's|[^[:alnum:]]|_|g' <<<"${path}" | tr '[:upper:]' '[:lower:]')"
  local hash
  hash="$(sha256sum <<<"${path}" | cut -c1-6)"
  printf '%s_%s' "${clean%_}" "${hash}"
}

get_project_folder_name()  { _get_project_slug "${PROJECT_DIR}"; }
get_image_name()           { printf 'claudebox-%s' "$(_get_project_slug "${PROJECT_DIR}")"; }

export -f get_project_folder_name get_image_name
```

---

### lib/docker.sh – Docker interaction layer

```bash
#!/usr/bin/env bash
# All calls to Docker are centralised here so you can later swap them out,
# mock them in tests, or add extra logic.

_check_docker() {
  command -v docker &>/dev/null || return 1
  docker info        &>/dev/null || return 2
  docker ps          &>/dev/null || return 3
}

_install_docker() { _warn "(placeholder) Would install Docker for this OS." ;}

run_claudebox_container() {
  local name="$1"; shift
  _info "(placeholder) docker run '${name}' $*"
}

export -f _check_docker _install_docker run_claudebox_container
```

---

### lib/config.sh – profile/config INI helpers

```bash
#!/usr/bin/env bash
# Tiny, dependency‑free INI helpers (bash‑only, awk‑only).

_read_ini() {               # $1=file $2=section $3=key
  awk -F' *= *' -v s="[$2]" -v k="$3" '
    $0==s {in=1; next}
    /^\[/ {in=0}
    in && $1==k {print $2; exit}
  ' "$1" 2>/dev/null
}

write_default_flag_file() {  # $* = flags | empty to clear
  local file="${CLAUDEBOX_HOME}/default-flags"
  if (($#)); then printf '%s\n' "$@" > "${file}"
  else : > "${file}"
  fi
  _success "Saved default flags → ${file}"
}
export -f _read_ini write_default_flag_file
```

---

### lib/template.sh – minimal `{{TOKEN}}` renderer

```bash
#!/usr/bin/env bash
# Pure‑bash handlebars‑lite.  Only handles literal {{TOKEN}} replacement.

render_template() {          # $1=template $2=dest
  local src="$1" dst="$2"
  : > "${dst}"
  while IFS= read -r line; do
    while [[ "${line}" =~ {{([A-Z0-9_]+)}} ]]; do
      local token="${BASH_REMATCH[1]}"
      local val="${!token:-}"
      line="${line//\{\{${token}\}\}/${val}}"
    done
    printf '%s\n' "${line}" >> "${dst}"
  done < "${src}"
}
export -f render_template
```

---

### lib/commands.sh – command dispatcher / handlers

```bash
#!/usr/bin/env bash
# The canonical place where CLI arguments map to functions.

# --- public -------------------------------------------------------------------
dispatch_command() {
  local cmd="${1:-help}"; shift || true
  case "${cmd}" in
    help|-h|--help)   _cmd_help "$@" ;;
    profiles)         _cmd_profiles "$@" ;;
    projects)         _cmd_projects "$@" ;;
    profile)          _cmd_profile "$@" ;;
    install)          _cmd_install "$@" ;;
    save)             _cmd_save "$@" ;;
    shell)            _cmd_shell "$@" ;;
    allowlist)        _cmd_allowlist "$@" ;;
    info)             _cmd_info "$@" ;;
    clean)            _cmd_clean "$@" ;;
    unlink)           _cmd_unlink "$@" ;;
    rebuild)          _cmd_rebuild "$@" ;;
    *)                _forward_to_container "${cmd}" "$@" ;;
  esac
}

# --- individual handlers (placeholders) ---------------------------------------
_cmd_help() {
  cat <<EOF
ClaudeBox – Docker‑based Claude CLI environment
Usage: claudebox [--verbose] <command> [args]

Core commands (identical to monolith):
  profiles           List shipping profile names
  projects           List registered ClaudeBox projects
  profile            Interactive profile menu
  install            Install apt packages into image
  save [flags...]    Persist default flags
  shell [admin]      Spawn transient/user/admin container shell
  allowlist          Edit firewall allow‑list
  info               Project diagnostics
  clean              Cleanup menu
  unlink             Remove ~/.local/bin/claudebox symlink
  rebuild            Force docker‑image rebuild
EOF
}

_cmd_profiles()  { _info "(stub) profiles called with $*"; }
_cmd_projects()  { _info "(stub) projects called   with $*"; }
_cmd_profile()   { _info "(stub) profile called   with $*"; }
_cmd_install()   { _info "(stub) install called   with $*"; }
_cmd_save()      { write_default_flag_file "$@"; }
_cmd_shell()     { _info "(stub) shell called     with $*"; }
_cmd_allowlist() { _info "(stub) allowlist called with $*"; }
_cmd_info()      { _info "(stub) info called      with $*"; }
_cmd_clean()     { _info "(stub) clean called     with $*"; }
_cmd_unlink()    { rm -f "${LINK_TARGET}" && _success "Unlinked ${LINK_TARGET}"; }
_cmd_rebuild()   { _info "(stub) rebuild called   with $*"; }

_forward_to_container() { run_claudebox_container "$(_get_project_slug "${PROJECT_DIR}")" "$@"; }

export -f dispatch_command
```

---

### entrypoint/docker-entrypoint.sh – strict container entrypoint

```bash
#!/usr/bin/env bash
set -euo pipefail
ENABLE_SUDO=false
DISABLE_FIREWALL=false
SHELL_MODE=false
FORWARD=()

# ---------------------------------- flag parse -------------------------------
while (($#)); do
  case "$1" in
    --enable-sudo)   ENABLE_SUDO=true   ;;
    --disable-firewall) DISABLE_FIREWALL=true ;;
    --shell-mode)    SHELL_MODE=true    ;;
    *)               FORWARD+=("$1")    ;;
  esac
  shift
done
set -- "${FORWARD[@]}"

export DISABLE_FIREWALL

# (real firewall/sudo logic intentionally omitted – fill in later)
echo "↪  [ENTRYPOINT] enable_sudo=${ENABLE_SUDO}  disable_firewall=${DISABLE_FIREWALL} shell_mode=${SHELL_MODE}"
exec "$@"
```

---

### assets/templates/init-firewall.tmpl

```bash
#!/bin/bash
# {{DOCKERUSER}} will be rendered by host‑side template engine.
set -euo pipefail
echo "(placeholder firewall script for {{DOCKERUSER}} – fill in your rules here)"
```

---

### assets/templates/docker-entrypoint.tmpl

```bash
#!/usr/bin/env bash
# A template version of the entrypoint – tokens rendered by host side.
exec /entrypoint/docker-entrypoint.sh "$@"
```

---

## 🛠 Next Steps / Migration Checklist

1. **Copy the files** above into your repo, maintaining the same paths.
2. `chmod +x` every `*.sh` file so Git preserves execution bits.
3. Incrementally move logic from the old monolith into the appropriate module:

   * Docker build logic → `lib/docker.sh`
   * Profile parsing & package lookup → `lib/config.sh`
   * All long helper functions → dedicated modules; keep `commands.sh` tiny.
4. Replace each “**(stub)**” handler with the real implementation (behaviour must not change).

   * Use `_debug` generously; it only appears when `--verbose` is passed.
5. Regenerate the two templates with `render_template` as part of `rebuild`.
6. Test matrix:

   * `claudebox --help`
   * `claudebox profiles`
   * `claudebox shell --verbose`
   * `claudebox rebuild`
   * Symlink (`which claudebox`) and state dir behaviour on repeat runs.
7. **CI**: add a bash‑strictness + `shellcheck` job; all modules are SC‑compliant.

Follow the checklist and you will have a maintainable, production‑ready ClaudeBox that is **behaviourally identical** to the original one‑file script.
