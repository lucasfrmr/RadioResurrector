#!/bin/bash
# RadioResurrector — one-shot setup script
# Run with: sudo bash setup.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[setup]${NC} $*"; }
success() { echo -e "${GREEN}${BOLD}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[!]${NC} $*"; }
die()     { echo -e "${RED}${BOLD}[✗]${NC} $*" >&2; exit 1; }

# ── Root check ──────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Please run as root: sudo bash setup.sh"

# ── Locate source files ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/radio.sh" ]] || die "radio.sh not found in $SCRIPT_DIR"
[[ -f "$SCRIPT_DIR/web.py"   ]] || die "web.py not found in $SCRIPT_DIR"

INSTALL_DIR="/opt/radio"
BUFFER_DIR="$INSTALL_DIR/buffer"
MP3_PLAYER_DIR="$INSTALL_DIR/mp3"
RADIO_SERVICE="/etc/systemd/system/radio.service"
WEB_SERVICE="/etc/systemd/system/radio-web.service"

echo ""
echo -e "${BOLD}  📻  RadioResurrector Setup${NC}"
echo "  ─────────────────────────────"
echo ""

# ── 1. Packages ─────────────────────────────────────────────────────────────
info "Installing packages (ffmpeg mpv alsa-utils python3-flask curl)..."
apt-get update -qq
apt-get install -y -qq ffmpeg mpv alsa-utils python3-flask curl
success "Packages installed"

# ── 1b. Raspotify (Spotify Connect) ──────────────────────────────────────────
# Installed but disabled by default. The web UI toggles it on/off,
# swapping it with radio.service so only one owns the audio device.
if ! command -v librespot >/dev/null 2>&1 && [[ ! -f /etc/default/raspotify ]]; then
  info "Installing raspotify (Spotify Connect)..."
  curl -sL https://dtcooper.github.io/raspotify/install.sh | sh
  success "raspotify installed"
else
  info "raspotify already present — skipping install"
fi

info "Writing /etc/default/raspotify ..."
cat > /etc/default/raspotify <<'EOF'
DEVICE_NAME="Pi Spotify"
BITRATE="320"
EOF

# Disabled by default — user opts in via web UI.
systemctl disable --now raspotify.service >/dev/null 2>&1 || true
success "raspotify configured (disabled by default)"

# ── 2. Directories & files ───────────────────────────────────────────────────
info "Creating $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR" "$BUFFER_DIR" "$MP3_PLAYER_DIR"

cp "$SCRIPT_DIR/radio.sh"  "$INSTALL_DIR/radio.sh"
cp "$SCRIPT_DIR/web.py"    "$INSTALL_DIR/web.py"
cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/README.md"

chmod +x "$INSTALL_DIR/radio.sh"
chmod +x "$INSTALL_DIR/web.py"

# Determine the non-root user who should own /opt/radio
# (the user who invoked sudo, or 'pi' as fallback)
RADIO_USER="${SUDO_USER:-pi}"
if ! id "$RADIO_USER" &>/dev/null; then
  RADIO_USER="pi"
fi
if ! id "$RADIO_USER" &>/dev/null; then
  RADIO_USER="$(logname 2>/dev/null || echo root)"
fi

chown -R "$RADIO_USER":"$RADIO_USER" "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"
success "Files installed to $INSTALL_DIR (owner: $RADIO_USER)"

# ── 3. Radio service ────────────────────────────────────────────────────────
info "Writing $RADIO_SERVICE ..."
cat > "$RADIO_SERVICE" <<EOF
[Unit]
Description=Auto-recovering radio stream
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$INSTALL_DIR/radio.sh
Restart=always
RestartSec=10
User=$RADIO_USER
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF
success "radio.service written"

# ── 4. Web service ───────────────────────────────────────────────────────────
info "Writing $WEB_SERVICE ..."
cat > "$WEB_SERVICE" <<EOF
[Unit]
Description=RadioResurrector Web Interface
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 $INSTALL_DIR/web.py
Restart=always
RestartSec=5
User=root
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF
success "radio-web.service written"

# ── 4b. Default stream prompt ────────────────────────────────────────────────
# Ask the user for a stream URL to pre-load, so the first boot plays the
# right thing without needing to open the web UI. Skipped when stdin is
# not a TTY (e.g. piped installs) or when config.json already exists.
DEFAULT_STREAM_URL=""
DEFAULT_STREAM_NAME=""
if [[ ! -f "$INSTALL_DIR/config.json" && -t 0 ]]; then
  echo ""
  echo -e "${BOLD}  🎙  Default stream${NC}"
  echo "  ─────────────────────────────"
  read -rp "  Stream URL (leave blank to configure later): " DEFAULT_STREAM_URL
  if [[ -n "$DEFAULT_STREAM_URL" ]]; then
    read -rp "  Name for this stream [Default]: " DEFAULT_STREAM_NAME
    DEFAULT_STREAM_NAME="${DEFAULT_STREAM_NAME:-Default}"
  fi
fi

if [[ -n "$DEFAULT_STREAM_URL" ]]; then
  info "Writing initial config with '$DEFAULT_STREAM_NAME' as default stream..."
  INSTALL_DIR="$INSTALL_DIR" \
  STREAM_URL="$DEFAULT_STREAM_URL" \
  STREAM_NAME="$DEFAULT_STREAM_NAME" \
  python3 - <<'PY'
