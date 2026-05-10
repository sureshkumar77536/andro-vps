#!/bin/bash

echo "============================================"
echo "    ANDROID VPS SETUP STARTING..."
echo "============================================"

[span_0](start_span)sudo apt update && sudo apt upgrade -y[span_0](end_span)
[span_1](start_span)sudo apt install -y openjdk-17-jdk wget unzip curl git xvfb x11vnc libgl1-mesa-glx libpulse0 tmux python3[span_1](end_span)

mkdir -p ~/android-sdk/cmdline-tools
cd ~/android-sdk/cmdline-tools
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip commandlinetools-linux-*.zip
mv cmdline-tools latest
rm *.zip

export ANDROID_HOME=$HOME/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools

if ! grep -q "ANDROID_HOME" ~/.bashrc; then
  echo 'export ANDROID_HOME=$HOME/android-sdk' >> ~/.bashrc
  echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools' >> ~/.bashrc
fi

[span_2](start_span)yes | sdkmanager --licenses[span_2](end_span)
sdkmanager "platform-tools" "emulator" "system-images;android-30;google_apis;x86_64"
echo "no" | avdmanager create avd -n myandroid -k "system-images;android-30;google_apis;x86_64" --device "pixel_4" -f

cd ~
if [ ! -d "noVNC" ]; then
  git clone https://github.com/novnc/noVNC.git
  cd noVNC
  git clone https://github.com/novnc/websockify websockify
fi

sed -i 's/<head>/<head>\n<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, shrink-to-fit=no">\n<style>body, html, #noVNC_canvas { touch-action: none !important; overflow: hidden !important; overscroll-behavior: none; }<\/style>/' ~/noVNC/vnc.html

cd ~
curl -L -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb
rm cloudflared.deb

echo "============================================"
echo " INSTALLATION COMPLETE! AUTOMATICALLY STARTING RUN.SH..."
echo "============================================"

# Yahan par run.sh apne aap chalu ho jayega bina user ke type kiye
curl -sL https://raw.githubusercontent.com/sureshkumar77536/andro-vps/main/run.sh | bash
