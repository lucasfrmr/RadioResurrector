# 1. Clone the repository
git clone https://github.com/<your-username>/pi-radio-autofailover.git
cd pi-radio-autofailover

# 2. Copy files into place
sudo mkdir -p /opt/radio
sudo cp radio.sh /opt/radio/
sudo chmod +x /opt/radio/radio.sh

# 3. Create a systemd service
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

# 4. Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable radio.service
sudo systemctl start radio.service

