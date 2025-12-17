#!/bin/bash
# delete_all_users.sh - Deletes all non-persistent (transient) users

# Load .env if exists
if [ -f "/opt/vless/.env" ]; then
    export $(grep -v '^#' "/opt/vless/.env" | xargs)
fi

API_PORT=${API_PORT:-8000}
API_URL="http://127.0.0.1:$API_PORT"
API_KEY_FILE="/opt/vless/api_key.txt"
RED='\033[0;31m'
NC='\033[0m'

if [ ! -f "$API_KEY_FILE" ]; then
    echo "Error: API Key not found. Is the system installed?"
    exit 1
fi

API_KEY=$(cat "$API_KEY_FILE")


# Check for -p flag (Purge/Delete All including persistent)
FORCE_DELETE=false
if [[ "$1" == "-p" ]]; then
    FORCE_DELETE=true
fi

if [ "$FORCE_DELETE" = true ]; then
    echo -e "${RED}WARNING: This will delete ALL users (including Persistent/Whitelisted).${NC}"
else
    echo -e "WARNING: This will delete ALL non-persistent (transient) users."
fi
read -p "Are you sure? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

if [ "$FORCE_DELETE" = true ]; then
    echo "Deleting EVERYONE..."
    ENDPOINT="$API_URL/users/delete_all?force=true"
else
    echo "Deleting transient users..."
    ENDPOINT="$API_URL/users/delete_all?force=false"
fi

RESPONSE=$(curl -s -X DELETE "$ENDPOINT" \
     -H "X-API-KEY: $API_KEY")

echo "Response:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
