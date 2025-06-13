#!/bin/bash
set -euo pipefail

echo "Starting firewall configuration for Dev Container..."

# Whitelisted domains - add more as needed for development
# Note: Wildcards like *.github.com need careful handling as iptables works with IPs.
# This script will resolve them at runtime. If IPs change frequently, this could be an issue.
WHITELISTED_DOMAINS=(
    "api.anthropic.com"
    "github.com"
    "api.github.com"
    "codeload.github.com"
    "objects.githubusercontent.com" # For raw content, releases
    "*.archive.ubuntu.com" # Ubuntu packages
    "security.ubuntu.com"  # Ubuntu security updates
    "pypi.org"             # Python packages
    "files.pythonhosted.org"
    "registry.npmjs.org"   # Node packages
    "crates.io"            # Rust packages
    "dl.google.com"        # For tools like gcloud, Chrome Remote Desktop (if used)
    "mcr.microsoft.com"    # Microsoft container registry (base images)
    "ghcr.io"              # GitHub container registry
    "vscode.blob.core.windows.net" # VS Code extension downloads
    "marketplace.visualstudio.com" # VS Code marketplace
    "*.vscode-unpkg.net" # VS Code extensions' assets
    "update.code.visualstudio.com" # VS Code updates
    # Add any other essential domains for your development workflow
)

# Ports to allow for whitelisted domains (common web and git ports)
ALLOWED_TCP_PORTS="80,443,22,9418" # HTTP, HTTPS, SSH, Git
ALLOWED_UDP_PORTS="" # Typically none needed for these domains, but can add if required

# --- Basic Firewall Setup ---
echo "Applying basic firewall rules..."
# Flush all existing rules
sudo iptables -F OUTPUT || echo "Failed to flush OUTPUT chain (might be normal if empty)"
sudo iptables -F INPUT || echo "Failed to flush INPUT chain"
sudo iptables -F FORWARD || echo "Failed to flush FORWARD chain"

# Set default policies: Drop all traffic not explicitly allowed
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT DROP

# Allow loopback traffic
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Allow established and related connections (important for return traffic)
sudo iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# Allow DNS lookups (UDP and TCP on port 53) - essential for resolving domains
sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
echo "Basic rules and DNS allowed."

# --- Whitelist Domain Resolution and Rules ---
echo "Resolving whitelisted domains and adding rules..."
for domain_pattern in "${WHITELISTED_DOMAINS[@]}"; do
    echo "Processing domain pattern: $domain_pattern"
    # Handle wildcard domains by trying to resolve the base and common subdomains
    # This is a simplified approach for wildcards. A more robust solution might involve
    # dynamically updating IPs or using a proxy that handles domain names.
    declare -a domains_to_resolve=()
    if [[ "$domain_pattern" == "*."* ]]; then
        base_domain="${domain_pattern#\*.}"
        # Add common subdomains or just the base. For package repos, the base is often enough.
        domains_to_resolve+=("$base_domain")
        # For example, for *.archive.ubuntu.com, we primarily care about archive.ubuntu.com and mirrors.
        # For *.github.com, www.github.com, api.github.com etc. are covered by explicit entries.
    else
        domains_to_resolve+=("$domain_pattern")
    fi

    for domain in "${domains_to_resolve[@]}"; do
        echo "  Resolving: $domain"
        # Using getent ahostsv4 for IPv4 addresses. Add ahostsv6 for IPv6 if needed.
        # Redirecting stderr to /dev/null for cases where a domain might not resolve (e.g. a CNAME pointing to another domain)
        ips=$(getent ahosts "$domain" | awk '{print $1}' | sort -u || true)
        if [ -n "$ips" ]; then
            for ip in $ips; do
                if [ -n "$ALLOWED_TCP_PORTS" ]; then
                    echo "    Allowing TCP to $domain ($ip) on ports $ALLOWED_TCP_PORTS"
                    sudo iptables -A OUTPUT -d "$ip" -p tcp -m multiport --dports "$ALLOWED_TCP_PORTS" -j ACCEPT
                fi
                if [ -n "$ALLOWED_UDP_PORTS" ]; then
                    echo "    Allowing UDP to $domain ($ip) on ports $ALLOWED_UDP_PORTS"
                    sudo iptables -A OUTPUT -d "$ip" -p udp -m multiport --dports "$ALLOWED_UDP_PORTS" -j ACCEPT
                fi
            done
        else
            echo "    Warning: Could not resolve IP for $domain. Firewall rule not added."
        fi
    done
done
echo "Whitelist rules applied."

# --- Verification (Optional but Recommended) ---
echo "Verifying firewall status..."
sudo iptables -L OUTPUT -n -v --line-numbers

echo "Testing connectivity (should succeed for whitelisted, fail for others):"
echo "  GitHub (whitelisted):"
if curl --connect-timeout 5 -Is https://github.com > /dev/null; then
    echo "    ✅ GitHub connection successful."
else
    echo "    ❌ GitHub connection failed."
fi

echo "  Example.com (likely not whitelisted, should fail unless it was added or resolved via another rule):"
if curl --connect-timeout 5 -Is https://example.com > /dev/null; then
    echo "    ⚠️ Example.com connection successful (unexpected if not whitelisted)."
else
    echo "    ✅ Example.com connection blocked as expected."
fi

echo "Firewall configuration complete."
# To drop all rules for testing:
# sudo iptables -P INPUT ACCEPT; sudo iptables -P FORWARD ACCEPT; sudo iptables -P OUTPUT ACCEPT; sudo iptables -F INPUT; sudo iptables -F OUTPUT; sudo iptables -F FORWARD;
# Remember to re-apply if testing this way.
