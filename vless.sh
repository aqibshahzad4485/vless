#!/bin/bash

# stealthAll.sh - Master Setup Script for Stealth VLESS VPN
# Non-interactive installation

# Variables
INSTALL_DIR="/opt/vless"
CERT_DIR="/etc/squid/ssl_cert" # Legacy support or shared path
XRAY_CONFIG="/usr/local/etc/xray/config.json"
API_PORT=${API_PORT:-8000}
API_KEY_FILE="$INSTALL_DIR/api_key.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 0. Cleanup
# We preserve vless.db on re-runs.
mkdir -p "$INSTALL_DIR"

# 1. Load .env if exists
if [ -f "$INSTALL_DIR/.env" ]; then
    echo "Loading .env..."
    set -a
    source "$INSTALL_DIR/.env"
    set +a
fi

# 2. Install Dependencies
echo "Installing dependencies..."
apt-get update
apt-get install -y curl wget unzip python3-pip python3-venv socat jq git openssl libssl-dev qrencode

# 3. Install/Update Xray
echo "Installing Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 4. Setup Python Environment
echo "Setting up Python environment..."
if [ ! -d "$INSTALL_DIR/venv" ]; then
    python3 -m venv "$INSTALL_DIR/venv"
fi
"$INSTALL_DIR/venv/bin/pip" install fastapi uvicorn pydantic requests

# 5. Config Generation Logic
mkdir -p "$INSTALL_DIR/ssl_cert"

# Determine Mode
MODE="reality"
DOMAIN="${DOMAIN:-}"

if [ -f "$INSTALL_DIR/server_ip.txt" ]; then
    PRESET_ADDR=$(cat "$INSTALL_DIR/server_ip.txt" | tr -d ' \n\r')
else
    # Detect IP
    PRESET_ADDR=$(curl -s https://api.ipify.org)
    echo "$PRESET_ADDR" > "$INSTALL_DIR/server_ip.txt"
fi

# Manual Static Certs
CERT_FULLCHAIN=""
CERT_KEY=""

if [ -f "$INSTALL_DIR/ssl_cert/fullchain.pem" ] && [ -f "$INSTALL_DIR/ssl_cert/privkey.pem" ]; then
    echo "Mode: Manual TLS (Static Certs found)"
    MODE="tls"
    CERT_FULLCHAIN="$INSTALL_DIR/ssl_cert/fullchain.pem"
    CERT_KEY="$INSTALL_DIR/ssl_cert/privkey.pem"
    
    # Try to extract domain from cert
    CN=$(openssl x509 -noout -subject -in "$CERT_FULLCHAIN" | sed -n 's/^.*CN = \(.*\)$/\1/p')
    if [[ -n "$CN" ]]; then DOMAIN="$CN"; fi
    if [[ "$DOMAIN" == *"*"* ]]; then DOMAIN=$(echo "$DOMAIN" | sed 's/\*\./vless./'); fi

elif [ -n "$DOMAIN" ]; then
    echo "Mode: Auto-TLS (Domain: $DOMAIN)"
    MODE="tls"
    
    # Check if we need to fetch certs
    if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        echo "Installing Certbot..."
        apt-get install -y certbot
        echo "Fetching Certificate for $DOMAIN..."
        certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN"
    fi
    
    CERT_FULLCHAIN="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    CERT_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    
    if [ ! -f "$CERT_FULLCHAIN" ]; then
        echo -e "${RED}[ERROR] Certificate fetch failed! Falling back to Reality.${NC}"
        MODE="reality"
    fi
fi

echo "$MODE" > "$INSTALL_DIR/connection_mode.txt"
if [ -n "$DOMAIN" ]; then echo "$DOMAIN" > "$INSTALL_DIR/server_domain.txt"; fi

# 6. Generate Xray Config
echo "Generating Xray config..."

VPN_PORT=${VPN_PORT:-443}

if [ "$MODE" == "reality" ]; then
    echo "Configuring REALITY..."
    
    # Generate Keys if not exist
    if [ ! -f "$INSTALL_DIR/reality_keys.json" ]; then
        /usr/local/bin/xray x25519 > "$INSTALL_DIR/reality_keys.json"
    fi
    
    PK=$(grep "Private key:" "$INSTALL_DIR/reality_keys.json" | awk '{print $3}')
    PBK=$(grep "Public key:" "$INSTALL_DIR/reality_keys.json" | awk '{print $3}')
    SID=$(openssl rand -hex 8)
    
    # Save for Python API to use
    echo "$PBK" > "$INSTALL_DIR/reality_pub.txt"
    echo "$SID" > "$INSTALL_DIR/reality_shortid.txt"
    
    # Generate Base Config with jq using REALITY
    jq -n --arg port "$VPN_PORT" --arg pk "$PK" --arg sid "$SID" \
    '{
        log: {loglevel: "warning"},
        inbounds: [
            {
                port: ($port|tonumber),
                protocol: "vless",
                settings: {clients: [], decryption: "none"},
                streamSettings: {
                    network: "tcp",
                    security: "reality",
                    realitySettings: {
                        show: false,
                        dest: "www.google.com:443",
                        xver: 0,
                        serverNames: ["www.google.com", "google.com"],
                        privateKey: $pk,
                        shortIds: [$sid]
                    }
                },
                sniffing: {enabled: true, destOverride: ["http", "tls"]}
            },
            {
                port: 10085,
                listen: "127.0.0.1",
                protocol: "dokodemo-door",
                settings: {address: "127.0.0.1"},
                tag: "api"
            }
        ],
        outbounds: [
            {protocol: "freedom", settings: {}},
            {protocol: "blackhole", tag: "blocked"}
        ],
        stats: {},
        api: {tag: "api", services: ["StatsService"]},
        policy: {
            levels: {"0": {statsUserUplink: true, statsUserDownlink: true}},
            system: {statsInboundUplink: true, statsInboundDownlink: true}
        }
    }' > "$XRAY_CONFIG"

