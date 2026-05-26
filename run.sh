#!/usr/bin/env bash
# =============================================================================
#  run.sh — Ctrl F5 Scripts Launcher
#
#  Usage:
#    curl -sL chandujs.com/s | bash
# =============================================================================

set -euo pipefail

# ── Script Registry ──────────────────────────────────────────────────────────
# Add new scripts here. Metadata (@name, @desc, @sudo) is read from each file.
BASE_URL="https://scripts.chandujs.com/scripts"
SCRIPTS=(
    "mc.sh"
    "ram.sh"
)

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
ok()   { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}!${RESET}  $*"; }
die()  { echo -e "\n  ${RED}✖${RESET}  $*" >&2; exit 1; }

# ── Spinner ───────────────────────────────────────────────────────────────────
SPINNER_PID=""
spinner_start() {
    local label="$1"
    ( local f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'); local i=0
      while true; do
          printf "\r  ${CYAN}${f[$((i % 10))]}${RESET}  %s" "$label"
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
    head -10 "$file" | grep -m1 "^# @${key} " | sed "s/^# @${key} //"
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
    echo ""
    echo -e "  ${CYAN}${BOLD}⚡ CTRL F5 SCRIPTS${RESET}"
    echo -e "  ${DIM}scripts.chandujs.com${RESET}"
    echo ""
    echo -e "  ${DIM}$(printf '─%.0s' {1..44})${RESET}"
    echo ""

    # ── Download all scripts ──────────────────────────────────────────────────
    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cf5_XXXXXX")
    spinner_start "Loading available scripts..."

    local names=() descs=() sudos=() paths=()
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
        paths+=("$tmp_path")
    done

    spinner_stop

    # ── Display menu ──────────────────────────────────────────────────────────
    echo -e "  ${BOLD}Available Scripts${RESET}"
    echo ""

    for i in "${!SCRIPTS[@]}"; do
        local num=$(( i + 1 ))
        local sudo_badge=""
        [[ "${sudos[$i]}" == "true" ]] && sudo_badge=" ${YELLOW}${DIM}sudo${RESET}"

        echo -e "  ${CYAN}${BOLD} ${num} ${RESET}  ${BOLD}${names[$i]}${RESET}${sudo_badge}"
        echo -e "       ${DIM}${descs[$i]}${RESET}"
        echo ""
    done

    echo -e "  ${DIM}$(printf '─%.0s' {1..44})${RESET}"
    echo ""

    # ── Selection ─────────────────────────────────────────────────────────────
    local selection
    echo -ne "  ${CYAN}?${RESET}  Select a script ${DIM}[1-${#SCRIPTS[@]}]${RESET}: "
    read -r selection < /dev/tty

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#SCRIPTS[@]} )); then
        die "Invalid selection."
    fi

    local idx=$(( selection - 1 ))
    local selected_name="${names[$idx]}"
    local selected_path="${paths[$idx]}"
    local needs_sudo="${sudos[$idx]}"

    echo ""

    # ── Arguments ─────────────────────────────────────────────────────────────
    local user_args=""
    echo -ne "  ${CYAN}?${RESET}  Arguments ${DIM}(blank for defaults)${RESET}: "
    read -r user_args < /dev/tty
    echo ""

    # ── Execute ───────────────────────────────────────────────────────────────
    chmod +x "$selected_path"
    ok "Launching ${BOLD}${selected_name}${RESET}"
    echo ""

    if [[ "$needs_sudo" == "true" ]]; then
        warn "This script requires ${BOLD}sudo${RESET} access."
        echo ""
        # shellcheck disable=SC2086
        sudo bash "$selected_path" $user_args
    else
        # shellcheck disable=SC2086
        bash "$selected_path" $user_args
    fi
}

main "$@"
