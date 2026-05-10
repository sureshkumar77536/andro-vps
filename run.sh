#!/bin/bash

export ANDROID_HOME=$HOME/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools

tmux kill-session -t android_vps 2>/dev/null
tmux new-session -d -s android_vps

tmux send-keys -t android_vps 'Xvfb :1 -screen 0 1080x1920x24' C-m
sleep 3
tmux send-keys -t android_vps "DISPLAY=:1 $ANDROID_HOME/emulator/emulator -avd myandroid -no-audio -no-boot-anim -gpu swiftshader_indirect -memory 3000 -skin 1080x1920" C-m
sleep 5

tmux send-keys -t android_vps 'x11vnc -display :1 -nopw -listen localhost -xkb -forever -shared' C-m
sleep 2
tmux send-keys -t android_vps '~/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 6080' C-m
sleep 2

echo "============================================"
echo "SAB KUCH READY HAI! CLOUDFLARE LINK AA RAHI HAI:"
echo "============================================"
cloudflared tunnel --url http://localhost:6080
