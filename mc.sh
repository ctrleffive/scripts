#!/bin/bash
# ============================================================
#  mc.sh — Mac Cleaner (Interactive & Dry-Run)
#
#  Usage:
#    sudo ./mc.sh          # Full system scan (Dry-Run)
#    sudo ./mc.sh --clean  # Interactive Cleanup Mode
# ============================================================

set -uo pipefail

# ── Flags ────────────────────────────────────────────────────
LIVE_RUN=false
for arg in "$@"; do
    [[ "$arg" == "--clean" ]] && LIVE_RUN=true
done

# ── Colours & Icons ──────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'

ICON_Q="${YELLOW}[?]${RESET}"
ICON_OK="${GREEN}[✓]${RESET}"
ICON_WARN="${RED}[!]${RESET}"
ICON_SKIP="${DIM}[-]${RESET}"

# ── Root check ───────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✖${RESET}  Please run with sudo: sudo $0"
    exit 1
fi

CURRENT_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
HOME_DIR=$(eval echo "~$CURRENT_USER")

# ── Size helpers ─────────────────────────────────────────────
get_bytes() {
    local total=0
    shopt -s nullglob
    for p in $1; do
        [[ -e "$p" ]] || continue
        local b
        b=$(du -sk "$p" 2>/dev/null | awk '{printf "%d", $1*1024}')
        total=$(( total + b ))
    done
    shopt -u nullglob
    echo $total
}

human_bytes() {
    local b=$1
    if   (( b >= 1073741824 )); then awk "BEGIN {printf \"%.1f GB\", $b/1073741824}"
    elif (( b >= 1048576 ))   ; then awk "BEGIN {printf \"%.1f MB\", $b/1048576}"
    elif (( b >= 1024 ))      ; then awk "BEGIN {printf \"%.1f KB\", $b/1024}"
    else echo "${b} B"; fi
}

# ── Spinner ──────────────────────────────────────────────────
SPINNER_PID=""
spinner_start() {
    local label="$1"
    ( local f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'); local i=0
      while true; do
          printf "\r  ${CYAN}${f[$((i%10))]}${RESET}  %s" "$label"
          sleep 0.08; i=$(( i+1 ))
      done ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null || true
}
spinner_stop() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
    printf "\r\033[K"
}

SECTION_TASKS=()

