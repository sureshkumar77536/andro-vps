#!/bin/bash
# setup.sh - Andro-VPS one-time setup. Self-contained, idempotent.

set -uo pipefail

REPO_RAW="https://raw.githubusercontent.com/sureshkumar77536/andro-vps/main"
INSTALL_DIR="$HOME/andro-vps"
mkdir -p "$INSTALL_DIR"

# ───────────────────────────── inline UI helpers ─────────────────────────────
if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[1;34m'; C_CYAN=$'\033[1;36m'
else
    C_RESET=''; C_BOLD=''; C_DIM=''
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
fi
ANDROVPS_LOG="${ANDROVPS_LOG:-/tmp/andro-vps.log}"
: > "$ANDROVPS_LOG"

_ui_restore_cursor() { tput cnorm 2>/dev/null || printf '\033[?25h'; }
trap _ui_restore_cursor EXIT INT TERM
_ui_hide_cursor() { tput civis 2>/dev/null || printf '\033[?25l'; }

spinner_pid() {
    local pid=$1 msg=$2
    local frames=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
    local i=0
    _ui_hide_cursor
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${C_CYAN}${frames[$i]}${C_RESET}  %s" "$msg"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
    local rc=0
    wait "$pid" || rc=$?
    _ui_restore_cursor
    if [ $rc -eq 0 ]; then
        printf "\r  ${C_GREEN}✔${C_RESET}  %s\n" "$msg"
    else
        printf "\r  ${C_RED}✘${C_RESET}  %s\n" "$msg"
    fi
    return $rc
}

step_run() {
    local msg=$1; shift
    local before
    before=$(wc -l <"$ANDROVPS_LOG" 2>/dev/null || echo 0)
    ( "$@" ) >>"$ANDROVPS_LOG" 2>&1 &
    local rc=0
    spinner_pid $! "$msg" || rc=$?
    if [ $rc -ne 0 ]; then
        local after
        after=$(wc -l <"$ANDROVPS_LOG" 2>/dev/null || echo 0)
        local n=$(( after - before ))
        [ $n -lt 30 ] && n=30
        printf "  ${C_DIM}── last %s log lines ──${C_RESET}\n" "$n"
        tail -n "$n" "$ANDROVPS_LOG" 2>/dev/null | sed "s/^/    ${C_DIM}│${C_RESET} /"
        printf "  ${C_DIM}── full log: $ANDROVPS_LOG ──${C_RESET}\n"
    fi
    return $rc
}

step_skip() { printf "  ${C_YELLOW}⊙${C_RESET}  %s ${C_DIM}(already done)${C_RESET}\n" "$1"; }
step_done() { printf "  ${C_GREEN}✔${C_RESET}  %s\n" "$1"; }
step_info() { printf "  ${C_BLUE}ℹ${C_RESET}  %s\n" "$1"; }

banner() {
    printf "${C_GREEN}${C_BOLD}"
    cat <<'EOF'
   _              _              __     ______  ____
  /_\  _ _   __| |_ _ ___       \ \   / /  _ \/ ___|
 //_\\| ' \ / _` | '_/ _ \  _____\ \ / /| |_) \___ \
/  _  \ | || (_| | || (_) ||_____|\ V / |  __/ ___) |
\_/ \_/_||_|\__,_|_| \___/         \_/  |_|   |____/
EOF
    printf "${C_RESET}\n"
}
# ─────────────────────────────────────────────────────────────────────────────

if [ "$(id -u)" = "0" ]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    echo "ERROR: not root and sudo not installed. Install sudo or run as root." >&2
    exit 1
fi

clear
banner
printf "  ${C_BOLD}Android VPS — Setup${C_RESET}\n"
printf "  ${C_DIM}One-time install. Subsequent runs use: bash ~/andro-vps/run.sh${C_RESET}\n"
printf "  ${C_DIM}Detailed log: $ANDROVPS_LOG${C_RESET}\n\n"

step_run "Latest scripts download" bash -c "
    curl -fsSL '$REPO_RAW/run.sh'   -o '$INSTALL_DIR/run.sh'
    curl -fsSL '$REPO_RAW/setup.sh' -o '$INSTALL_DIR/setup.sh'
    chmod +x '$INSTALL_DIR/run.sh' '$INSTALL_DIR/setup.sh'
"

# 1. APT packages
APT_PKGS=(openjdk-17-jdk wget unzip curl git xvfb x11vnc libgl1 libpulse0 tmux python3 x11-utils iproute2 ca-certificates)
need_apt=0
for p in "${APT_PKGS[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || need_apt=1
done
if [ $need_apt -eq 1 ]; then
    step_run "System packages install ho rahe hai" bash -c "
        set -e
        for i in \$(seq 1 60); do
            if ! pgrep -x apt-get >/dev/null && ! pgrep -x dpkg >/dev/null && ! pgrep -x unattended-upgr >/dev/null; then
                break
            fi
            echo \"apt busy, waiting (\${i}/60)...\"
            sleep 2
        done
        $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -y
        $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \\
            -o Dpkg::Options::='--force-confdef' \\
            -o Dpkg::Options::='--force-confold' \\
            ${APT_PKGS[*]}
    " || exit 1
else
    step_skip "System packages already installed"
fi

# 2. Android SDK command-line tools
ANDROID_HOME="$HOME/android-sdk"
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
    step_run "Android SDK command-line tools download" bash -c "
        set -e
        mkdir -p '$ANDROID_HOME/cmdline-tools'
        cd '$ANDROID_HOME/cmdline-tools'
        curl -fsSL -o cmdline.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
        unzip -q -o cmdline.zip
        rm -rf latest
        mv cmdline-tools latest
        rm -f cmdline.zip
    " || exit 1
else
    step_skip "Android SDK command-line tools already installed"
fi

export ANDROID_HOME
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools"

if ! grep -q "ANDROID_HOME" "$HOME/.bashrc" 2>/dev/null; then
    {
        echo ''
        echo '# Andro-VPS'
        echo 'export ANDROID_HOME=$HOME/android-sdk'
        echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools'
    } >> "$HOME/.bashrc"
fi

# 3. SDK packages
SDK_IMG_DIR="$ANDROID_HOME/system-images/android-30/google_apis/x86_64"
if [ ! -d "$SDK_IMG_DIR" ] || [ ! -x "$ANDROID_HOME/emulator/emulator" ]; then
    step_run "SDK licenses accept ho rahe hai" bash -c "yes | sdkmanager --licenses >/dev/null" || exit 1
    step_run "Platform-tools, emulator, system image install" bash -c "
        sdkmanager 'platform-tools' 'emulator' 'system-images;android-30;google_apis;x86_64' >/dev/null
    " || exit 1
else
    step_skip "SDK packages already installed"
fi

# 4. AVD
if ! "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" list avd 2>/dev/null | grep -q 'Name: myandroid'; then
    step_run "AVD 'myandroid' bana raha hu" bash -c "
        echo 'no' | avdmanager create avd -n myandroid -k 'system-images;android-30;google_apis;x86_64' --device 'pixel_4' -f >/dev/null
    " || exit 1
else
    step_skip "AVD myandroid already exists"
fi

# 5. noVNC + websockify
if [ ! -d "$HOME/noVNC" ]; then
    step_run "noVNC clone" bash -c "
        set -e
        cd '$HOME'
        git clone -q https://github.com/novnc/noVNC.git
        cd noVNC
        git clone -q https://github.com/novnc/websockify websockify
    " || exit 1
else
    step_skip "noVNC already cloned"
fi

# 6. Mobile-friendly viewport meta in vnc.html
if ! grep -q 'maximum-scale=1.0' "$HOME/noVNC/vnc.html" 2>/dev/null; then
    step_run "noVNC mobile viewport patch" bash -c "
        sed -i 's|<head>|<head>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, shrink-to-fit=no\">\n<style>body, html, #noVNC_canvas { touch-action: none !important; overflow: hidden !important; overscroll-behavior: none; }</style>|' '$HOME/noVNC/vnc.html'
    " || exit 1
else
    step_skip "noVNC mobile viewport already patched"
fi

# 7. cloudflared
if ! command -v cloudflared >/dev/null 2>&1; then
    step_run "cloudflared install" bash -c "
        set -e
        cd /tmp
        curl -fsSL -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        $SUDO dpkg -i cloudflared.deb >/dev/null
        rm -f cloudflared.deb
    " || exit 1
else
    step_skip "cloudflared already installed"
fi

echo
printf "  ${C_GREEN}${C_BOLD}✓ Setup complete!${C_RESET}\n"
printf "  ${C_DIM}Ab Android emulator + VNC + Cloudflare tunnel start ho raha hai…${C_RESET}\n\n"

exec bash "$INSTALL_DIR/run.sh"
