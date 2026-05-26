#!/usr/bin/env bash
# Local dev server — auto-downloads miniserve on first run.
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}!${RESET}  $*"; }
die()  { echo -e "\n  ${RED}✖${RESET}  $*" >&2; exit 1; }

BIN_DIR=".bin"
MINISERVE="$BIN_DIR/miniserve"

if [[ ! -x "$MINISERVE" ]]; then
    mkdir -p "$BIN_DIR"
    echo -e "  ${CYAN}⬇${RESET}  Downloading miniserve..."
    ARCH=$(uname -m)
    [[ "$ARCH" == "arm64" ]] && PATTERN="aarch64-apple-darwin" || PATTERN="x86_64-apple-darwin"
    URL=$(curl -sL "https://api.github.com/repos/svenstaro/miniserve/releases/latest" \
        | grep -o "\"browser_download_url\": \"[^\"]*${PATTERN}\"" \
        | head -1 | cut -d'"' -f4)
    [[ -z "$URL" ]] && die "Failed to find download URL."
    curl -sL "$URL" -o "$MINISERVE"
    chmod +x "$MINISERVE"
    ok "Cached in ${DIM}${BIN_DIR}/${RESET}"
fi

ok "Serving at ${BOLD}http://localhost:3000${RESET}"
"$MINISERVE" --index index.html -p 3000 .
