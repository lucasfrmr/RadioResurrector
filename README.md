# 1. Clone the repository

```bash
[git clone https://github.com/lucasfrmr/RadioResurrector.git](https://github.com/lucasfrmr/RadioResurrector.git)
cd pi-radio-autofailover
```


# 2. Copy files into place

```bash
sudo mkdir -p /opt/radio
sudo cp radio.sh /opt/radio/
sudo chmod +x /opt/radio/radio.sh
```

# 3. Create a systemd service
sudo systemctl enable --now radio.service

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

# 4. Enable and start the service

```bash
sudo chown -R pi:pi /opt/radio
sudo chmod -R 755 /opt/radio
sudo systemctl daemon-reload
sudo systemctl enable radio.service
sudo systemctl start radio.service
```
````We're waiting for your response to the Copilot confirmation dialog before continuing with the push and commit to your repository.