elif [ "$MODE" == "tls" ]; then
    echo "Configuring TLS..."
    
    # Generate Base Config with jq using TLS
    jq -n --arg port "$VPN_PORT" --arg cert "$CERT_FULLCHAIN" --arg key "$CERT_KEY" \
    '{
        log: {loglevel: "warning"},
        inbounds: [
            {
                port: ($port|tonumber),
                protocol: "vless",
                settings: {clients: [], decryption: "none"},
                streamSettings: {
                    network: "tcp",
                    security: "tls",
                    tlsSettings: {
                        certificates: [{certificateFile: $cert, keyFile: $key}]
                    }
                },
                sniffing: {enabled: true, destOverride: ["http", "tls"]}
            },
            {
                port: 10085,
                listen: "127.0.0.1",
                protocol: "dokodemo-door",
                settings: {address: "127.0.0.1"},
                tag: "api"
            }
        ],
        outbounds: [
            {protocol: "freedom", settings: {}},
            {protocol: "blackhole", tag: "blocked"}
        ],
        stats: {},
        api: {tag: "api", services: ["StatsService"]},
        policy: {
            levels: {"0": {statsUserUplink: true, statsUserDownlink: true}},
            system: {statsInboundUplink: true, statsInboundDownlink: true}
        }
    }' > "$XRAY_CONFIG"
fi

# 7. Generate API Key if missing
if [ ! -f "$API_KEY_FILE" ]; then
    openssl rand -hex 16 > "$API_KEY_FILE"
fi

# 8. Copy Scripts
echo "Copying scripts to $INSTALL_DIR..."
# Assuming scripts are in current directory
[ -f manage_vless.py ] && cp manage_vless.py "$INSTALL_DIR/"
[ -f api_server.py ] && cp api_server.py "$INSTALL_DIR/"
[ -f auto_delete.py ] && cp auto_delete.py "$INSTALL_DIR/"
[ -f update_token.sh ] && cp update_token.sh "$INSTALL_DIR/"
[ -f create_user.sh ] && cp create_user.sh "$INSTALL_DIR/"
[ -f delete_user.sh ] && cp delete_user.sh "$INSTALL_DIR/"
[ -f delete_all_users.sh ] && cp delete_all_users.sh "$INSTALL_DIR/"

[ -f vless.db ] || touch "$INSTALL_DIR/vless.db" # Create DB if not exists
chown -R root:root "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/auto_delete.py"
chmod +x "$INSTALL_DIR/update_token.sh"
chmod +x "$INSTALL_DIR/create_user.sh"
chmod +x "$INSTALL_DIR/delete_user.sh"
chmod +x "$INSTALL_DIR/delete_all_users.sh"


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

# Check Xray
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}[OK] Xray is running.${NC}"
else
    echo -e "${RED}[ERROR] Xray failed to start!${NC}"
    systemctl status xray
fi

# Cron Job
(crontab -l 2>/dev/null; echo "*/10 * * * * cd $INSTALL_DIR && $INSTALL_DIR/venv/bin/python3 auto_delete.py >> /var/log/vless_autodel.log 2>&1") | crontab -

echo 
echo "-----------------------------------------------------"
echo -e "${GREEN}Installation Complete!${NC}"
echo "API Key loaded in: $API_KEY_FILE"
echo "API Key: $(cat $API_KEY_FILE)"
echo "-----------------------------------------------------"