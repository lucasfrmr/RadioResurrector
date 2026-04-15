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
RADIO_SERVICE="/etc/systemd/system/radio.service"
WEB_SERVICE="/etc/systemd/system/radio-web.service"

echo ""
echo -e "${BOLD}  📻  RadioResurrector Setup${NC}"
echo "  ─────────────────────────────"
echo ""

# ── 1. Packages ─────────────────────────────────────────────────────────────
info "Installing packages (ffmpeg mpv alsa-utils python3-flask)..."
apt-get update -qq
apt-get install -y -qq ffmpeg mpv alsa-utils python3-flask
success "Packages installed"

# ── 2. Directories & files ───────────────────────────────────────────────────
info "Creating $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR" "$BUFFER_DIR"

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
