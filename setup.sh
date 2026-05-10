#!/bin/bash

echo "============================================"
echo "    ANDROID VPS SETUP STARTING..."
echo "============================================"

# 1. Update and install important packages
sudo apt update && sudo apt upgrade -y
sudo apt install -y openjdk-17-jdk wget unzip curl git xvfb x11vnc libgl1-mesa-glx libpulse0 tmux python3

# 2. Android SDK Setup
echo "Downloading Android SDK..."
mkdir -p ~/android-sdk/cmdline-tools
cd ~/android-sdk/cmdline-tools
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip commandlinetools-linux-*.zip
mv cmdline-tools latest
rm *.zip

# Set Environment Variables temporarily for this script
export ANDROID_HOME=$HOME/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools

# Set Environment Variables permanently
if ! grep -q "ANDROID_HOME" ~/.bashrc; then
  echo 'export ANDROID_HOME=$HOME/android-sdk' >> ~/.bashrc
  echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools' >> ~/.bashrc
fi

# 3. Create Google Pixel AVD
echo "Installing Android 30 and creating Pixel 4 AVD..."
yes | sdkmanager --licenses
sdkmanager "platform-tools" "emulator" "system-images;android-30;google_apis;x86_64"
echo "no" | avdmanager create avd -n myandroid -k "system-images;android-30;google_apis;x86_64" --device "pixel_4" -f

# 4. noVNC and Websockify Setup
echo "Setting up noVNC..."
cd ~
if [ ! -d "noVNC" ]; then
  git clone https://github.com/novnc/noVNC.git
  cd noVNC
  git clone https://github.com/novnc/websockify websockify
else
  echo "noVNC already exists."
fi

# 5. THE TOUCH & SCROLL FIX (Mobile Browser Lock)
echo "Applying touch control fix for mobile browsers..."
sed -i 's/<head>/<head>\n<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, shrink-to-fit=no">\n<style>body, html, #noVNC_canvas { touch-action: none !important; overflow: hidden !important; overscroll-behavior: none; }<\/style>/' ~/noVNC/vnc.html

# 6. Install Cloudflared
echo "Installing Cloudflared..."
cd ~
curl -L -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb
rm cloudflared.deb

echo "============================================"
echo " SETUP COMPLETE! AAPKA VPS READY HAI."
echo "============================================"
