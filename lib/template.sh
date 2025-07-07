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
# Create build files for docker context
create_build_files() {
    local build_context="$1"

    cat > "$build_context/init-firewall" << 'EOF'
#!/bin/bash
set -euo pipefail
if [ "${DISABLE_FIREWALL:-false}" = "true" ]; then
    echo "Firewall disabled, skipping setup"
    rm -f "$0"
    exit 0
fi
iptables -F OUTPUT 2>/dev/null || true
iptables -F INPUT 2>/dev/null || true
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -s 127.0.0.0/8 -d 127.0.0.0/8 -j ACCEPT
iptables -A INPUT -s 127.0.0.0/8 -d 127.0.0.0/8 -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# Default allowed domains
DEFAULT_DOMAINS="api.anthropic.com console.anthropic.com statsig.anthropic.com sentry.io"

ALLOWED_DOMAINS="$DEFAULT_DOMAINS"
ALLOWLIST_FILE="/home/claude/.claudebox/projects/${CLAUDEBOX_PROJECT_NAME:-}/allowlist"
if [ -f "$ALLOWLIST_FILE" ]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^#.* ]] && continue
        [[ -z "$line" ]] && continue
        domain="${line#\*.}"
        domain="$(echo "$domain" | xargs)"
        [[ -n "$domain" ]] && ALLOWED_DOMAINS="$ALLOWED_DOMAINS $domain"
    done < "$ALLOWLIST_FILE"
fi

if command -v ipset >/dev/null 2>&1; then
    ipset destroy allowed-domains 2>/dev/null || true
    ipset create allowed-domains hash:net
    ipset destroy allowed-ips 2>/dev/null || true
    ipset create allowed-ips hash:net

    for domain in $ALLOWED_DOMAINS; do
        if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            ipset add allowed-ips $domain 2>/dev/null || true
        else
            ips=$(getent hosts $domain 2>/dev/null | awk '{print $1}')
            for ip in $ips; do
                ipset add allowed-domains $ip 2>/dev/null || true
            done
        fi
    done
    iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
    iptables -A OUTPUT -m set --match-set allowed-ips dst -j ACCEPT
else
    for domain in $ALLOWED_DOMAINS; do
        if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            iptables -A OUTPUT -d $domain -j ACCEPT
        else
            ips=$(getent hosts $domain 2>/dev/null | awk '{print $1}')
            for ip in $ips; do
                iptables -A OUTPUT -d $ip -j ACCEPT
            done
        fi
    done
fi
iptables -P OUTPUT DROP
iptables -P INPUT DROP
echo "Firewall initialized with Anthropic-only access"
rm -f "$(realpath "$0")"
EOF

    cat > "$build_context/docker-entrypoint.sh" << 'EOF'
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
# Note: claude user already has sudoers entry from Dockerfile
if [ "$ENABLE_SUDO" != "true" ]; then
    # Remove sudo access if --enable-sudo wasn't passed
    rm -f /etc/sudoers.d/claude
fi

if [ -n "$CLAUDEBOX_PROJECT_NAME" ]; then
    CONFIG_FILE="/home/claude/.claudebox/projects/${CLAUDEBOX_PROJECT_NAME}/config.ini"

    if command -v uv >/dev/null 2>&1 && [ -f "$CONFIG_FILE" ] && grep -qE 'python|ml|datascience' "$CONFIG_FILE"; then
        if [ ! -d /home/claude/.claudebox/projects/$CLAUDEBOX_PROJECT_NAME/.venv ]; then
            su - claude -c "uv venv /home/claude/.claudebox/projects/$CLAUDEBOX_PROJECT_NAME/.venv"
            if [ -f /workspace/pyproject.toml ]; then
                su - claude -c "cd /workspace && uv sync"
            else
                su - claude -c "uv pip install --python /home/claude/.claudebox/projects/$CLAUDEBOX_PROJECT_NAME/.venv/bin/python ipython black pylint mypy flake8 pytest ruff"
            fi
        fi

        for shell_rc in /home/claude/.zshrc /home/claude/.bashrc; do
            if ! grep -q "source /home/claude/.claudebox/projects/$CLAUDEBOX_PROJECT_NAME/.venv/bin/activate" "$shell_rc"; then
                echo 'if [ -f /home/claude/.claudebox/projects/$CLAUDEBOX_PROJECT_NAME/.venv/bin/activate ]; then source /home/claude/.claudebox/projects/$CLAUDEBOX_PROJECT_NAME/.venv/bin/activate; fi' >> "$shell_rc"
            fi
        done
    fi
fi

cd /home/claude

if [[ "${SHELL_MODE:-false}" == "true" ]]; then
    # Use runuser to avoid PTY signal handling issues
    exec runuser -u claude -- bash -c "source /home/claude/.nvm/nvm.sh && cd /workspace && exec /bin/zsh"
else
    # Claude mode - handle wrapper logic directly here
    if [[ "${1:-}" == "update" ]]; then
        # Special update handling - pass all arguments
        shift  # Remove "update" from arguments
        exec runuser -u claude -- bash -c '
            export NVM_DIR="$HOME/.nvm"
            if [[ -s "$NVM_DIR/nvm.sh" ]]; then
                \. "$NVM_DIR/nvm.sh"
                nvm use default >/dev/null 2>&1 || {
                    echo "Warning: Failed to activate default Node version" >&2
                }
            else
                echo "Warning: NVM not found, Node.js may not be available" >&2
            fi
            exec claude update "$@"
        ' -- "$@"
    else
        # Regular claude execution
        exec runuser -u claude -- bash -c '
            export NVM_DIR="$HOME/.nvm"
            if [[ -s "$NVM_DIR/nvm.sh" ]]; then
                \. "$NVM_DIR/nvm.sh"
                nvm use default >/dev/null 2>&1 || {
                    echo "Warning: Failed to activate default Node version" >&2
                }
            else
                echo "Warning: NVM not found, Node.js may not be available" >&2
            fi
            exec claude "$@"
        ' -- "$@"
    fi
fi
EOF

    chmod +x "$build_context/init-firewall" "$build_context/docker-entrypoint.sh"
}

export -f render_template create_build_files