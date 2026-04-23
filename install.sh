#!/usr/bin/env bash
# Holler installer — one-shot setup for Pop!_OS, Ubuntu, Fedora, and Arch.
#
# Usage:
#   ./install.sh                 # full interactive install
#   ./install.sh --no-service    # skip systemd user service
#   ./install.sh --no-dotool     # skip dotool build (Wayland users only)
#   ./install.sh --yes           # assume yes to all prompts
#
# What it does:
#   1. Detects distro + session (X11/Wayland) + desktop environment
#   2. Installs OS packages via apt/dnf/pacman
#   3. Builds dotool from source if on Wayland and dotool isn't present
#   4. Adds $USER to the 'input' group if needed (Wayland)
#   5. Creates a Python venv and installs Holler
#   6. Writes config.json from the example
#   7. Installs a .desktop entry and optionally a systemd --user service

set -euo pipefail

# ---------- CLI flags ----------
ASSUME_YES=0
SKIP_SERVICE=0
SKIP_DOTOOL=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=1 ;;
        --no-service) SKIP_SERVICE=1 ;;
        --no-dotool) SKIP_DOTOOL=1 ;;
        -h|--help)
            sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown flag: $arg" >&2
            exit 2
            ;;
    esac
done

# ---------- pretty output ----------
bold=$(tput bold 2>/dev/null || true)
dim=$(tput dim 2>/dev/null || true)
red=$(tput setaf 1 2>/dev/null || true)
green=$(tput setaf 2 2>/dev/null || true)
yellow=$(tput setaf 3 2>/dev/null || true)
blue=$(tput setaf 4 2>/dev/null || true)
reset=$(tput sgr0 2>/dev/null || true)

step()  { echo; echo "${bold}${blue}==>${reset} ${bold}$*${reset}"; }
info()  { echo "    $*"; }
ok()    { echo "    ${green}✓${reset} $*"; }
warn()  { echo "    ${yellow}!${reset} $*"; }
die()   { echo "${red}✗ $*${reset}" >&2; exit 1; }

confirm() {
    local prompt="$1"
    if [[ $ASSUME_YES -eq 1 ]]; then
        info "$prompt ${dim}[auto-yes]${reset}"
        return 0
    fi
    read -r -p "    $prompt [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

# ---------- locate repo ----------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# ---------- detect distro ----------
step "Detecting system"

if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect distro: /etc/os-release missing"
fi
# shellcheck disable=SC1091
. /etc/os-release
DISTRO_ID="${ID:-unknown}"
DISTRO_LIKE="${ID_LIKE:-}"
info "Distro: ${bold}${PRETTY_NAME:-$DISTRO_ID}${reset}"

case "$DISTRO_ID $DISTRO_LIKE" in
    *debian*|*ubuntu*|*pop*) PKG=apt ;;
    *fedora*|*rhel*)         PKG=dnf ;;
    *arch*|*manjaro*)        PKG=pacman ;;
    *)
        warn "Unknown package manager — you'll need to install system deps manually."
        PKG=unknown
        ;;
esac
info "Package manager: ${bold}$PKG${reset}"

# ---------- detect session ----------
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
DESKTOP="${XDG_CURRENT_DESKTOP:-unknown}"
info "Session: ${bold}$SESSION_TYPE${reset}  Desktop: ${bold}$DESKTOP${reset}"

IS_WAYLAND=0
[[ "$SESSION_TYPE" == "wayland" ]] && IS_WAYLAND=1

IS_COSMIC=0
[[ "${DESKTOP,,}" == *cosmic* ]] && IS_COSMIC=1

# ---------- install system deps ----------
step "Installing system dependencies"

install_apt() {
    local pkgs=(libportaudio2 python3-venv python3-pip build-essential)
    if [[ $IS_WAYLAND -eq 1 ]]; then
        pkgs+=(wl-clipboard)
    else
        pkgs+=(xclip xdotool)
    fi
    info "Packages: ${pkgs[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y "${pkgs[@]}"
}

install_dnf() {
    local pkgs=(portaudio python3-virtualenv python3-pip gcc gcc-c++ make)
    if [[ $IS_WAYLAND -eq 1 ]]; then
        pkgs+=(wl-clipboard)
    else
        pkgs+=(xclip xdotool)
    fi
    info "Packages: ${pkgs[*]}"
    sudo dnf install -y "${pkgs[@]}"
}

install_pacman() {
    local pkgs=(portaudio python python-pip base-devel)
    if [[ $IS_WAYLAND -eq 1 ]]; then
        pkgs+=(wl-clipboard)
    else
        pkgs+=(xclip xdotool)
    fi
    info "Packages: ${pkgs[*]}"
    sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

case "$PKG" in
    apt)    install_apt ;;
    dnf)    install_dnf ;;
    pacman) install_pacman ;;
    unknown)
        warn "Please install manually:"
        warn "  - portaudio (libportaudio2)"
        warn "  - python3-venv, python3-pip, gcc/make"
        if [[ $IS_WAYLAND -eq 1 ]]; then
            warn "  - wl-clipboard"
        else
            warn "  - xclip, xdotool"
        fi
        ;;
esac
ok "System packages installed"

