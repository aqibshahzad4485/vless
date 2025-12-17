#!/bin/bash

# update_token.sh - Update API Token
# Usage: ./update_token.sh [new_token]

INSTALL_DIR="/opt/vless"
API_KEY_FILE="$INSTALL_DIR/api_key.txt"
ENV_FILE="$INSTALL_DIR/.env"

if [ -n "$1" ]; then
    NEW_TOKEN="$1"
else
    # Generate random
    NEW_TOKEN=$(openssl rand -hex 16)
fi

echo "Updating API Token..."
echo "$NEW_TOKEN" > "$API_KEY_FILE"
echo "New Token: $NEW_TOKEN"

# Also update .env if it exists to persist across re-runs
if [ -f "$ENV_FILE" ]; then
    # Check if API_TOKEN exists
    if grep -q "API_TOKEN=" "$ENV_FILE"; then
        sed -i "s/^API_TOKEN=.*/API_TOKEN=$NEW_TOKEN/" "$ENV_FILE"
    else
        echo "API_TOKEN=$NEW_TOKEN" >> "$ENV_FILE"
    fi
    echo "Updated .env as well."
fi

# Service restart not strictly needed if API reads file on request, 
# but good practice to ensure env vars are reloaded if used elsewhere.
# However, user requested hot update capability.
# api_server.py reads file on every request, so it works immediately.
echo "Token updated successfully."
