#!/bin/bash
# create_user.sh - Manual user creation
# Usage: ./create_user.sh <username> [-p]
# -p: Mark user as persistent (won't be auto-deleted)

# Load .env if exists
if [ -f "/opt/vless/.env" ]; then
    export $(grep -v '^#' "/opt/vless/.env" | xargs)
fi

API_PORT=${API_PORT:-8000}
API_URL="http://127.0.0.1:$API_PORT"
API_KEY_FILE="/opt/vless/api_key.txt"

if [ ! -f "$API_KEY_FILE" ]; then
    echo "Error: API Key not found. Is the system installed?"
    exit 1
fi

API_KEY=$(cat "$API_KEY_FILE")
USERNAME=""
PERSISTENT="false"

# Parse arguments
for arg in "$@"
do
    if [ "$arg" == "-p" ] || [ "$arg" == "--persistent" ]; then
        PERSISTENT="true"
    elif [[ "$arg" != -* ]]; then
        USERNAME="$arg"
    fi
done

if [ -z "$USERNAME" ]; then
    echo "Usage: $0 <username> [-p]"
    echo "  -p : Make user persistent (whitelist)"
    exit 1
fi

echo "Creating user: $USERNAME (Persistent: $PERSISTENT)..."
RESPONSE=$(curl -s -X POST "$API_URL/user" \
     -H "X-API-KEY: $API_KEY" \
     -H "Content-Type: application/json" \
     -d "{\"username\": \"$USERNAME\", \"persistent\": $PERSISTENT}")

echo "Response:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"

# Extract Link and Generate QR
LINK=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('link', ''))" 2>/dev/null)

if [ -n "$LINK" ]; then
    echo
    echo "QR Code:"
    if command -v qrencode &> /dev/null; then
        qrencode -t ANSIUTF8 "$LINK"
    else
        echo "qrencode not found. Install it to see QR codes (apt install qrencode)."
    fi
fi
