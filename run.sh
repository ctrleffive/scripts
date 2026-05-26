#!/usr/bin/env bash
# =============================================================================
#  run.sh — Ctrl F5 Scripts Launcher
#
#  Usage:
#    curl -sL chandujs.com/s | bash
# =============================================================================

set -euo pipefail

# ── Script Registry ──────────────────────────────────────────────────────────
# Add new scripts here. Metadata (@name, @desc, @sudo, @os) is read from each file.
BASE_URL="https://scripts.chandujs.com/scripts"
SCRIPTS=(
    "mc.sh"
    "ram.sh"
)

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[38;2;0;229;160m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
ok()   { echo -e " ${GREEN}✔${RESET} $*"; }
warn() { echo -e " ${YELLOW}!${RESET} $*"; }
die()  { echo -e "\n ${RED}✖${RESET} $*" >&2; exit 1; }

# ── Spinner ───────────────────────────────────────────────────────────────────
SPINNER_PID=""
spinner_start() {
    local label="$1"
    ( local f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'); local i=0
      while true; do
          printf "\r ${CYAN}${f[$((i % 10))]}${RESET} %s" "$label"
          sleep 0.08; i=$(( i + 1 ))
      done ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null || true
}
spinner_stop() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill -0 "$SPINNER_PID" 2>/dev/null && kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
    printf "\r\033[K"
}

# ── Metadata parser ──────────────────────────────────────────────────────────
parse_meta() {
    local file="$1" key="$2"
    head -10 "$file" | grep -m1 "^# @${key} " | sed "s/^# @${key} //" || true
}

# ── Cleanup ───────────────────────────────────────────────────────────────────
TMP_DIR=""
cleanup() {
    spinner_stop 2>/dev/null || true
    [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
 ███████  ██████ ██████  ██ ██████  ████████ ███████ 
 ██      ██      ██   ██ ██ ██   ██    ██    ██      
 ███████ ██      ██████  ██ ██████     ██    ███████ 
      ██ ██      ██   ██ ██ ██         ██         ██ 
 ███████  ██████ ██   ██ ██ ██         ██    ███████ 
EOF
    echo -e "${RESET}"
    echo ""

    # ── Detect host OS ─────────────────────────────────────────────────────────
    local current_os
    case "$(uname -s)" in
        Darwin) current_os="macos" ;;
        Linux)  current_os="linux" ;;
        *)      current_os="unknown" ;;
    esac

    # ── Download all scripts ──────────────────────────────────────────────────
    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cf5_XXXXXX")
    spinner_start "Loading available scripts..."

    local names=() descs=() sudos=() oses=() paths=()
    for script in "${SCRIPTS[@]}"; do
        local url="${BASE_URL}/${script}"
        local tmp_path="${TMP_DIR}/${script}"
        if ! curl -sL --fail "$url" -o "$tmp_path" 2>/dev/null; then
            spinner_stop
            die "Failed to download ${script}. Check your internet connection."
        fi

        names+=("$(parse_meta "$tmp_path" "name")")
        descs+=("$(parse_meta "$tmp_path" "desc")")
        sudos+=("$(parse_meta "$tmp_path" "sudo")")
        oses+=("$(parse_meta "$tmp_path" "os")")
        paths+=("$tmp_path")
    done

    spinner_stop

    # ── Filter by current OS ──────────────────────────────────────────────────
    local filtered=()
    for i in "${!SCRIPTS[@]}"; do
        local os_list="${oses[$i]}"
        if [[ -z "$os_list" ]] || [[ ",$os_list," == *",$current_os,"* ]]; then
            filtered+=("$i")
        fi
    done

    if (( ${#filtered[@]} == 0 )); then
        die "No scripts available for ${BOLD}${current_os}${RESET}."
    fi

    # ── Display menu ──────────────────────────────────────────────────────────
    echo -e " ${BOLD}Available Scripts${RESET}"
    echo ""

    local menu_num=0
    for idx in "${filtered[@]}"; do
        menu_num=$(( menu_num + 1 ))
        local sudo_badge=""
        [[ "${sudos[$idx]}" == "true" ]] && sudo_badge=" ${YELLOW}${DIM}sudo${RESET}"

        local os_badge=""
        if [[ -n "${oses[$idx]}" ]]; then
            os_badge=" ${DIM}${oses[$idx]//,/ · }${RESET}"
        fi

        echo -e " ${CYAN}${BOLD}$(printf '%-2d' "$menu_num")${RESET} ${BOLD}${names[$idx]}${RESET}${sudo_badge}"
        echo -e "    ${descs[$idx]}"
        if [[ -n "${oses[$idx]}" ]]; then
            echo -e "    ${DIM}Supports: ${oses[$idx]//,/, }${RESET}"
        fi
        echo ""
    done

    echo -e " ${DIM}${RESET}"
    echo ""

    # ── Selection ─────────────────────────────────────────────────────────────
    echo -e " ${DIM}   Ctrl+C to quit${RESET}"
    echo ""
    local selection
    while true; do
        echo -ne " ${CYAN}?${RESET}  Select a script ${DIM}[1-${#filtered[@]}]${RESET}: "
        read -r selection < /dev/tty

        if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#filtered[@]} )); then
            break
        fi

        printf "\033[1A\033[K"
    done

    local pick=${filtered[$(( selection - 1 ))]}
    local selected_name="${names[$pick]}"
    local selected_path="${paths[$pick]}"
    local needs_sudo="${sudos[$pick]}"

    echo ""

    # ── Arguments ─────────────────────────────────────────────────────────────
    local user_args=""
    echo -ne " ${CYAN}?${RESET}  Arguments ${DIM}(blank for defaults)${RESET}: "
    read -r user_args < /dev/tty
    echo ""

    # ── Execute ───────────────────────────────────────────────────────────────
    chmod +x "$selected_path"
    ok " Launching ${BOLD}${selected_name}${RESET}"
    echo ""

    if [[ "$needs_sudo" == "true" ]]; then
        clear
        warn " This script requires ${BOLD}sudo${RESET} access."
        echo ""
        # shellcheck disable=SC2086
        sudo bash "$selected_path" $user_args
    else
        clear
        # shellcheck disable=SC2086
        bash "$selected_path" $user_args
    fi
}

main "$@"
