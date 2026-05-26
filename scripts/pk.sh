#!/usr/bin/env bash
# @name Port Killer
# @desc Find and kill processes listening on TCP ports
# @sudo false
# @os macos,linux
# =============================================================================
#  pk.sh — Port Killer
#
#  Usage:
#    ./pk.sh          # Interactive mode — scan and pick processes to kill
#    ./pk.sh 3000     # Kill whatever is on port 3000 directly
# =============================================================================

set -uo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ── Helpers ──────────────────────────────────────────────────────────────────
ok()   { echo -e " ${GREEN}✔${RESET} $*"; }
warn() { echo -e " ${YELLOW}!${RESET} $*"; }
die()  { echo -e "\n ${RED}✖${RESET} $*" >&2; exit 1; }

# ── Detect OS ────────────────────────────────────────────────────────────────
OS=""
case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux)  OS="linux" ;;
    *)      die "Unsupported OS: $(uname -s)" ;;
esac

# ── Scan listening ports ─────────────────────────────────────────────────────
# Returns lines of: PORT|PID|PROCESS_NAME
scan_ports() {
    if [[ "$OS" == "macos" ]]; then
        lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | awk 'NR>1 {
            # Extract port from the NAME column (e.g. *:3000 or 127.0.0.1:8080)
            split($9, a, ":")
            port = a[length(a)]
            pid = $2
            proc = $1
            # Deduplicate by port+pid
            key = port "|" pid
            if (!(key in seen)) {
                seen[key] = 1
                print port "|" pid "|" proc
            }
        }' | sort -t'|' -k1,1n
    else
        ss -tlnp 2>/dev/null | awk 'NR>1 {
            # Extract port from Local Address (e.g. 0.0.0.0:3000 or [::]:8080)
            split($4, a, ":")
            port = a[length(a)]
            # Extract pid and process from users field
            match($0, /pid=([0-9]+)/, m)
            pid = m[1]
            match($0, /\("([^"]+)"/, m2)
            proc = m2[1]
            if (pid && port) {
                key = port "|" pid
                if (!(key in seen)) {
                    seen[key] = 1
                    print port "|" pid "|" proc
                }
            }
        }' | sort -t'|' -k1,1n
    fi
}

# ── Kill a process by PID ────────────────────────────────────────────────────
kill_pid() {
    local pid="$1"
    local proc="$2"
    local port="$3"

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        sleep 0.3
        if kill -0 "$pid" 2>/dev/null; then
            warn "Process ${BOLD}${proc}${RESET} (PID ${pid}) didn't stop, sending SIGKILL..."
            kill -9 "$pid" 2>/dev/null || true
            sleep 0.2
        fi

        if kill -0 "$pid" 2>/dev/null; then
            warn "Could not kill PID ${pid}. Try: ${DIM}sudo kill -9 ${pid}${RESET}"
        else
            ok "Killed ${BOLD}${proc}${RESET} (PID ${pid}) on port ${CYAN}${port}${RESET}"
        fi
    else
        warn "PID ${pid} is no longer running."
    fi
}

# ── Direct mode: kill by port number ─────────────────────────────────────────
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    target_port="$1"
    echo ""

    matches=()
    while IFS='|' read -r port pid proc; do
        [[ "$port" == "$target_port" ]] && matches+=("${port}|${pid}|${proc}")
    done < <(scan_ports)

    if (( ${#matches[@]} == 0 )); then
        warn "Nothing listening on port ${BOLD}${target_port}${RESET}."
        exit 0
    fi

    for entry in "${matches[@]}"; do
        IFS='|' read -r port pid proc <<< "$entry"
        kill_pid "$pid" "$proc" "$port"
    done
    echo ""
    exit 0
fi

# ── Interactive mode ─────────────────────────────────────────────────────────
echo ""
echo -e " ${BOLD}Scanning listening ports...${RESET}"
echo ""

lines=()
while IFS= read -r line; do
    lines+=("$line")
done < <(scan_ports)

if (( ${#lines[@]} == 0 )); then
    ok "No processes listening on any TCP ports."
    echo ""
    exit 0
fi

# ── Display table ────────────────────────────────────────────────────────────
printf " ${DIM}%-4s  %-7s  %-8s  %s${RESET}\n" "#" "PORT" "PID" "PROCESS"
printf " ${DIM}%-4s  %-7s  %-8s  %s${RESET}\n" "───" "──────" "───────" "────────"

for i in "${!lines[@]}"; do
    IFS='|' read -r port pid proc <<< "${lines[$i]}"
    num=$(( i + 1 ))
    printf " ${CYAN}${BOLD}%-4s${RESET}  %-7s  ${DIM}%-8s${RESET}  %s\n" "$num" "$port" "$pid" "$proc"
done

echo ""
echo -e " ${DIM}Ctrl+C to quit${RESET}"
echo ""

# ── Selection loop ───────────────────────────────────────────────────────────
while true; do
    echo -ne " ${CYAN}?${RESET}  Kill which? ${DIM}(number, port, or 'all')${RESET}: "
    read -r input < /dev/tty || input=""

    [[ -z "$input" ]] && { printf "\033[1A\033[K"; continue; }

    if [[ "$input" == "all" ]]; then
        echo ""
        for entry in "${lines[@]}"; do
            IFS='|' read -r port pid proc <<< "$entry"
            kill_pid "$pid" "$proc" "$port"
        done
        echo ""
        exit 0
    fi

    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        printf "\033[1A\033[K"
        continue
    fi

    # Check if input matches a menu number
    if (( input >= 1 && input <= ${#lines[@]} )); then
        idx=$(( input - 1 ))
        IFS='|' read -r port pid proc <<< "${lines[$idx]}"
        echo ""
        kill_pid "$pid" "$proc" "$port"
        echo ""
        exit 0
    fi

    # Otherwise treat as a port number
    found=false
    echo ""
    for entry in "${lines[@]}"; do
        IFS='|' read -r port pid proc <<< "$entry"
        if [[ "$port" == "$input" ]]; then
            kill_pid "$pid" "$proc" "$port"
            found=true
        fi
    done

    if ! $found; then
        warn "No match for '${input}'."
    fi
    echo ""
    exit 0
done
