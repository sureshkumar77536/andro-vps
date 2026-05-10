#!/bin/bash
# run.sh - Andro-VPS runtime launcher. Self-contained.

set -uo pipefail

INSTALL_DIR="$HOME/andro-vps"
REPO_RAW="https://raw.githubusercontent.com/sureshkumar77536/andro-vps/main"

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

spinner_until() {
    local check=$1 msg=$2 timeout=${3:-180}
    local frames=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
    local i=0 elapsed=0 max=$(( timeout * 5 ))
    _ui_hide_cursor
    while ! eval "$check" >/dev/null 2>&1; do
        printf "\r  ${C_CYAN}${frames[$i]}${C_RESET}  %s" "$msg"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.2
        elapsed=$(( elapsed + 1 ))
        if [ $elapsed -gt $max ]; then
            _ui_restore_cursor
            printf "\r  ${C_RED}✘${C_RESET}  %s ${C_DIM}(timeout)${C_RESET}\n" "$msg"
            return 1
        fi
    done
    _ui_restore_cursor
    printf "\r  ${C_GREEN}✔${C_RESET}  %s\n" "$msg"
    return 0
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

# Pre-flight
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

step_run "Purani sessions cleanup" bash -c '
    tmux kill-session -t android_vps 2>/dev/null || true
    pkill -f "Xvfb :1"            2>/dev/null || true
    pkill -f "qemu-system"        2>/dev/null || true
    pkill -f "x11vnc.*:1"         2>/dev/null || true
    pkill -f "novnc_proxy"        2>/dev/null || true
    pkill -f "websockify"         2>/dev/null || true
    pkill -f "cloudflared tunnel" 2>/dev/null || true
    sleep 1
    true
'

tmux new-session -d -s android_vps -n xvfb \
    "Xvfb :1 -screen 0 1080x1920x24 >$XVFB_LOG 2>&1"
spinner_until "DISPLAY=:1 xdpyinfo" "Xvfb display ready" 15 || exit 1

tmux new-window -t android_vps -n emulator \
    "DISPLAY=:1 '$ANDROID_HOME/emulator/emulator' -avd myandroid -no-audio -no-boot-anim -no-snapshot-save -gpu swiftshader_indirect -memory 3000 -skin 1080x1920 >$EMU_LOG 2>&1"
spinner_until "adb get-state | grep -q device" "Emulator process up" 90 || true
spinner_until "adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' | grep -q 1" \
    "Android boot ho raha hai (1-2 min lag sakta hai)" 360 || {
    printf "  ${C_YELLOW}⚠${C_RESET}  Boot detect nahi hua, fir bhi continue kar raha hu — log: $EMU_LOG\n"
}

tmux new-window -t android_vps -n x11vnc \
    "x11vnc -display :1 -nopw -listen localhost -rfbport 5900 -xkb -forever -shared >$VNC_LOG 2>&1"
spinner_until "ss -ltn 2>/dev/null | grep -q ':5900 '" "x11vnc listening on 5900" 15 || exit 1

tmux new-window -t android_vps -n novnc \
    "$HOME/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 6080 >$NOVNC_LOG 2>&1"
spinner_until "ss -ltn 2>/dev/null | grep -q ':6080 '" "noVNC web server on 6080" 15 || exit 1

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
