# 🎵 RadioResurrector

A self-healing radio stream system for Raspberry Pi.  
It continuously streams and records an online radio feed, keeping a rolling 2-hour backup.  
If the internet or stream goes down, it automatically switches to the cached buffer until the connection returns — then seamlessly resumes live playback.

A **PIN-protected web interface** lets you control everything from any device on your network — change streams, adjust volume, tune chunk sizes, and manage the buffer, all without touching the Pi.

---

# 1. Clone and run the setup script

```bash
git clone https://github.com/lucasfrmr/RadioResurrector.git
cd RadioResurrector
sudo bash setup.sh
```

That's it. The script installs dependencies, copies files to `/opt/radio`, creates both systemd services, and starts everything automatically.

---

# 2. Open the web interface

Find your Pi's IP address:
```bash
hostname -I
```

Then open a browser on any device on the same network:
```
http://<pi-ip>:8080
```

The default PIN is **1234** — change it immediately from the dashboard.

### Web interface controls

| Control | Description |
|---|---|
| **Volume** | Live slider — updates the audio level instantly |
| **Stream URL** | Paste any stream URL, or choose a saved preset |
| **Chunk Size** | How many seconds per buffer file (60–600 s) |
| **Buffer Duration** | How much history to keep (30–360 min) |
| **Check Interval** | How often to test the live stream (5–60 s) |
| **Apply & Restart** | Saves all settings and restarts the radio service |
| **Start / Restart / Stop** | Direct service controls |
| **Stream Presets** | Save and manage favourite stream URLs |
| **Change PIN** | Update the web interface PIN (4–8 digits) |

---

# 3. Monitor service logs

```bash
# Radio stream logs
sudo journalctl -fu radio.service

# Web interface logs
sudo journalctl -fu radio-web.service
```

---

# 4. Test failover

To simulate an internet outage:
```bash
sudo ip route add blackhole 0.0.0.0/0
```

Wait ~10 seconds; the Pi should begin playing from the buffer.  
Restore the connection:
```bash
sudo ip route del blackhole 0.0.0.0/0
```

---

# 5. File locations

```
/opt/radio/
 ├── radio.sh         # Main stream script
 ├── web.py           # Web interface server
 ├── config.json      # Settings (managed by web UI)
 ├── config.sh        # Shell-sourced config (written by web UI)
 ├── README.md        # Documentation
 └── buffer/          # Rolling audio buffer
/etc/systemd/system/radio.service
/etc/systemd/system/radio-web.service
```

---

# 6. Maintenance

Clear buffer files:
```bash
sudo rm -f /opt/radio/buffer/*.mp3
```

Restart both services:
```bash
sudo systemctl restart radio.service radio-web.service
```

Edit settings manually (or use the web UI):
```bash
sudo nano /opt/radio/config.json
sudo systemctl restart radio.service
```

---

# License

MIT License © 2025 Lucas Farmer
