#!/usr/bin/env bash
# =============================================================================
#  ram.sh
#  Backs up ~/Downloads, mounts a RAM disk, and symlinks Downloads → RAM disk.
#
#  Usage:
#    ./ram.sh            # uses default 10 GB
#    ./ram.sh 4          # 4 GB
#    ./ram.sh 4g         # 4 GB  (g/G suffix accepted)
#    ./ram.sh 512m       # 512 MB (m/M suffix accepted)
#
#  Supported OS:  macOS · Linux (tmpfs)
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ── Icons ─────────────────────────────────────────────────────────────────────
ok()   { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}!${RESET}  $*"; }
die()  { echo -e "  ${RED}!${RESET}  $*" >&2; exit 1; }

ask() {
    # ask <varname> <prompt>
    local _var="$1"; shift
    echo -ne "  ${CYAN}?${RESET}  $* ${DIM}[y/N]${RESET}: "
    read -r "$_var" < /dev/tty
}

banner() { echo -e "\n${BOLD}$*${RESET}\n"; }

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
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
    printf "\r\033[K"
}

# ── Parse size ────────────────────────────────────────────────────────────────
#   Accepts: 10 | 10g | 10G | 512m | 512M  (bare number = GB)
parse_size() {
    local raw="${1:-10}"
    local lower
    lower=$(echo "$raw" | tr '[:upper:]' '[:lower:]')

    if [[ "$lower" =~ ^([0-9]+)([gm]?)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        case "$unit" in
            g|"") SIZE_BYTES=$(( num * 1024 * 1024 * 1024 )); SIZE_HUMAN="${num} GB" ;;
            m)    SIZE_BYTES=$(( num * 1024 * 1024 ));        SIZE_HUMAN="${num} MB" ;;
        esac
    else
        die "Invalid size '${raw}'.  Examples: 10  4g  512m"
    fi
}

# ── Detect OS ─────────────────────────────────────────────────────────────────
detect_os() {
    case "$(uname -s)" in
        Darwin) OS="macos" ;;
        Linux)  OS="linux" ;;
        *)      die "Unsupported OS: $(uname -s).  Only macOS and Linux are supported." ;;
    esac
    ok "OS detected: ${BOLD}${OS}${RESET}"
}

# ── RAM headroom check ────────────────────────────────────────────────────────
check_ram() {
    local available_bytes

    if [[ "$OS" == "macos" ]]; then
        available_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    else
        available_bytes=$(awk '/MemAvailable/ {print $2 * 1024}' /proc/meminfo 2>/dev/null || echo 0)
    fi

    if (( available_bytes > 0 && SIZE_BYTES > available_bytes * 80 / 100 )); then
        warn "${BOLD}${SIZE_HUMAN}${RESET} exceeds 80 % of available RAM — system may become unstable."
        ask _go "Continue anyway?"
        [[ "$_go" =~ ^[Yy]$ ]] || die "Aborted."
    fi
}

# ── Backup Downloads ──────────────────────────────────────────────────────────
backup_downloads() {
    local downloads="${HOME}/Downloads"

    # ── Already a symlink? ────────────────────────────────────────────────────
    # This means the script was run before. Don't touch any data — just remove
    # the old symlink so we can replace it with the new one.
    if [[ -L "$downloads" ]]; then
        warn "~/Downloads is already a symlink → $(readlink "$downloads")"
        ask _go "Remove it and continue?"
        [[ "$_go" =~ ^[Yy]$ ]] || die "Aborted."
        rm -- "$downloads"
        ok "Existing symlink removed"
        BACKUP_PATH=""
        return
    fi

    # ── No real directory — nothing to back up ────────────────────────────────
    if [[ ! -d "$downloads" ]]; then
        ok "No existing ~/Downloads — nothing to back up"
        BACKUP_PATH=""
        return
    fi

    # ── Real directory: find next free backup name ────────────────────────────
    # NOTE: avoid (( n++ )) under set -e — arithmetic expressions that evaluate
    # to 0 return exit code 1 in bash, which set -e treats as a failure.
    # Use n=$(( n + 1 )) instead — it is an assignment, exit code is always 0.
    local n=1
    while [[ -d "${HOME}/Downloads Backup - ${n}" ]]; do
        n=$(( n + 1 ))
    done
    BACKUP_NAME="Downloads Backup - ${n}"
    BACKUP_PATH="${HOME}/${BACKUP_NAME}"

    # Hard guard: refuse if the target somehow already exists as a file/other
    if [[ -e "$BACKUP_PATH" ]]; then
        die "Backup target already exists: ${BACKUP_PATH}\n     Remove it manually and re-run."
    fi

    spinner_start "Backing up ~/Downloads…"
    mv -- "$downloads" "$BACKUP_PATH" \
        || { spinner_stop; die "Could not rename ~/Downloads — check permissions."; }
    spinner_stop

    # Verify both sides of the rename before proceeding — never assume mv worked
    if [[ ! -d "$BACKUP_PATH" ]]; then
        die "Backup target missing after rename — something went wrong. Aborting."
    fi
    if [[ -e "$downloads" ]]; then
        die "~/Downloads still exists after rename — aborting to avoid data loss."
    fi

    ok "Backed up to ${BOLD}~/${BACKUP_NAME}${RESET}"
}

