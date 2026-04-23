#!/usr/bin/env bash
# Holler uninstaller — removes the venv, systemd user service, and desktop entry.
#
# Usage:
#   ./uninstall.sh              # remove venv + service + desktop entry (keeps config.json)
#   ./uninstall.sh --purge      # also remove config.json

set -euo pipefail

PURGE=0
for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        -h|--help)
            sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown flag: $arg" >&2
            exit 2
            ;;
    esac
done

bold=$(tput bold 2>/dev/null || true)
green=$(tput setaf 2 2>/dev/null || true)
yellow=$(tput setaf 3 2>/dev/null || true)
blue=$(tput setaf 4 2>/dev/null || true)
reset=$(tput sgr0 2>/dev/null || true)

step() { echo; echo "${bold}${blue}==>${reset} ${bold}$*${reset}"; }
ok()   { echo "    ${green}✓${reset} $*"; }
skip() { echo "    ${yellow}-${reset} $*"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# ---------- systemd service ----------
step "Removing systemd --user service"

SERVICE_FILE="$HOME/.config/systemd/user/holler.service"
if [[ -f "$SERVICE_FILE" ]]; then
    systemctl --user stop holler.service 2>/dev/null || true
    systemctl --user disable holler.service 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload 2>/dev/null || true
    ok "Removed $SERVICE_FILE"
else
    skip "No systemd service found"
fi

# ---------- desktop entry ----------
step "Removing desktop entry"

DESKTOP_FILE="$HOME/.local/share/applications/holler.desktop"
if [[ -f "$DESKTOP_FILE" ]]; then
    rm -f "$DESKTOP_FILE"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    fi
    ok "Removed $DESKTOP_FILE"
else
    skip "No desktop entry found"
fi

# ---------- venv ----------
step "Removing Python venv"

VENV_DIR="$REPO_DIR/.env"
if [[ -d "$VENV_DIR" ]]; then
    rm -rf "$VENV_DIR"
    ok "Removed $VENV_DIR"
else
    skip "No venv found"
fi

# ---------- caches ----------
step "Cleaning caches"

find "$REPO_DIR" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find "$REPO_DIR" -type d -name .ruff_cache -exec rm -rf {} + 2>/dev/null || true
find "$REPO_DIR" -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
rm -rf "$REPO_DIR"/*.egg-info "$REPO_DIR/build" "$REPO_DIR/dist"
ok "Cleaned"

# ---------- config ----------
if [[ $PURGE -eq 1 ]]; then
    step "Purging config.json (--purge)"
    if [[ -f "$REPO_DIR/config.json" ]]; then
        rm -f "$REPO_DIR/config.json"
        ok "Removed config.json (API keys erased)"
    else
        skip "No config.json to remove"
    fi
fi

# ---------- done ----------
echo
echo "${green}${bold}✓ Uninstall complete${reset}"
echo
if [[ $PURGE -eq 0 && -f "$REPO_DIR/config.json" ]]; then
    echo "    ${yellow}Note:${reset} config.json (with your API keys) was preserved."
    echo "    Pass ${bold}--purge${reset} to remove it too."
fi
echo
echo "    System packages (libportaudio2, wl-clipboard, dotool, etc.)"
echo "    and group memberships (input, uinput) were NOT touched —"
echo "    remove those manually if you want a full cleanup."
echo
