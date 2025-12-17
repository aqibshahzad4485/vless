#!/bin/bash

# stealthAll.sh - Master Setup Script for Stealth VLESS VPN
# Non-interactive installation

# Variables
INSTALL_DIR="/opt/vless"
CERT_DIR="/etc/squid/ssl_cert"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
API_PORT=${API_PORT:-8000}
API_KEY_FILE="$INSTALL_DIR/api_key.txt"

# ... (rest of file)

# 0. Cleanup
# We preserve vless.db on re-runs.

# ...

# 5. Config Generation
mkdir -p "/opt/vless/ssl_cert"

# ...

if [ -f "$INSTALL_DIR/server_ip.txt" ]; then
    PRESET_ADDR=$(cat "$INSTALL_DIR/server_ip.txt" | tr -d ' \n\r')
fi

# ...

# Manual Static Certs
if [ -f "/opt/vless/ssl_cert/fullchain.pem" ] && [ -f "/opt/vless/ssl_cert/privkey.pem" ]; then
    echo "Mode: Manual TLS (Static Certs found)"
    MODE="tls"
    CERT_FULLCHAIN="/opt/vless/ssl_cert/fullchain.pem"
    CERT_KEY="/opt/vless/ssl_cert/privkey.pem"

# ...

if [[ "$CERT_FULLCHAIN" == *"/opt/vless/"* ]]; then
     CN=$(openssl x509 -noout -subject -in "$CERT_FULLCHAIN" | sed -n 's/^.*CN = \(.*\)$/\1/p')
     if [[ -n "$CN" ]]; then DOMAIN="$CN"; fi
     if [[ "$DOMAIN" == *"*"* ]]; then DOMAIN=$(echo "$DOMAIN" | sed 's/\*\./vless./'); fi
fi

# ...

# 8. Copy Scripts
echo "Copying scripts to $INSTALL_DIR..."
[ -f manage_vless.py ] && cp manage_vless.py "$INSTALL_DIR/"
[ -f api_server.py ] && cp api_server.py "$INSTALL_DIR/"
[ -f auto_delete.py ] && cp auto_delete.py "$INSTALL_DIR/"
[ -f update_token.sh ] && cp update_token.sh "$INSTALL_DIR/"
[ -f vless.db ] || touch "$INSTALL_DIR/vless.db" # Create DB if not exists
chown -R root:root "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/auto_delete.py"
chmod +x "$INSTALL_DIR/update_token.sh"

# 9. Create Systemd Service for API
echo "Creating API Service..."
cat <<EOF > /etc/systemd/system/vless-api.service
[Unit]
Description=VLESS VPN API Service
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/uvicorn api_server:app --host 0.0.0.0 --port $API_PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 10. Start Services
echo "Starting Services..."
systemctl daemon-reload
systemctl enable xray vless-api
systemctl restart xray vless-api

echo "Verifying..."
sleep 2

# Check API
if systemctl is-active --quiet vless-api; then
    echo -e "${GREEN}[OK] VLESS API is running.${NC}"
else
    echo -e "${RED}[ERROR] VLESS API failed to start!${NC}"
    echo "Last 10 lines of API Log:"
    journalctl -u vless-api -n 10 --no-pager
fi

# ...

# Cron Job
(crontab -l 2>/dev/null; echo "*/10 * * * * cd $INSTALL_DIR && $INSTALL_DIR/venv/bin/python3 auto_delete.py >> /var/log/vless_autodel.log 2>&1") | crontab -
