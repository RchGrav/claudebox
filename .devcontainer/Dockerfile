# Use a base image with common development tools
FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Install jq for manipulating JSON, used by claudebox
# Install shellcheck for Bash linting and shfmt for formatting
# Install iptables for firewall management and dnsutils for nslookup/dig (if needed for firewall script)
USER root
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y jq shellcheck shfmt iptables dnsutils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
USER vscode

# Copy the claudebox script into a common location
# This assumes the Dockerfile is in .devcontainer and claudebox is at the repo root
COPY ../claudebox /usr/local/bin/claudebox-dev

# Make it executable
RUN sudo chmod +x /usr/local/bin/claudebox-dev

# Copy the firewall script
COPY init-firewall.sh /home/vscode/init-firewall.sh
RUN sudo chmod +x /home/vscode/init-firewall.sh

# Set a default command if needed, or rely on VS Code to open the workspace
# CMD ["/bin/bash"]
ENV SHELL /bin/bash
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
