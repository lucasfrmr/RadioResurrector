# 🎵 RadioResurrector

A self-healing radio stream system for Raspberry Pi.  
It continuously streams and records an online radio feed, keeping a rolling 2-hour backup.  
If the internet or stream goes down, it automatically switches to the cached buffer until the connection returns — then seamlessly resumes live playback.

---

# 1. Clone the repository

```bash
git clone https://github.com/lucasfrmr/RadioResurrector.git
cd RadioResurrector
```

---

# 2. Install required packages

```bash
sudo apt update
sudo apt install -y ffmpeg mpv alsa-utils
```

---

# 3.Grant permissions

```bash
sudo mkdir -p /opt/radio
sudo mkdir -p /opt/radio/buffer
sudo cp radio.sh /opt/radio/
sudo cp README.md /opt/radio/
sudo chmod +x /opt/radio/radio.sh
```

---

# 4. Create the systemd service

```bash
sudo tee /etc/systemd/system/radio.service > /dev/null <<'EOF'
[Unit]
Description=Auto-recovering radio stream
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/opt/radio/radio.sh
Restart=always
RestartSec=10
User=pi
WorkingDirectory=/opt/radio

[Install]
WantedBy=multi-user.target
EOF
```

---

# 5. Enable and start the service

```bash
sudo chown -R pi:pi /opt/radio
sudo chmod -R 755 /opt/radio
sudo systemctl daemon-reload
sudo systemctl enable radio.service
sudo systemctl start radio.service
```

---

# 6. Monitor the service logs

```bash
sudo journalctl -fu radio.service
```

---

# 7. Test failover

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

# 8. Edit stream settings

Open the main script:
```bash
sudo nano /opt/radio/radio.sh
```

Change the stream URL:
```bash
STREAM_URL="https://your-stream-url-here"
```

You can also modify:
- `CHUNK_SECONDS` — recording chunk length (default 300s)
- `BUFFER_MINUTES` — how much history to keep (default 120 min)
- `CHECK_INTERVAL` — how often to check stream (default 10s)

---

# 9. File locations

```
/opt/radio/
 ├── radio.sh         # Main script
 ├── README.md        # Documentation
 └── buffer/          # Rolling 2-hour audio buffer
/etc/systemd/system/radio.service
```

---

# 10. Maintenance

Clear buffer files:
```bash
sudo rm -f /opt/radio/buffer/*.mp3
```

Restart service manually:
```bash
sudo systemctl restart radio.service
```

---

# License

MIT License © 2025 Lucas Farmer
```
