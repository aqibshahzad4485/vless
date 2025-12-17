#!/bin/bash
# delete_user.sh - Manual user deletion

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
USERNAME=$1

if [ -z "$USERNAME" ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

echo "Deleting user: $USERNAME..."
RESPONSE=$(curl -s -X DELETE "$API_URL/user/$USERNAME" \
     -H "X-API-KEY: $API_KEY")

echo "Response:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
