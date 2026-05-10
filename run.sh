#!/bin/bash
# run.sh - Andro-VPS runtime launcher.
# Starts (or restarts) Xvfb + Android emulator + x11vnc + noVNC + Cloudflare tunnel
# and prints a single clean URL at the end.

set -uo pipefail

INSTALL_DIR="$HOME/andro-vps"
REPO_RAW="https://raw.githubusercontent.com/sureshkumar77536/andro-vps/main"

# When invoked via `curl | bash`, $0 won't have a sibling lib/. Fall back to download.
if [ -f "$(dirname "$0")/lib/ui.sh" ]; then
    # shellcheck source=/dev/null
    . "$(dirname "$0")/lib/ui.sh"
elif [ -f "$INSTALL_DIR/lib/ui.sh" ]; then
    # shellcheck source=/dev/null
    . "$INSTALL_DIR/lib/ui.sh"
else
    mkdir -p "$INSTALL_DIR/lib"
    curl -fsSL "$REPO_RAW/lib/ui.sh" -o "$INSTALL_DIR/lib/ui.sh"
    # shellcheck source=/dev/null
    . "$INSTALL_DIR/lib/ui.sh"
fi

export ANDROID_HOME="$HOME/android-sdk"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools"

CLOUDFLARED_LOG=/tmp/andro-vps-cloudflared.log
NOVNC_LOG=/tmp/andro-vps-novnc.log
EMU_LOG=/tmp/andro-vps-emulator.log
VNC_LOG=/tmp/andro-vps-x11vnc.log
XVFB_LOG=/tmp/andro-vps-xvfb.log
: > "$CLOUDFLARED_LOG"

clear
banner
printf "  ${C_BOLD}Android VPS — Launch${C_RESET}\n"
printf "  ${C_DIM}Logs: $ANDROVPS_LOG  -  Live tmux: tmux attach -t android_vps${C_RESET}\n\n"

# Pre-flight: required binaries
missing=0
for bin in Xvfb x11vnc tmux cloudflared adb emulator; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        missing=1
        printf "  ${C_RED}✘${C_RESET}  %s missing\n" "$bin"
    fi
done
if [ $missing -eq 1 ] || [ ! -d "$HOME/noVNC" ]; then
    echo
    printf "  ${C_YELLOW}⚠ Setup adhura hai. Pehle ye chala:${C_RESET}\n"
    printf "    ${C_BOLD}curl -sL %s/setup.sh | bash${C_RESET}\n\n" "$REPO_RAW"
    exit 1
fi

# 1. Cleanup any previous run.
step_run "Purani sessions cleanup" bash -c '
    tmux kill-session -t android_vps 2>/dev/null || true
    pkill -f "Xvfb :1"           2>/dev/null || true
    pkill -f "qemu-system"       2>/dev/null || true
    pkill -f "x11vnc.*:1"        2>/dev/null || true
    pkill -f "novnc_proxy"       2>/dev/null || true
    pkill -f "websockify"        2>/dev/null || true
    pkill -f "cloudflared tunnel" 2>/dev/null || true
    sleep 1
    true
'

# 2. Xvfb in its own tmux window
tmux new-session -d -s android_vps -n xvfb \
    "Xvfb :1 -screen 0 1080x1920x24 >$XVFB_LOG 2>&1"
spinner_until "DISPLAY=:1 xdpyinfo" "Xvfb display ready" 15 || exit 1

# 3. Emulator
tmux new-window -t android_vps -n emulator \
    "DISPLAY=:1 '$ANDROID_HOME/emulator/emulator' -avd myandroid -no-audio -no-boot-anim -no-snapshot-save -gpu swiftshader_indirect -memory 3000 -skin 1080x1920 >$EMU_LOG 2>&1"
spinner_until "adb get-state | grep -q device" "Emulator process up" 90 || true
spinner_until "adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' | grep -q 1" \
    "Android boot ho raha hai (1-2 min lag sakta hai)" 360 || {
    printf "  ${C_YELLOW}⚠${C_RESET}  Boot detect nahi hua, fir bhi continue kar raha hu — log: $EMU_LOG\n"
}

# 4. x11vnc
tmux new-window -t android_vps -n x11vnc \
    "x11vnc -display :1 -nopw -listen localhost -rfbport 5900 -xkb -forever -shared >$VNC_LOG 2>&1"
spinner_until "ss -ltn 2>/dev/null | grep -q ':5900 '" "x11vnc listening on 5900" 15 || exit 1

# 5. noVNC
tmux new-window -t android_vps -n novnc \
    "$HOME/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 6080 >$NOVNC_LOG 2>&1"
spinner_until "ss -ltn 2>/dev/null | grep -q ':6080 '" "noVNC web server on 6080" 15 || exit 1

# 6. Cloudflare tunnel
tmux new-window -t android_vps -n cloudflared \
    "cloudflared tunnel --url http://localhost:6080 --no-autoupdate >$CLOUDFLARED_LOG 2>&1"
spinner_until "grep -Eo 'https://[a-zA-Z0-9.-]+\\.trycloudflare\\.com' '$CLOUDFLARED_LOG' | head -1" \
    "Cloudflare tunnel URL milne ka wait" 90 || {
    printf "  ${C_RED}✘${C_RESET}  Cloudflare URL nahi mila. Log: $CLOUDFLARED_LOG\n"
    exit 1
}

CF_URL=$(grep -Eo 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$CLOUDFLARED_LOG" | head -1)
VNC_LINK="$CF_URL/vnc.html?autoconnect=true&resize=remote&reconnect=true"

echo
printf "${C_GREEN}${C_BOLD}  ╔══════════════════════════════════════════════════════════════╗${C_RESET}\n"
printf "${C_GREEN}${C_BOLD}  ║                  SAB KUCH READY HAI! 🚀                       ║${C_RESET}\n"
printf "${C_GREEN}${C_BOLD}  ╚══════════════════════════════════════════════════════════════╝${C_RESET}\n"
echo
printf "  ${C_BOLD}🔗 VNC link (browser me kholo, autoconnect ho jayega):${C_RESET}\n"
printf "     ${C_CYAN}${C_BOLD}%s${C_RESET}\n" "$VNC_LINK"
echo
printf "  ${C_BOLD}🌐 Plain tunnel URL:${C_RESET}\n"
printf "     ${C_YELLOW}%s${C_RESET}\n" "$CF_URL"
echo
printf "  ${C_DIM}- Logs dekho:    tmux attach -t android_vps${C_RESET}\n"
printf "  ${C_DIM}- Restart:       bash ~/andro-vps/run.sh${C_RESET}\n"
printf "  ${C_DIM}- Stop:          tmux kill-session -t android_vps${C_RESET}\n"
echo
