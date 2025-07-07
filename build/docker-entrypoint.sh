#!/bin/bash
set -euo pipefail
ENABLE_SUDO=false
DISABLE_FIREWALL=false
SHELL_MODE=false
new_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --enable-sudo) ENABLE_SUDO=true; shift ;;
        --disable-firewall) DISABLE_FIREWALL=true; shift ;;
        --shell-mode) SHELL_MODE=true; shift ;;
        *) new_args+=("$1"); shift ;;
    esac
done
set -- "${new_args[@]}"
export DISABLE_FIREWALL

if [ -f ~/init-firewall ]; then
    ~/init-firewall || true
fi

# Handle sudo access based on --enable-sudo flag
# Note: DOCKERUSER user already has sudoers entry from Dockerfile
if [ "$ENABLE_SUDO" != "true" ]; then
    # Remove sudo access if --enable-sudo wasn't passed
    rm -f /etc/sudoers.d/DOCKERUSER
fi

if [ -n "$CLAUDEBOX_PROJECT_NAME" ]; then
    CONFIG_FILE="/home/DOCKERUSER/.claudebox/config.ini"

    if command -v uv >/dev/null 2>&1 && [ -f "$CONFIG_FILE" ] && grep -qE 'python|ml|datascience' "$CONFIG_FILE"; then
        # Python venv already exists at /home/DOCKERUSER/.venv from Docker build
        # Just add activation to shell rc files if needed
        for shell_rc in /home/DOCKERUSER/.zshrc /home/DOCKERUSER/.bashrc; do
            if ! grep -q "source /home/DOCKERUSER/.venv/bin/activate" "$shell_rc"; then
                echo 'if [ -f /home/DOCKERUSER/.venv/bin/activate ]; then source /home/DOCKERUSER/.venv/bin/activate; fi' >> "$shell_rc"
            fi
        done
    fi
fi

cd /home/DOCKERUSER

if [[ "${SHELL_MODE:-false}" == "true" ]]; then
    # Use runuser to avoid PTY signal handling issues
    exec runuser -u DOCKERUSER -- bash -c "source /home/DOCKERUSER/.nvm/nvm.sh && cd /workspace && exec /bin/zsh"
else
    # Claude mode - handle wrapper logic directly here
    if [[ "${1:-}" == "update" ]]; then
        # Special update handling - pass all arguments
        shift  # Remove "update" from arguments
        exec runuser -u DOCKERUSER -- bash -c '
            export NVM_DIR="$HOME/.nvm"
            if [[ -s "$NVM_DIR/nvm.sh" ]]; then
                \. "$NVM_DIR/nvm.sh"
                nvm use default >/dev/null 2>&1 || {
                    echo "Warning: Failed to activate default Node version" >&2
                }
            else
                echo "Warning: NVM not found at $NVM_DIR" >&2
            fi
            
            cd /workspace
            echo "Running update command..."
            
            # Check for stale update lock (older than 5 minutes)
            lock_file="$HOME/.DOCKERUSER/.update.lock"
            if [[ -f "$lock_file" ]]; then
                lock_age=$(( $(date +%s) - $(stat -f %m "$lock_file" 2>/dev/null || stat -c %Y "$lock_file" 2>/dev/null || echo 0) ))
                if [[ $lock_age -gt 300 ]]; then
                    rm -f "$lock_file"
                fi
            fi
            
            # Capture the output of DOCKERUSER update to check if already up to date
            update_output=$(DOCKERUSER update 2>&1)
            echo "$update_output"
            
            # Only run version check if an actual update occurred
            if echo "$update_output" | grep -q "Successfully updated\|Installing update"; then
                echo "Verifying update..."
                DOCKERUSER --version
            fi
        '
    else
        # Regular DOCKERUSER execution
        exec runuser -u DOCKERUSER -- bash -c '
            export NVM_DIR="$HOME/.nvm"
            if [[ -s "$NVM_DIR/nvm.sh" ]]; then
                \. "$NVM_DIR/nvm.sh"
                nvm use default >/dev/null 2>&1 || {
                    echo "Warning: Failed to activate default Node version" >&2
                }
            else
                echo "Warning: NVM not found at $NVM_DIR" >&2
            fi
            
            cd /workspace
            
            # If no arguments and stdin is a terminal, run DOCKERUSER in interactive mode
            if [[ $# -eq 0 ]] && [[ -t 0 ]]; then
                exec DOCKERUSER
            else
                exec DOCKERUSER "$@"
            fi
        ' -- "$@"
    fi
fi
