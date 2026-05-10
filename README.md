# Andro-VPS

Browser ke through Android emulator ka VNC access — sirf Cloudflare link share karke.

Stack: **Xvfb + Android Emulator (API 30) + x11vnc + noVNC + cloudflared**.

---

## ⚡ Quick Install (sirf ek command)

Pehli baar install karne ke liye:

```bash
curl -sL https://raw.githubusercontent.com/sureshkumar77536/andro-vps/main/setup.sh | bash
```

Setup automatic chalega. Har step ke liye animated spinner dikhega — download spam nahi. Last me ek clean Cloudflare link milegi jaise:

```
https://something-random.trycloudflare.com/vnc.html?autoconnect=true&resize=remote&reconnect=true
```

Wo link browser me kholo (mobile/PC) — Connect button click karne ki zaroorat nahi, autoconnect ho jayega.

---

## 🔁 Re-run / Restart (agar pehle se install hai)

Setup ke baad sab kuch `~/andro-vps/` me save ho jata hai. Dobara start karne ke liye:

```bash
bash ~/andro-vps/run.sh
```

Ye script:
- purani Xvfb / emulator / x11vnc / noVNC / cloudflared sessions ko clean karti hai
- sab kuch fresh start karti hai
- ek nayi Cloudflare link print karti hai

Agar `~/andro-vps/` exist nahi karta (naye VPS pe ho), to wapis Quick Install run karo — wo idempotent hai, jo pehle se installed hai use skip kar dega.

### Stop karne ke liye

```bash
tmux kill-session -t android_vps
```

### Live logs dekhne ke liye

```bash
tmux attach -t android_vps
```

`Ctrl-b` phir `n` se window switch (xvfb / emulator / x11vnc / novnc / cloudflared). Detach: `Ctrl-b` phir `d`.

---

## 🛠️ Requirements

- Ubuntu / Debian VPS (root ya `sudo` access)
- ≥ 4 GB RAM (emulator ke liye)
- KVM / nested virtualization enabled hone par boot bahut tez ho jata hai (recommended)
- Outbound internet access (cloudflared ke liye)

---

## 🐞 Troubleshooting

| Problem | Fix |
|---|---|
| `Failed to connect to server` browser me | `bash ~/andro-vps/run.sh` se restart, fir nayi link use karo |
| Emulator boot bahut slow | KVM enable karwao VPS provider se, ya `-memory 3000` value badhao `run.sh` me |
| `cloudflared` URL print nahi hua | `cat /tmp/andro-vps-cloudflared.log` dekho |
| Cursor hidden ho gaya Ctrl-C ke baad | `tput cnorm` ya naya terminal kholo |

Detailed install log: `/tmp/andro-vps.log`

---

## 📁 Files

- `setup.sh` — one-time installer (idempotent, animated)
- `run.sh` — start / restart everything (idempotent, animated)
- `lib/ui.sh` — shared spinner / colors / banner helpers
- `README.md` — ye file

---

## 📝 Notes
THIS REPO IS MANAGED BY P******t SAHU

- `myandroid` AVD: Pixel 4 skin, Android 30 (Google APIs, x86_64)
- noVNC `vnc.html` me mobile viewport meta auto-patch hota hai taaki phone pe pinch-zoom theek se chale
- Cloudflare quick tunnel use ho rahi hai — link har restart pe change hoti hai (ye normal hai). Stable URL chahiye to `cloudflared` ka named tunnel setup karo.