# ---------- dotool (Wayland only) ----------
if [[ $IS_WAYLAND -eq 1 && $SKIP_DOTOOL -eq 0 ]]; then
    step "Checking for dotool (Wayland text injection)"

    if command -v dotool >/dev/null 2>&1; then
        ok "dotool already installed: $(command -v dotool)"
    else
        warn "dotool not found — needed for reliable text injection on Wayland"
        warn "(especially on COSMIC, where wtype is broken)"
        if confirm "Build and install dotool from source?"; then
            tmp=$(mktemp -d)
            trap 'rm -rf "$tmp"' EXIT
            info "Cloning dotool..."
            git clone --depth 1 https://git.sr.ht/~geb/dotool "$tmp/dotool"
            (
                cd "$tmp/dotool"
                ./build.sh
                sudo ./build.sh install
            )
            ok "dotool installed: $(command -v dotool)"
            trap - EXIT
            rm -rf "$tmp"
        else
            warn "Skipped — install dotool manually from https://sr.ht/~geb/dotool/"
        fi
    fi

    # uinput group — dotool writes to /dev/uinput
    if getent group uinput >/dev/null 2>&1; then
        if id -nG "$USER" | tr ' ' '\n' | grep -qx uinput; then
            ok "User already in 'uinput' group"
        elif confirm "Add $USER to 'uinput' group (needed for dotool)?"; then
            sudo usermod -aG uinput "$USER"
            warn "You must log out and back in for this to take effect"
        fi
    fi
fi

# ---------- input group (Wayland hotkeys) ----------
if [[ $IS_WAYLAND -eq 1 ]]; then
    step "Checking 'input' group membership (needed for Wayland hotkeys)"

    if id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
        ok "User already in 'input' group"
    elif confirm "Add $USER to 'input' group?"; then
        sudo usermod -aG input "$USER"
        warn "You must log out and back in for this to take effect"
    else
        warn "Hotkeys won't work on Wayland until $USER is in the 'input' group"
    fi
fi

# ---------- python venv + package ----------
step "Setting up Python environment"

VENV_DIR="$REPO_DIR/.env"
if [[ -d "$VENV_DIR" ]]; then
    ok "Reusing existing venv: $VENV_DIR"
else
    info "Creating venv: $VENV_DIR"
    python3 -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
"$VENV_DIR/bin/python" -m pip install --quiet --upgrade pip
info "Installing Holler (editable)..."
"$VENV_DIR/bin/python" -m pip install --quiet -e "$REPO_DIR"
ok "Holler installed in $VENV_DIR"

# ---------- config.json ----------
step "Configuration"

CONFIG_PATH="$REPO_DIR/config.json"
if [[ -f "$CONFIG_PATH" ]]; then
    ok "Existing config.json preserved"
else
    cp "$REPO_DIR/config.example.json" "$CONFIG_PATH"
    ok "Created config.json from example"
    warn "Edit ${bold}$CONFIG_PATH${reset}${yellow} to add your Groq/OpenAI API keys${reset}"
    warn "Or launch Holler and use the settings dialog (first-run wizard)"
fi

# ---------- .desktop entry ----------
step "Desktop entry"

DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
DESKTOP_FILE="$DESKTOP_DIR/holler.desktop"

# Generated each install so the Exec= path always matches REPO_DIR
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Holler
Comment=Push-to-talk voice dictation
Exec=$VENV_DIR/bin/holler
Icon=$REPO_DIR/assets/icon.svg
Categories=Utility;AudioVideo;Accessibility;
Terminal=false
StartupNotify=false
Keywords=voice;dictation;speech;transcription;whisper;
EOF
ok "Wrote $DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

# ---------- systemd --user service ----------
if [[ $SKIP_SERVICE -eq 0 ]]; then
    step "Systemd --user service (auto-start on login)"

    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl not found — skipping service install"
    elif confirm "Install systemd --user service so Holler starts on login?"; then
        SERVICE_DIR="$HOME/.config/systemd/user"
        mkdir -p "$SERVICE_DIR"
        SERVICE_FILE="$SERVICE_DIR/holler.service"

        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Holler — push-to-talk voice dictation
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$VENV_DIR/bin/holler
Restart=on-failure
RestartSec=3
# Needed for PyQt on Wayland:
Environment=QT_QPA_PLATFORM=xcb

[Install]
WantedBy=graphical-session.target
EOF
        systemctl --user daemon-reload
        systemctl --user enable holler.service
        ok "Service installed and enabled (will start on next login)"
        info "Start now:  ${bold}systemctl --user start holler${reset}"
        info "Logs:       ${bold}journalctl --user -u holler -f${reset}"
    fi
fi

# ---------- done ----------
echo
echo "${green}${bold}✓ Install complete${reset}"
echo
echo "Next steps:"
echo "  1. ${bold}Edit $CONFIG_PATH${reset} with your API keys (or run Holler and use Settings)"
if [[ $IS_WAYLAND -eq 1 ]]; then
    if ! id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
        echo "  2. ${yellow}Log out and back in${reset} so the 'input' group takes effect"
        echo "  3. Run: ${bold}make run${reset}  (or: $VENV_DIR/bin/holler)"
    else
        echo "  2. Run: ${bold}make run${reset}  (or: $VENV_DIR/bin/holler)"
    fi
else
    echo "  2. Run: ${bold}make run${reset}  (or: $VENV_DIR/bin/holler)"
fi
echo
