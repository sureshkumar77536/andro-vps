#!/bin/bash
# setup.sh - Andro-VPS one-time setup. Idempotent: re-running is safe.
#
# Quick install:
#   curl -sL https://raw.githubusercontent.com/sureshkumar77536/andro-vps/main/setup.sh | bash
#
# Re-run later:
#   bash ~/andro-vps/run.sh

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/sureshkumar77536/andro-vps/main"
INSTALL_DIR="$HOME/andro-vps"

# Use sudo only when not already root and sudo is available.
if [ "$(id -u)" = "0" ]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    echo "ERROR: not root and sudo not installed. Install sudo or run as root." >&2
    exit 1
fi
mkdir -p "$INSTALL_DIR/lib"

if [ ! -f "$INSTALL_DIR/lib/ui.sh" ] || [ "${ANDROVPS_FORCE_REFRESH:-0}" = "1" ]; then
    curl -fsSL "$REPO_RAW/lib/ui.sh" -o "$INSTALL_DIR/lib/ui.sh"
fi
# shellcheck source=/dev/null
. "$INSTALL_DIR/lib/ui.sh"

clear
banner
printf "  ${C_BOLD}Android VPS — Setup${C_RESET}\n"
printf "  ${C_DIM}One-time install. Subsequent runs use: bash ~/andro-vps/run.sh${C_RESET}\n\n"

step_run "Latest scripts download kar raha hu" bash -c "
    curl -fsSL '$REPO_RAW/run.sh'    -o '$INSTALL_DIR/run.sh'
    curl -fsSL '$REPO_RAW/setup.sh'  -o '$INSTALL_DIR/setup.sh'
    curl -fsSL '$REPO_RAW/lib/ui.sh' -o '$INSTALL_DIR/lib/ui.sh'
    chmod +x '$INSTALL_DIR/run.sh' '$INSTALL_DIR/setup.sh'
"

# 1. APT packages
APT_PKGS=(openjdk-17-jdk wget unzip curl git xvfb x11vnc libgl1-mesa-glx libpulse0 tmux python3 x11-utils iproute2 ca-certificates)
need_apt=0
for p in "${APT_PKGS[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || need_apt=1
done
if [ $need_apt -eq 1 ]; then
    step_run "System packages install ho rahe hai" bash -c "
        set -e
        $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -y
        $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' ${APT_PKGS[*]}
    "
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
    "
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
    step_run "SDK licenses accept ho rahe hai" bash -c "yes | sdkmanager --licenses >/dev/null"
    step_run "Platform-tools, emulator, system image install" bash -c "
        sdkmanager 'platform-tools' 'emulator' 'system-images;android-30;google_apis;x86_64' >/dev/null
    "
else
    step_skip "SDK packages already installed"
fi

# 4. AVD
if ! "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" list avd 2>/dev/null | grep -q 'Name: myandroid'; then
    step_run "AVD 'myandroid' bana raha hu" bash -c "
        echo 'no' | avdmanager create avd -n myandroid -k 'system-images;android-30;google_apis;x86_64' --device 'pixel_4' -f >/dev/null
    "
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
    "
else
    step_skip "noVNC already cloned"
fi

# 6. Mobile-friendly viewport meta
if ! grep -q 'maximum-scale=1.0' "$HOME/noVNC/vnc.html" 2>/dev/null; then
    step_run "noVNC mobile viewport patch" bash -c "
        sed -i 's|<head>|<head>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, shrink-to-fit=no\">\n<style>body, html, #noVNC_canvas { touch-action: none !important; overflow: hidden !important; overscroll-behavior: none; }</style>|' '$HOME/noVNC/vnc.html'
    "
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
    "
else
    step_skip "cloudflared already installed"
fi

echo
printf "  ${C_GREEN}${C_BOLD}✓ Setup complete!${C_RESET}\n"
printf "  ${C_DIM}Ab Android emulator + VNC + Cloudflare tunnel start ho raha hai…${C_RESET}\n\n"

exec bash "$INSTALL_DIR/run.sh"
