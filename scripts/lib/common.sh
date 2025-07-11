#!/usr/bin/env bash
# Shared helpers that every module can safely source.

# -------- colours -------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# -------- utility functions ---------------------------------------------------
cecho() { printf "${2:-$NC}%s${NC}\n" "$1"; }
error() { cecho "$1" "$RED" >&2; exit "${2:-1}"; }
warn() { cecho "$1" "$YELLOW"; }
info() { cecho "$1" "$BLUE"; }
success() { cecho "$1" "$GREEN"; }

# -------- logo functions ------------------------------------------------------
logo() {
    local cb='
 ██████╗██╗      █████╗ ██╗   ██╗██████╗ ███████╗
██╔════╝██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝
██║     ██║     ███████║██║   ██║██║  ██║█████╗
██║     ██║     ██╔══██║██║   ██║██║  ██║██╔══╝
╚██████╗███████╗██║  ██║╚██████╔╝██████╔╝███████╗
 ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝

██████╗  ██████╗ ██╗  ██╗ ------ ┌──────────────┐
██╔══██╗██╔═══██╗╚██╗██╔╝ ------ │ The Ultimate │
██████╔╝██║   ██║ ╚███╔╝  ------ │ Claude Code  │
██╔══██╗██║   ██║ ██╔██╗  ------ │  Docker Dev  │
██████╔╝╚██████╔╝██╔╝ ██╗ ------ │ Environment  │
╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ------ └──────────────┘
'
    while IFS= read -r l; do
        o="" c=""
        for ((i=0;i<${#l};i++)); do
            ch="${l:$i:1}"
            [ "$ch" = " " ] && { o+="$ch"; continue; }
            cc=$(printf '%d' "'$ch" 2>/dev/null||echo 0)
            if [ $cc -ge 32 ] && [ $cc -le 126 ]; then n='\033[33m'      # Yellow for regular text
            elif [ $cc -ge 9552 ] && [ $cc -le 9580 ]; then n='\033[34m'  # Blue for box drawing
            elif [ $cc -eq 9608 ]; then n='\033[31m'                      # Red for block chars
            else n='\033[37m'; fi                                          # White for others
            [ "$n" != "$c" ] && { o+="$n"; c="$n"; }
            o+="$ch"
        done
        printf "${o}\033[0m\n"
    done <<< "$cb"
}

logo_header() {
    local cb='
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║  █▀▀ █   ▄▀█ █ █ █▀▄ █▀▀ █▄▄ █▀█ ▀▄▀   Docker Environment for Claude Code  ║
║  █▄▄ █▄▄ █▀█ █▄█ █▄▀ ██▄ █▄█ █▄█ █ █    Isolated  •  Secure  •  Powerful   ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
'
    while IFS= read -r l; do
        o="" c=""
        for ((i=0;i<${#l};i++)); do
            ch="${l:$i:1}"
            [ "$ch" = " " ] && { o+="$ch"; continue; }
            cc=$(printf '%d' "'$ch" 2>/dev/null||echo 0)
            if [ $cc -ge 32 ] && [ $cc -le 126 ] && [ "$ch" != "•" ]; then n='\033[37m'      # White for regular text
            elif [ $cc -ge 9552 ] && [ $cc -le 9580 ]; then n='\033[90m'  # Grey for box drawing
            elif [ $cc -eq 9608 ] || [ $cc -ge 9600 ] && [ $cc -le 9631 ]; then n='\033[37m'  # White for block chars
            elif [ "$ch" = "•" ]; then n='\033[31m'                       # Red for bullets
            else n='\033[37m'; fi                                          # White for others
            [ "$n" != "$c" ] && { o+="$n"; c="$n"; }
            o+="$ch"
        done
        printf "${o}\033[0m\n"
    done <<< "$cb"
}

logo_small() {
    local cb='
█▀▀ █   ▄▀█ █ █ █▀▄ █▀▀ █▄▄ █▀█ ▀▄▀
█▄▄ █▄▄ █▀█ █▄█ █▄▀ ██▄ █▄█ █▄█ █ █
'
    printf "${WHITE}%s${NC}" "$cb"
}

# -------- spinner function ----------------------------------------------------
show_spinner() {
    local pid=$1 msg=$2 spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    echo -n "$msg "
    while kill -0 "$pid" 2>/dev/null; do
        printf "\b%s" "${spin:i++%${#spin}:1}"
        sleep 0.1
    done
    echo -e "\b${GREEN}✓${NC}"
}

# -------- fillbar progress indicator ------------------------------------------
FILLBAR_PID=""

fillbar() {
    case "${1:-}" in
        stop)
            if [ ! -z "$FILLBAR_PID" ]; then
                kill $FILLBAR_PID 2>/dev/null
            fi
            printf "\r\033[K"
            tput cnorm
            FILLBAR_PID=""
            ;;
        *)
            (
                p=0
                tput civis
                while true; do
                    printf "\r"
                    full=$((p / 8))
                    part=$((p % 8))
                    i=0
                    while [ $i -lt $full ]; do
                        printf "█"
                        i=$((i + 1))
                    done
                    if [ $part -gt 0 ]; then
                        pb=$(printf %x $((0x258F - part + 1)))
                        printf "\\u$pb"
                    fi
                    p=$((p + 1))
                    sleep 0.01
                done
            ) &
            FILLBAR_PID=$!
            ;;
    esac
}

export -f cecho error warn info success logo logo_header logo_small show_spinner fillbar
