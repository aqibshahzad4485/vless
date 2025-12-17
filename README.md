# Stealth VLESS VPN Solution

A complete solution for deploying a stealthy VLESS VPN with automated user management, idle cleanup, and API access.

## Features

- **Security**:
    - **Internet Access**: Allowed.
    - **Local/Private Access**: **Configurable** (Default: Blocked). Control via `.env`.
    - **Isolation**: Users cannot access each other.
- **Hybrid Mode**:
    - **Default (IP-Based)**: Uses VLESS-REALITY.
    - **Domain (TLS)**: VLESS-TLS with Auto-LetsEncrypt or Manual Certs.
- **Safe Updates**: Re-running `vless.sh` updates the system without deleting users or data.
- **API Management**: FastAPI service running on port 8000 (protected by API Key).
- **Auto-Deletion**: Cron job checks every 10 minutes. Deletes users who are idle > 3 hours.
- **Persistence**: Whitelisted users are not auto-deleted.
- **Statistics**: API tracks traffic, creation time, and server-level history.
- **Manual CLI**: `create_user.sh` and `delete_user.sh` for easy management.
- **QR Codes**: Links are displayed as QR codes for easy scanning.

## Configuration (.env)

You can customize the deployment by creating a `.env` file in the installation directory. A template `.env.example` is provided.

**Supported Variables:**
*   `DOMAIN`: Set your domain here (e.g., `vpn.example.com`) to enable **Auto-TLS**.
*   `BLOCK_LOCAL_ACCESS`: `true` (default) or `false`. Blocks/Allows access to private/LAN IPs.
*   `IDLE_TIMEOUT_HOURS`: Number of hours (default `3`) before an idle user is deleted.
*   `VPN_PORT`: Custom port for the VPN (Default: `443`).
*   `API_PORT`: Port for the management API (Default: `8000`).
*   `API_TOKEN`: Manually set your API key.

## Installation & Modes

1.  Upload or clone the scripts to your server (e.g., `/root/vless` or `git clone https://github.com/aqibshahzad4485/vless.git /root/vless`).
2.  (Optional) Create/Edit `.env` to set your preferences (e.g., `cd /root/vless && cp .env.example .env && nano .env`).
3.  Run `chmod +x vless.sh && ./vless.sh`.

### Mode A: Default (REALITY / IP-Based)
*   **Condition**: variable `DOMAIN` is empty.
*   **Result**: Uses VLESS-REALITY on the public IP. No certificates needed.

### Mode B: Auto-TLS (LetsEncrypt)
*   **Condition**: variable `DOMAIN` is set (e.g., `vpn.mydomain.com`) AND point to server IP.
*   **Result**: Installs Certbot, fetches valid HTTPS certs, and configures VLESS-TLS.

### Mode C: Manual TLS (Static Certs)
*   **Condition**: Files exist in `/opt/vless/ssl_cert/` (`fullchain.pem`, `privkey.pem`).
*   **Result**: Uses your provided certificates. Ignores `.env` domain logic for cert generation, but uses it for link generation.

---

4.  After setup, resources are installed to `/opt/vless/`.
5.  Service runs automatically. Restart if needed: `systemctl restart vless-api`.
6.  API Key is in `/opt/vless/api_key.txt` (or what you set in `.env`).

## Usage

### Manual Management (CLI)

*   **Create a User**:
    ```bash
    ./create_user.sh myuser          # Transient (auto-deleted if idle)
    ./create_user.sh myuser -p       # Persistent (NEVER auto-deleted)
    ```
    *If the user already exists, it will simply return the existing profile/link.*

*   **Delete a User**:
    ```bash
    ./delete_user.sh myuser
    ```
*   **Delete All Users**:
    ```bash
    ./delete_all_users.sh            # Deletes ONLY transient/idle users
    ./delete_all_users.sh -p         # WARNING: Deletes ALL users (including persistent/whitelisted)
    ```

*   **Update API Token**:
    ```bash
    ./update_token.sh                # Regenerates a random token
    ./update_token.sh mynewtoken     # Sets to 'mynewtoken'
    ```

### API Usage

*   **Endpoint**: `http://YOUR_IP/DOMAIN:API_PORT`
*   **Auth Header**: `X-API-KEY: <your-key>`

#### Endpoints
*   `POST /user`: Create/Fetch user (JSON body: `{"username": "myuser", "persistent": false}`). 
    *   Set `"persistent": true` to **disable auto-deletion** for this user. They will remain until manually deleted.
*   `GET /users`: List all users and their traffic/stats.
*   `DELETE /user/{username}`: Delete a user.
*   `DELETE /users/delete_all?force=true|false`: Delete users. Default (`force=false`) deletes only transient users. `force=true` deletes all (including persistent).
*   `GET /stats`: View server-level history and total counts.
*   `POST /token/update`: Update API Token (JSON body: `{"token": "optional_new_token"}`). Returns new token.

## Auto-Deletion Logic

*   Runs every 10 minutes.
*   Checks if a user has been **idle** for more than **3 hours** (Configurable in `.env` via `IDLE_TIMEOUT_HOURS`).
*   If `persistent` is False, the user is deleted.
*   If `persistent` is True (or in whitelist), the user is kept safe.

## Files Structure

*   `/opt/vless/`
    *   `vless.sh`: Setup script.
    *   `manage_vless.py`: Core logic & Database handler.
    *   `api_server.py`: API Service.
    *   `update_token.sh`: Token update utility.

    *   `auto_delete.py`: Cron script.
    *   `vless.db`: SQLite database for stats.
    *   `api_key.txt`: Generated API Key.
