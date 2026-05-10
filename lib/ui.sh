#!/bin/bash
# Shared UI helpers: colors, spinner, banner, step runners.
# Source this file: . "$(dirname "$0")/lib/ui.sh"

if [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[1;31m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[1;34m'
    C_MAGENTA=$'\033[1;35m'
    C_CYAN=$'\033[1;36m'
else
    C_RESET=''; C_BOLD=''; C_DIM=''
    C_RED=''; C_GREEN=''; C_YELLOW=''
    C_BLUE=''; C_MAGENTA=''; C_CYAN=''
fi

ANDROVPS_LOG="${ANDROVPS_LOG:-/tmp/andro-vps.log}"
: > "$ANDROVPS_LOG"

# Restore cursor on any exit so a Ctrl-C doesn't leave it hidden.
_ui_restore_cursor() { tput cnorm 2>/dev/null || printf '\033[?25h'; }
trap _ui_restore_cursor EXIT INT TERM

_ui_hide_cursor() { tput civis 2>/dev/null || printf '\033[?25l'; }

# spinner_pid <pid> <message>
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
    wait "$pid"
    local rc=$?
    _ui_restore_cursor
    if [ $rc -eq 0 ]; then
        printf "\r  ${C_GREEN}✔${C_RESET}  %s\n" "$msg"
    else
        printf "\r  ${C_RED}✘${C_RESET}  %s ${C_DIM}(log: $ANDROVPS_LOG)${C_RESET}\n" "$msg"
    fi
    return $rc
}

# spinner_until '<bash test>' '<message>' [timeout_sec]
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

# step_run '<message>' <command...>
# Runs in background, redirects to log, shows spinner.
# On failure: dumps the log lines that this step produced so the user
# can see the actual error in the terminal.
step_run() {
    local msg=$1; shift
    local before
    before=$(wc -l <"$ANDROVPS_LOG" 2>/dev/null || echo 0)
    ( "$@" ) >>"$ANDROVPS_LOG" 2>&1 &
    spinner_pid $! "$msg"
    local rc=$?
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
