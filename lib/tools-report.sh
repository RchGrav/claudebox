#!/usr/bin/env bash
# Tools Report Generator - Creates tooling.md documenting installed tools
# ============================================================================

# Generate the developer tools report and save to ~/.claudebox/tooling.md
generate_tools_report() {
    local profiles_ini="/home/claude/.claudebox/profiles.ini"
    local output_file="/home/claude/.claudebox/tooling.md"
    
    # Start the markdown document
    {
        # Check if profiles.ini exists
        if [[ -f "$profiles_ini" ]]; then
            # Parse active profiles
            local profiles=()
            local in_profiles_section=false
            while IFS= read -r line; do
                if [[ "$line" == "[profiles]" ]]; then
                    in_profiles_section=true
                    continue
                elif [[ "$line" == "["*"]" ]]; then
                    in_profiles_section=false
                    continue
                fi
                
                if [[ "$in_profiles_section" == true ]] && [[ -n "$line" ]]; then
                    profiles+=("$line")
                fi
            done < "$profiles_ini"
            
            if [[ ${#profiles[@]} -gt 0 ]]; then
                echo "## Active Development Profiles"
                echo
                for profile in "${profiles[@]:-}"; do
                    echo "### $profile"
                    echo
                    _describe_profile "$profile"
                    echo
                done
            else
                echo "## No Active Profiles"
                echo
                echo "No development profiles are currently active."
                echo
            fi
            
            # Check for custom packages
            local packages=()
            local in_packages_section=false
            while IFS= read -r line; do
                if [[ "$line" == "[packages]" ]]; then
                    in_packages_section=true
                    continue
                elif [[ "$line" == "["*"]" ]]; then
                    in_packages_section=false
                    continue
                fi
                
                if [[ "$in_packages_section" == true ]] && [[ -n "$line" ]]; then
                    packages+=("$line")
                fi
            done < "$profiles_ini"
            
            if [[ ${#packages[@]} -gt 0 ]]; then
                echo "## Additional Packages"
                echo
                echo "The following custom packages have been installed:"
                echo
                for package in "${packages[@]:-}"; do
                    echo "- $package"
                done
                echo
            fi
        else
            echo "## Default Environment"
            echo
            echo "No profiles.ini found - using default ClaudeBox environment."
            echo
        fi
        
        # Always installed tools
        echo "## Core Tools (Always Available)"
        echo
        echo "These tools are included in every ClaudeBox container:"
        echo
        echo "### Development Essentials"
        echo "- **git** - Version control system"
        echo "- **gh** - GitHub CLI for repository management"
        echo "- **curl/wget** - HTTP clients for downloading files"
        echo "- **jq** - JSON processor for parsing and manipulating JSON"
        echo "- **tmux** - Terminal multiplexer for managing sessions"
        echo "- **nano/vim** - Text editors"
        echo
        echo "### Claude CLI"
        echo "- **claude** - Anthropic's Claude CLI (pre-configured)"
        echo
        echo "### System Utilities"
        echo "- **sudo** - Execute commands with elevated privileges"
        echo "- **htop** - Interactive process viewer"
        echo "- **tree** - Display directory structure"
        echo "- **unzip/zip** - Archive management"
        echo
        
        # Footer
        echo "---"
        echo
        echo "## Using These Tools"
        echo
        echo "All tools listed above are available in your PATH and ready to use."
        echo "For tool-specific help, use:"
        echo
        echo '```bash'
        echo '<tool> --help'
        echo '# or'
        echo 'man <tool>'
        echo '```'
        echo
        echo "This document is automatically generated based on your project's profiles.ini configuration."
    } > "$output_file"
    
    echo "Developer README generated at: $output_file"
}

# Describe what each profile provides
_describe_profile() {
    local profile="$1"
    
    case "$profile" in
        core)
            echo "**Core Development Utilities**"
            echo
            echo "Essential development tools including:"
            echo "- GCC/G++ compilers for C/C++ development"
            echo "- Make build automation tool"
            echo "- pkg-config for managing library compile flags"
            echo "- OpenSSL and zlib development libraries"
            echo
            ;;
            
        build-tools)
            echo "**Build and Automation Tools**"
            echo
            echo "Modern build systems and tools:"
            echo "- CMake - Cross-platform build system generator"
            echo "- Ninja - Small, fast build system"
            echo "- Autoconf/Automake - GNU build system"
            echo "- Libtool - Generic library support script"
            echo
            ;;
            
        shell)
            echo "**Enhanced Shell Tools**"
            echo
            echo "Additional shell utilities:"
            echo "- fzf - Fuzzy finder (installed via git)"
            echo "- rsync - Fast file synchronization"
            echo "- OpenSSH client - Secure shell connections"
            echo "- man-db - Manual page viewer"
            echo "- GnuPG - Encryption and signing"
            echo "- file - Determine file types"
            echo
            ;;
            
        networking)
            echo "**Network Development Tools**"
            echo
            echo "Network configuration and analysis:"
            echo "- iptables/ipset - Firewall management"
            echo "- iproute2 - Advanced IP routing utilities"
            echo "- dnsutils - DNS lookup tools (dig, nslookup)"
            echo
            ;;
            
        webdev|javascript)
            echo "**JavaScript Development Environment**"
            echo
            echo "JavaScript/TypeScript development stack:"
            echo "- Node.js (via nvm) - JavaScript runtime"
            echo "- npm - Node package manager"
            echo "- typescript - TypeScript language support"
            echo "- eslint - JavaScript linter"
            echo "- prettier - Code formatter"
            echo "- yarn - Alternative package manager"
            echo "- pnpm - Fast, disk space efficient package manager"
            echo
            ;;
            
        python)
            echo "**Python Development Environment**"
            echo
            echo "Python development with modern tooling:"
            echo "- Python 3 (system python)"
            echo "- uv - Fast Python package installer and resolver"
            echo "- pip - Python package installer"
            echo "- venv - Virtual environment support"
            echo "- ipython - Interactive Python shell"
            echo "- black - Code formatter"
            echo "- mypy - Static type checker"
            echo "- pylint - Code analyzer"
            echo "- pytest - Testing framework"
            echo "- ruff - Fast Python linter"
            echo "- poetry - Dependency management"
            echo "- pipenv - Package management tool"
            echo
            ;;
            
        rust)
            echo "**Rust Development Environment**"
            echo
            echo "Rust programming language toolchain:"
            echo "- rustc - Rust compiler"
            echo "- cargo - Rust package manager and build tool"
            echo "- rustup - Rust toolchain installer"
            echo "- rust-analyzer - Language server"
            echo "- Common tools: clippy, rustfmt"
            echo
            ;;
            
        go)
            echo "**Go Development Environment**"
            echo
            echo "Go programming language:"
            echo "- go - Go compiler and tools"
            echo "- gofmt - Go code formatter"
            echo "- go mod - Dependency management"
            echo "- Common tools: golangci-lint, delve debugger"
            echo
            ;;
            
        flutter)
            echo "**Flutter Framework**"
            echo
            echo Use FLUTTER_SDK_VERSION environment variable before running claudebox to set use different flutter version
            echo Ex: FLUTTER_SDK_VERSION=beta claudebox
            echo
            echo "Available commands:"
            echo "- flutter - To manage flutter apps"
            echo "- dart - To run dart cli tasks"
            echo "- fvm - To manage flutter versions"
            echo
            ;;
            
        c)
            echo "**C/C++ Advanced Development**"
            echo
            echo "Advanced C/C++ development tools:"
            echo "- GDB - GNU debugger"
            echo "- Valgrind - Memory debugging and profiling"
            echo "- Clang/LLVM - Alternative C/C++ compiler"
            echo "- clang-format - Code formatter"
            echo "- clang-tidy - Linter and static analyzer"
            echo "- cppcheck - Static analysis tool"
            echo "- Doxygen - Documentation generator"
            echo "- Boost libraries - C++ library collection"
            echo "- CMocka - Unit testing framework"
            echo "- lcov - Code coverage tool"
            echo "- ncurses - Terminal UI library"
            echo
            ;;
            
        java)
            echo "**Java Development Environment**"
            echo
            echo "Java development tools:"
            echo "- Java - Latest JDK LTS installed via SDKMan"
            echo "- Maven - Build automation and dependency management (via SDKMan)"
            echo "- Gradle - Build automation system (via SDKMan)"
            echo "- Ant - Build tool (via SDKMan)"
            echo
            ;;
            
        ruby)
            echo "**Ruby Development Environment**"
            echo
            echo "Ruby programming tools:"
            echo "- Ruby - Ruby interpreter"
            echo "- gem - Ruby package manager"
            echo "- bundler - Dependency manager"
            echo "- Development libraries for native extensions"
            echo
            ;;
            
        php)
            echo "**PHP Development Environment**"
            echo
            echo "PHP web development:"
            echo "- PHP - PHP interpreter"
            echo "- PHP-FPM - FastCGI Process Manager"
            echo "- Composer - Dependency manager"
            echo "- Common extensions: mysql, pgsql, sqlite3, curl, gd, mbstring, xml, zip"
            echo
            ;;
            
        database)
            echo "**Database Client Tools**"
            echo
            echo "Database connectivity:"
            echo "- PostgreSQL client - psql and utilities"
            echo "- MySQL client - mysql and utilities"
            echo "- SQLite3 - Lightweight SQL database"
            echo "- Redis tools - redis-cli and utilities"
            echo "- MongoDB clients - mongo shell and tools"
            echo
            ;;
            
        devops)
            echo "**DevOps and Cloud Tools**"
            echo
            echo "Infrastructure and deployment:"
            echo "- Docker - Container runtime and CLI"
            echo "- docker-compose - Multi-container orchestration"
            echo "- kubectl - Kubernetes CLI"
            echo "- helm - Kubernetes package manager"
            echo "- terraform - Infrastructure as Code"
            echo "- ansible - Configuration management"
            echo "- AWS CLI - Amazon Web Services CLI"
            echo
            ;;
            
        web)
            echo "**Web Server Tools**"
            echo
            echo "Web server utilities:"
            echo "- nginx - High-performance web server"
            echo "- apache2-utils - Apache utilities (htpasswd, ab)"
            echo "- httpie - User-friendly HTTP client"
            echo
            ;;
            
        embedded)
            echo "**Embedded Development Tools**"
            echo
            echo "Embedded systems development:"
            echo "- arm-none-eabi-gcc - ARM cross-compiler"
            echo "- gdb-multiarch - Multi-architecture debugger"
            echo "- OpenOCD - On-chip debugger"
            echo "- picocom/minicom - Serial terminal programs"
            echo "- screen - Terminal multiplexer (for serial)"
            echo "- PlatformIO - Embedded development platform"
            echo
            ;;
            
        datascience)
            echo "**Data Science Environment**"
            echo
            echo "Complete data science toolkit:"
            echo "- Python 3 with venv"
            echo "- R - Statistical computing language"
            echo "- jupyter - Interactive notebooks"
            echo "- notebook - Classic Jupyter notebook"
            echo "- jupyterlab - JupyterLab interface"
            echo "- numpy - Numerical computing"
            echo "- pandas - Data analysis and manipulation"
            echo "- scipy - Scientific computing"
            echo "- matplotlib - Plotting library"
            echo "- seaborn - Statistical data visualization"
            echo "- scikit-learn - Machine learning library"
            echo "- statsmodels - Statistical modeling"
            echo "- plotly - Interactive visualizations"
            echo
            ;;
            
        security)
            echo "**Security Analysis Tools**"
            echo
            echo "Security testing and analysis:"
            echo "- nmap - Network exploration and security auditing"
            echo "- tcpdump - Packet analyzer"
            echo "- wireshark-common - Network protocol analyzer (CLI tools)"
            echo "- netcat - Network utility for reading/writing data"
            echo "- john - Password cracker"
            echo "- hashcat - Advanced password recovery"
            echo "- hydra - Network login cracker"
            echo
            ;;
            
        ml)
            echo "**Machine Learning Environment**"
            echo
            echo "Machine learning development:"
            echo "- Python 3 with venv"
            echo "- torch - PyTorch deep learning framework"
            echo "- transformers - Hugging Face transformers library"
            echo "- scikit-learn - Machine learning library"
            echo "- numpy - Numerical computing"
            echo "- pandas - Data analysis and manipulation"
            echo "- matplotlib - Plotting library"
            echo
            ;;
            
        openwrt)
            echo "**OpenWRT Development Environment**"
            echo
            echo "OpenWRT/embedded Linux development:"
            echo "- Cross-compilation toolchains"
            echo "- QEMU emulators (ARM, AArch64, MIPS, x86)"
            echo "- Build dependencies for OpenWRT"
            echo "- Subversion, ccache for faster builds"
            echo
            ;;
            
        *)
            echo "**Custom Profile: $profile**"
            echo
            echo "This is a custom profile. Check your configuration for details."
            echo
            ;;
    esac
}

# Export the main function
export -f generate_tools_report _describe_profile