flush_tasks() {
    (( ${#SECTION_TASKS[@]} == 0 )) && return

    local sorted_tasks
    sorted_tasks=$(printf "%s\n" "${SECTION_TASKS[@]}" | sort -nr -t'|' -k1,1)

    local old_ifs="$IFS"
    IFS=$'\n'
    set -f
    local tasks_arr=($sorted_tasks)
    set +f
    IFS="$old_ifs"

    for task in "${tasks_arr[@]}"; do
        [[ -z "$task" ]] && continue
        
        local task_bytes="${task%%|*}"
        local remainder="${task#*|}"
        
        local label="${remainder%%|*}"
        remainder="${remainder#*|}"
        
        local native_cmd="${remainder%%|*}"
        local actual_paths="${remainder#*|}"

        local size_str
        size_str=$(human_bytes "$task_bytes")

        if ! $LIVE_RUN; then
            local cmd_hint=""
            [[ -n "$native_cmd" ]] && cmd_hint="  ${DIM}— $native_cmd${RESET}"
            printf "  %-10s  %s%b\n" "$size_str" "$label" "$cmd_hint"
        else
            local prompt_cmd=""
            [[ -n "$native_cmd" ]] && prompt_cmd=" ${DIM}[run: $native_cmd]${RESET}"
            
            printf "  ${ICON_Q}  Clean %s (%s)?%b [y/N] " "$label" "$size_str" "$prompt_cmd"
            read -rp "" confirm </dev/tty

            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                spinner_start "Cleaning $label..."
                if [[ -n "$native_cmd" ]]; then
                    if [[ "$native_cmd" == brew* || "$native_cmd" == npm* || "$native_cmd" == pnpm* || "$native_cmd" == pod* ]]; then
                        sudo -u "$CURRENT_USER" bash -c "$native_cmd" &>/dev/null || true
                    else
                        eval "$native_cmd" &>/dev/null || true
                    fi
                else
                    eval "rm -rf $actual_paths" 2>/dev/null || true
                fi
                spinner_stop
                printf "  ${ICON_OK}  Cleaned %s ${DIM}(%s)${RESET}\n" "$label" "$size_str"
                TOTAL_CLEANED=$(( TOTAL_CLEANED + task_bytes ))
            else
                printf "  ${ICON_SKIP}  Skipped %s\n" "$label"
            fi
        fi
    done

    SECTION_TASKS=()
}

section() { 
    flush_tasks
    echo ""
    echo -e "${BOLD}  $1${RESET}"
    echo -e "  ${DIM}$(printf '─%.0s' {1..44})${RESET}" 
}

# ── Totals ───────────────────────────────────────────────────
TOTAL_SCANNED=0
TOTAL_CLEANED=0

# ── Task runner ──────────────────────────────────────────────
# run_task "Label" "native command (or empty)" "path1" "path2" ...
run_task() {
    local label="$1"
    local native_cmd="$2"
    shift 2
    local paths=("$@")

    local task_bytes=0
    local found=false
    local actual_paths=""

    spinner_start "Scanning $label..."
    shopt -s nullglob
    for p in "${paths[@]}"; do
        for expanded in $p; do
            [[ -e "$expanded" ]] || continue
            found=true
            actual_paths="$actual_paths \"$expanded\""
            local b
            b=$(get_bytes "$expanded")
            task_bytes=$(( task_bytes + b ))
        done
    done
    shopt -u nullglob
    spinner_stop

    (( task_bytes == 0 )) && return

    TOTAL_SCANNED=$(( TOTAL_SCANNED + task_bytes ))
    SECTION_TASKS+=("${task_bytes}|${label}|${native_cmd}|${actual_paths}")
}

# ── Special Docker/Time Machine Tasks ────────────────────────
run_docker_task() {
    spinner_start "Scanning Docker..."
    local b=$(get_bytes "${HOME_DIR}/Library/Containers/com.docker.docker/Data/")
    spinner_stop
    if (( b > 0 )); then
        TOTAL_SCANNED=$(( TOTAL_SCANNED + b ))
        SECTION_TASKS+=("${b}|Docker Data|docker system prune -f|")
    fi
}

run_tm_task() {
    spinner_start "Checking Time Machine snapshots..."
    local TM_LIST=$(tmutil listlocalsnapshots / 2>/dev/null || true)
    local TM_COUNT=$(echo "$TM_LIST" | grep -c 'com.apple' 2>/dev/null || echo 0)
    local TM_BYTES=$(get_bytes "/.MobileBackups")
    spinner_stop
    if (( TM_COUNT > 0 )); then
        TOTAL_SCANNED=$(( TOTAL_SCANNED + TM_BYTES ))
        SECTION_TASKS+=("${TM_BYTES}|Time Machine snapshots ($TM_COUNT)|tmutil deletelocalsnapshots /|")
    fi
}

# ── Header ───────────────────────────────────────────────────
clear
echo ""
echo -e "${CYAN}"
cat << 'EOF'
  ▗▖  ▗▖ ▗▄▖  ▗▄▄▖     ▗▄▄▖▗▖   ▗▄▄▄▖ ▗▄▖ ▗▖  ▗▖▗▄▄▄▖▗▄▄▖ 
  ▐▛▚▞▜▌▐▌ ▐▌▐▌       ▐▌   ▐▌   ▐▌   ▐▌ ▐▌▐▛▚▖▐▌▐▌   ▐▌ ▐▌
  ▐▌  ▐▌▐▛▀▜▌▐▌       ▐▌   ▐▌   ▐▛▀▀▘▐▛▀▜▌▐▌ ▝▜▌▐▛▀▀▘▐▛▀▚▖
  ▐▌  ▐▌▐▌ ▐▌▝▚▄▄▖    ▝▚▄▄▖▐▙▄▄▖▐▙▄▄▖▐▌ ▐▌▐▌  ▐▌▐▙▄▄▖▐▌ ▐▌  
EOF
echo -e "${RESET}"
FREE_BEFORE=$(df -h / | awk 'NR==2 {print $4}')
echo -e "  ${DIM}Free space currently: $FREE_BEFORE${RESET}"
if ! $LIVE_RUN; then
    echo -e "  ${CYAN}Running in Dry-Run mode. No files will be deleted.${RESET}"
else
    echo -e "  ${YELLOW}Interactive Cleanup Mode active. You will be prompted before deletions.${RESET}"
fi
echo ""

# ════════════════════════════════════════════════════════════
section "System & User Caches"
# ════════════════════════════════════════════════════════════
run_task "User Caches" "" "${HOME_DIR}/Library/Caches/"
run_task "System Caches" "" "/Library/Caches/" "/System/Library/Caches/com.apple.kext.caches/"

# ════════════════════════════════════════════════════════════
section "Logs & Temp Files"
# ════════════════════════════════════════════════════════════
run_task "Application Logs" "" "${HOME_DIR}/Library/Logs/" "/Library/Logs/" "/var/log/asl/"
run_task "Temporary Files" "" "/private/tmp/" "/private/var/tmp/" "${TMPDIR:-/tmp}/"
run_task "Browser Caches" "" "${HOME_DIR}/Library/Caches/com.apple.Safari/" "${HOME_DIR}/Library/Application Support/Google/Chrome/Default/Cache/" "${HOME_DIR}/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cache/" "${HOME_DIR}/Library/Application Support/Firefox/Profiles/*/cache2/"
run_task "Mail Attachments" "" "${HOME_DIR}/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/" "${HOME_DIR}/Library/Mail/V*/MailData/Attachments/"
run_task "Diagnostic Reports" "" "${HOME_DIR}/Library/Logs/DiagnosticReports/" "/Library/Logs/DiagnosticReports/" "/Library/Logs/CrashReporter/"

# ════════════════════════════════════════════════════════════
section "Xcode & Apple Developer"
# ════════════════════════════════════════════════════════════
run_task "Xcode DerivedData" "" "${HOME_DIR}/Library/Developer/Xcode/DerivedData/"
run_task "iOS Device Support" "" "${HOME_DIR}/Library/Developer/Xcode/iOS DeviceSupport/"
run_task "Xcode Archives" "" "${HOME_DIR}/Library/Developer/Xcode/Archives/"
run_task "Simulator Devices" "xcrun simctl delete unavailable" "${HOME_DIR}/Library/Developer/CoreSimulator/Devices/"

# ════════════════════════════════════════════════════════════
section "Docker & Time Machine"
# ════════════════════════════════════════════════════════════
run_tm_task
run_docker_task

# ════════════════════════════════════════════════════════════
section "Package Manager Caches"
# ════════════════════════════════════════════════════════════
run_task "Homebrew Cache" "brew cleanup" "$(sudo -u "$CURRENT_USER" brew --cache 2>/dev/null || echo /dev/null)"
run_task "npm Cache" "npm cache clean --force" "${HOME_DIR}/.npm/_cacache/"
run_task "pnpm Store" "pnpm store prune" "${HOME_DIR}/Library/pnpm/store/" "${HOME_DIR}/.pnpm-store/"
run_task "Bun Cache" "rm -rf ${HOME_DIR}/Library/Caches/bun" "${HOME_DIR}/Library/Caches/bun/"
run_task "pip Cache" "pip cache purge" "${HOME_DIR}/Library/Caches/pip/"
run_task "Gradle Cache" "" "${HOME_DIR}/.gradle/caches/"
run_task "Go Build Cache" "go clean -cache" "${HOME_DIR}/Library/Caches/go-build/" "${HOME_DIR}/.cache/go-build/"
run_task "Go Module Cache" "go clean -modcache" "${HOME_DIR}/go/pkg/mod/"
run_task "CocoaPods Cache" "pod cache clean --all" "${HOME_DIR}/Library/Caches/CocoaPods/"

# ════════════════════════════════════════════════════════════
section "IDE & Editor Caches"
# ════════════════════════════════════════════════════════════
run_task "JetBrains Caches" "" "${HOME_DIR}/Library/Caches/JetBrains/"
run_task "VS Code Caches" "" "${HOME_DIR}/Library/Application Support/Code/Cache/" "${HOME_DIR}/Library/Application Support/Code/CachedData/"

# ════════════════════════════════════════════════════════════
section "Application Data"
# ════════════════════════════════════════════════════════════
# Destructive action!
run_task "${ICON_WARN} iOS Device Backups" "" "${HOME_DIR}/Library/Application Support/MobileSync/Backup/"

# ════════════════════════════════════════════════════════════
section "Custom Path Scan (Large Files & node_modules)"
# ════════════════════════════════════════════════════════════
echo -e "  ${DIM}Optionally enter a custom path to deep-scan for large files (>200MB)${RESET}"
echo -e "  ${DIM}and heavy node_modules folders. Leave blank to skip.${RESET}"
read -rp "  Custom path (e.g. ~/Projects): " custom_path </dev/tty

if [[ -n "$custom_path" ]]; then
    # Expand tilde
    custom_path="${custom_path/#\~/$HOME_DIR}"
    if [[ -d "$custom_path" ]]; then
        spinner_start "Hunting large items in $custom_path..."
        
        # Find node_modules
        NM_LINES=()
        while IFS= read -r dir; do
            b=$(du -sk "$dir" 2>/dev/null | awk '{printf "%d", $1*1024}')
            (( b < 52428800 )) && continue   # skip < 50 MB
            short="${dir/#$HOME_DIR/~}"
            NM_LINES+=("${b}|${short}|${dir}")
        done < <(find "$custom_path" -name node_modules -type d -prune -not -path "*/\.*" 2>/dev/null)
        
        # Find Large files
        LF_LINES=()
        while IFS= read -r f; do
            b=$(stat -f%z "$f" 2>/dev/null || echo 0)
            short="${f/#$HOME_DIR/~}"
            LF_LINES+=("${b}|${short}|${f}")
        done < <(find "$custom_path" -type f -size +200M -not -path "*/node_modules/*" 2>/dev/null)
        
        spinner_stop
        
        # Display & Prompt for Node Modules
        if (( ${#NM_LINES[@]} > 0 )); then
            echo -e "\n  ${BOLD}Heavy node_modules found:${RESET}"
            local sorted_nm
            sorted_nm=$(printf "%s\n" "${NM_LINES[@]}" | sort -nr -t'|' -k1,1)
            
            local old_ifs="$IFS"
            IFS=$'\n'
            set -f
            local nm_arr=($sorted_nm)
            set +f
            IFS="$old_ifs"
            
            for entry in "${nm_arr[@]}"; do
                [[ -z "$entry" ]] && continue
                local b="${entry%%|*}"
                local remainder="${entry#*|}"
                local short="${remainder%%|*}"
                local dir="${remainder#*|}"
                size_str=$(human_bytes "$b")
                TOTAL_SCANNED=$(( TOTAL_SCANNED + b ))
                if ! $LIVE_RUN; then
                    printf "  %-10s  %s\n" "$size_str" "$short"
                else
                    printf "  ${ICON_Q}  Delete %s (%s)? [y/N] " "$short" "$size_str"
                    read -rp "" confirm </dev/tty
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        rm -rf "$dir" 2>/dev/null || true
                        printf "  ${ICON_OK}  Deleted %s\n" "$short"
                        TOTAL_CLEANED=$(( TOTAL_CLEANED + b ))
                    else
                        printf "  ${ICON_SKIP}  Skipped %s\n" "$short"
                    fi
                fi
            done
        fi
        
        # Display & Prompt for Large Files
        if (( ${#LF_LINES[@]} > 0 )); then
            echo -e "\n  ${BOLD}Large files found (>200MB):${RESET}"
            local sorted_lf
            sorted_lf=$(printf "%s\n" "${LF_LINES[@]}" | sort -nr -t'|' -k1,1)
            
            local old_ifs="$IFS"
            IFS=$'\n'
            set -f
            local lf_arr=($sorted_lf)
            set +f
            IFS="$old_ifs"
            
            for entry in "${lf_arr[@]}"; do
                [[ -z "$entry" ]] && continue
                local b="${entry%%|*}"
                local remainder="${entry#*|}"
                local short="${remainder%%|*}"
                local f="${remainder#*|}"
                size_str=$(human_bytes "$b")
                TOTAL_SCANNED=$(( TOTAL_SCANNED + b ))
                if ! $LIVE_RUN; then
                    printf "  %-10s  %s\n" "$size_str" "$short"
                else
                    printf "  ${ICON_Q}  Delete %s (%s)? ${ICON_WARN} [y/N] " "$short" "$size_str"
                    read -rp "" confirm </dev/tty
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        rm -f "$f" 2>/dev/null || true
                        printf "  ${ICON_OK}  Deleted %s\n" "$short"
                        TOTAL_CLEANED=$(( TOTAL_CLEANED + b ))
                    else
                        printf "  ${ICON_SKIP}  Skipped %s\n" "$short"
                    fi
                fi
            done
        fi
        
        if (( ${#NM_LINES[@]} == 0 && ${#LF_LINES[@]} == 0 )); then
            echo -e "  ${DIM}No heavy items found in $custom_path${RESET}"
        fi
    else
        echo -e "  ${RED}Invalid directory: $custom_path${RESET}"
    fi
else
    echo -e "  ${DIM}Skipped custom path scan.${RESET}"
fi

# ════════════════════════════════════════════════════════════
section "Summary"
# ════════════════════════════════════════════════════════════
echo ""
if ! $LIVE_RUN; then
    echo -e "  ${BOLD}Scannable junk found: ${RED}$(human_bytes $TOTAL_SCANNED)${RESET}"
    echo -e "  ${DIM}Run with \`--clean\` to start the interactive cleanup process.${RESET}"
else
    FREE_AFTER=$(df -h / | awk 'NR==2 {print $4}')
    echo -e "  ${BOLD}${GREEN}Cleanup Complete.${RESET} Freed $(human_bytes $TOTAL_CLEANED)."
    echo -e "  ${DIM}Free space: $FREE_BEFORE → $FREE_AFTER${RESET}"
fi
echo ""