# ── macOS: hdiutil RAM disk ───────────────────────────────────────────────────
create_ramdisk_macos() {
    local sectors=$(( SIZE_BYTES / 512 ))

    spinner_start "Attaching ${SIZE_HUMAN} RAM disk…"
    local dev
    dev=$(hdiutil attach -nomount "ram://${sectors}" 2>/dev/null) \
        || { spinner_stop; die "hdiutil failed — not enough free RAM?"; }
    dev=$(echo "$dev" | tr -d '[:space:]')
    spinner_stop
    ok "RAM device attached: ${DIM}${dev}${RESET}"

    spinner_start "Formatting ${dev} as HFS+…"
    diskutil eraseDisk JHFS+ RAMDisk "${dev}" >/dev/null \
        || { spinner_stop; die "diskutil format failed on ${dev}."; }
    spinner_stop
    ok "Formatted and mounted at ${BOLD}/Volumes/RAMDisk${RESET}"

    RAMDISK_MOUNT="/Volumes/RAMDisk"
}

# ── Linux: tmpfs ──────────────────────────────────────────────────────────────
create_ramdisk_linux() {
    RAMDISK_MOUNT="/mnt/ramdisk_downloads"

    if mountpoint -q "$RAMDISK_MOUNT" 2>/dev/null; then
        warn "${RAMDISK_MOUNT} is already mounted."
        ask _go "Unmount and remount?"
        if [[ "$_go" =~ ^[Yy]$ ]]; then
            sudo umount "$RAMDISK_MOUNT" || die "Failed to unmount existing RAM disk."
        else
            die "Aborted — clean up ${RAMDISK_MOUNT} manually and re-run."
        fi
    fi

    spinner_start "Mounting ${SIZE_HUMAN} tmpfs at ${RAMDISK_MOUNT}…"
    sudo mkdir -p "$RAMDISK_MOUNT"
    sudo mount -t tmpfs -o "size=${SIZE_BYTES}" tmpfs "$RAMDISK_MOUNT" \
        || { spinner_stop; die "mount tmpfs failed — do you have sudo rights?"; }
    sudo chown "$(id -u):$(id -g)" "$RAMDISK_MOUNT"
    spinner_stop
    ok "tmpfs mounted at ${BOLD}${RAMDISK_MOUNT}${RESET}"
}

# ── Symlink ───────────────────────────────────────────────────────────────────
create_symlink() {
    local downloads="${HOME}/Downloads"

    # Final sanity check — Downloads must not exist at this point
    if [[ -e "$downloads" || -L "$downloads" ]]; then
        die "~/Downloads still exists before symlinking — aborting to prevent overwrite."
    fi

    ln -s "$RAMDISK_MOUNT" "$downloads" \
        || die "Failed to create symlink."
    ok "Symlink created: ${BOLD}~/Downloads${RESET} → ${RAMDISK_MOUNT}"
}

# ── Post-setup warnings ───────────────────────────────────────────────────────
print_warnings() {
    echo ""
    echo -e "  ${DIM}────────────────────────────────────────────${RESET}"
    warn "${BOLD}RAM is volatile${RESET} — everything in ~/Downloads is lost on reboot."
    warn "Disk is capped at ${BOLD}${SIZE_HUMAN}${RESET}; larger downloads will fail."
    if [[ "$OS" == "linux" ]]; then
        warn "Mount won't survive reboot.  For persistence, add to /etc/fstab:"
        echo -e "       ${DIM}tmpfs  ${RAMDISK_MOUNT}  tmpfs  defaults,size=${SIZE_BYTES}  0  0${RESET}"
    else
        warn "/Volumes/RAMDisk disappears on reboot — ~/Downloads will be a dangling link."
    fi
    if [[ -n "${BACKUP_PATH:-}" ]]; then
        warn "To restore your original folder:"
        echo -e "       ${DIM}rm ~/Downloads${RESET}"
        echo -e "       ${DIM}mv \"${BACKUP_PATH}\" ~/Downloads${RESET}"
    fi
    echo -e "  ${DIM}────────────────────────────────────────────${RESET}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    banner "  RAM Disk Downloads Setup"

    parse_size "${1:-10}"
    detect_os
    check_ram

    echo -e "  ${DIM}Will back up ~/Downloads, mount a ${SIZE_HUMAN} RAM disk, and symlink.${RESET}"
    echo ""
    ask _go "Proceed?"
    [[ "$_go" =~ ^[Yy]$ ]] || die "Aborted."
    echo ""

    backup_downloads

    if [[ "$OS" == "macos" ]]; then
        create_ramdisk_macos
    else
        create_ramdisk_linux
    fi

    create_symlink
    print_warnings

    ok "${BOLD}Done.${RESET}  ~/Downloads is now a ${SIZE_HUMAN} RAM disk."
}

main "$@"