import json, os, secrets
cfg = {
    "secret_key":     secrets.token_hex(32),
    "pin":            "1234",
    "stream_url":     os.environ["STREAM_URL"],
    "chunk_seconds":  300,
    "buffer_minutes": 120,
    "check_interval": 10,
    "volume":         90,
    "buffer_enabled": False,
    "mp3_player_dir": os.path.join(os.environ["INSTALL_DIR"], "mp3"),
    "streams": [
        {"name": os.environ["STREAM_NAME"], "url": os.environ["STREAM_URL"]},
    ],
}
with open(os.path.join(os.environ["INSTALL_DIR"], "config.json"), "w") as f:
    json.dump(cfg, f, indent=2)
PY

  # Also write config.sh so the very first radio.sh start uses this URL
  # (web.py would otherwise write it on first dashboard load).
  cat > "$INSTALL_DIR/config.sh" <<EOF
# Auto-generated by RadioResurrector setup.sh — overwritten by web UI on save
STREAM_URL="$DEFAULT_STREAM_URL"
CHUNK_SECONDS=300
BUFFER_MINUTES=120
MAX_CHUNKS=\$(( BUFFER_MINUTES * 60 / CHUNK_SECONDS ))
CHECK_INTERVAL=10
VOLUME=90
BUFFER_ENABLED=0
MP3_PLAYER_DIR="$INSTALL_DIR/mp3"
EOF

  chown "$RADIO_USER":"$RADIO_USER" "$INSTALL_DIR/config.json" "$INSTALL_DIR/config.sh"
  chmod 644 "$INSTALL_DIR/config.json" "$INSTALL_DIR/config.sh"
  success "Default stream saved"
fi

# ── 4c. Config migration for existing installs ──────────────────────────────
info "Ensuring MP3 player config defaults ..."
INSTALL_DIR="$INSTALL_DIR" python3 - <<'PY'
import json, os, secrets

install_dir = os.environ["INSTALL_DIR"]
config_json = os.path.join(install_dir, "config.json")
config_sh = os.path.join(install_dir, "config.sh")
mp3_dir = os.path.join(install_dir, "mp3")

if os.path.exists(config_json):
    with open(config_json) as f:
        cfg = json.load(f)
else:
    cfg = {
        "secret_key": secrets.token_hex(32),
        "pin": "1234",
        "stream_url": "https://findyourownstream.example/stream",
        "chunk_seconds": 300,
        "buffer_minutes": 120,
        "check_interval": 10,
        "volume": 90,
        "streams": [
            {"name": "Example Stream", "url": "https://findyourownstream.example/stream"},
        ],
    }

if "mp3_player_dir" not in cfg:
    cfg["buffer_enabled"] = False
cfg.setdefault("buffer_enabled", False)
cfg.setdefault("mp3_player_dir", mp3_dir)

with open(config_json, "w") as f:
    json.dump(cfg, f, indent=2)

with open(config_sh, "w") as f:
    f.write("# Auto-generated by RadioResurrector setup.sh — overwritten by web UI on save\n")
    f.write(f'STREAM_URL="{cfg["stream_url"]}"\n')
    f.write(f'CHUNK_SECONDS={cfg.get("chunk_seconds", 300)}\n')
    f.write(f'BUFFER_MINUTES={cfg.get("buffer_minutes", 120)}\n')
    f.write('MAX_CHUNKS=$(( BUFFER_MINUTES * 60 / CHUNK_SECONDS ))\n')
    f.write(f'CHECK_INTERVAL={cfg.get("check_interval", 10)}\n')
    f.write(f'VOLUME={cfg.get("volume", 90)}\n')
    f.write(f'BUFFER_ENABLED={1 if cfg.get("buffer_enabled", False) else 0}\n')
    f.write(f'MP3_PLAYER_DIR="{cfg.get("mp3_player_dir", mp3_dir)}"\n')
PY
chown "$RADIO_USER":"$RADIO_USER" "$INSTALL_DIR/config.json" "$INSTALL_DIR/config.sh"
chmod 644 "$INSTALL_DIR/config.json" "$INSTALL_DIR/config.sh"
success "MP3 player config defaults ready"

# ── 5. Enable & start ────────────────────────────────────────────────────────
info "Enabling and starting services..."
systemctl daemon-reload
systemctl enable radio.service radio-web.service
systemctl restart radio.service radio-web.service
success "Both services enabled and started"

# ── 6. Done ─────────────────────────────────────────────────────────────────
PI_IP="$(hostname -I | awk '{print $1}')"

echo ""
echo -e "${GREEN}${BOLD}  ✓  Setup complete!${NC}"
echo "  ─────────────────────────────"
echo -e "  Web interface → ${BOLD}http://${PI_IP}:8080${NC}"
echo -e "  Default PIN   → ${BOLD}1234${NC}  (change this in the dashboard)"
echo ""
echo "  Useful commands:"
echo "    sudo journalctl -fu radio.service      # stream logs"
echo "    sudo journalctl -fu radio-web.service  # web logs"
echo "    sudo systemctl restart radio.service   # restart stream"
echo ""
