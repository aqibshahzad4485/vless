import json
import uuid
import os
import sqlite3
import subprocess
import datetime
from typing import Optional, List, Dict

# Configuration
XRAY_CONFIG_PATH = "/usr/local/etc/xray/config.json"
DB_PATH = "/opt/vless/vless.db"
WHITELIST_PATH = "/opt/vless/whitelist.txt"

class VPNManager:
    def __init__(self):
        self.init_db()

    def init_db(self):
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute('''CREATE TABLE IF NOT EXISTS users
                     (id INTEGER PRIMARY KEY, username TEXT UNIQUE, uuid TEXT, 
                      created_at TIMESTAMP, traffic_up INTEGER DEFAULT 0, 
                      traffic_down INTEGER DEFAULT 0, last_active TIMESTAMP, 
                      is_persistent BOOLEAN)''')
        c.execute('''CREATE TABLE IF NOT EXISTS server_stats
                     (id INTEGER PRIMARY KEY, timestamp TIMESTAMP, action TEXT, 
                      details TEXT)''')
        conn.commit()
        conn.close()

    def _sync_whitelist_file(self):
        """Syncs DB persistent users to whitelist.txt for legacy/backup support"""
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("SELECT username FROM users WHERE is_persistent = 1")
        users = [r[0] for r in c.fetchall()]
        conn.close()
        try:
            with open(WHITELIST_PATH, 'w') as f:
                f.write('\n'.join(users))
        except:
            pass

    def get_xray_config(self) -> Dict:
        if not os.path.exists(XRAY_CONFIG_PATH):
            return {"inbounds": [], "outbounds": []} # Default empty
        with open(XRAY_CONFIG_PATH, 'r') as f:
            return json.load(f)

    def save_xray_config(self, config: Dict):
        with open(XRAY_CONFIG_PATH, 'w') as f:
            json.dump(config, f, indent=4)
        # Restart Xray
        subprocess.run(["systemctl", "restart", "xray"], check=False)

    def create_user(self, username: Optional[str] = None, persistent: bool = False) -> Dict:
        if not username:
            username = f"user_{uuid.uuid4().hex[:8]}"
        
        user_uuid = str(uuid.uuid4())
        
        # 1. Update DB
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        try:
            c.execute("INSERT INTO users (username, uuid, created_at, last_active, is_persistent) VALUES (?, ?, ?, ?, ?)",
                      (username, user_uuid, datetime.datetime.now(), datetime.datetime.now(), persistent))
            conn.commit()
            
            # Log stat
            bg_user_count = c.execute("SELECT count(*) FROM users").fetchone()[0]
            c.execute("INSERT INTO server_stats (timestamp, action, details) VALUES (?, ?, ?)",
                      (datetime.datetime.now(), "create", f"User created: {username}. Total: {bg_user_count}"))
            conn.commit()
        except sqlite3.IntegrityError:
            # User already exists
            existing = c.execute("SELECT uuid FROM users WHERE username = ?", (username,)).fetchone()
            if existing:
                user_uuid = existing[0]
            else:
                conn.close()
                return {"error": "User collision error", "username": username}
            # Continue execution to return link
        conn.close()

        if persistent:
            self._sync_whitelist_file()

        # 2. Update Xray Config
        config = self.get_xray_config()
        # Ensure VLESS inbound exists
        vless_inbound = next((i for i in config.get("inbounds", []) if i.get("protocol") == "vless"), None)
        if not vless_inbound:
            # Create default VLESS inbound if missing (simplified for brevity, assumes config exists mostly)
            # Fetching port 443 inbound usually
            pass # Assumes setup_vless.sh created the structure.
            
        # Add client to first VLESS inbound
        for inbound in config.get("inbounds", []):
            if inbound["protocol"] == "vless":
                clients = inbound["settings"]["clients"]
                # Check if user exists in config
                user_found = False
                for client in clients:
                    if client.get("email") == username:
                        user_found = True
                        # Update UUID if different (should not happen usually but good for sync)
                        if client.get("id") != user_uuid:
                            client["id"] = user_uuid
                        break
                
                if not user_found:
                    clients.append({"id": user_uuid, "email": username})
                break
        
        self.save_xray_config(config)
        
        # Get Server IP/Domain based on preference
        # If server_ip.txt contains a domain (has dots and not an IP, mostly), use it?
        # User said "update the .../server_ip.txt to the domain then it should work".
        # So we trust server_ip.txt content as the address.
        server_address = "YOUR_IP"
        ip_file = "/opt/vless/server_ip.txt"
        
        if os.path.exists(ip_file):
            with open(ip_file, 'r') as f:
                server_address = f.read().strip()
        
        # Fallback
        if server_address == "YOUR_IP" or not server_address:
             try:
                import urllib.request
                server_address = urllib.request.urlopen('https://api.ipify.org').read().decode('utf8').strip()
             except: pass

        # Check Mode
        mode = "reality"
        if os.path.exists("/opt/vless/connection_mode.txt"):
            with open("/opt/vless/connection_mode.txt", 'r') as f:
                mode = f.read().strip()

        # Find Port from Config
        server_port = 443
        for inbound in config.get("inbounds", []):
            if inbound.get("protocol") == "vless":
                server_port = inbound.get("port", 443)
                break

        if mode == "tls":
            # TLS Mode
            # Get SNI Domain
            sni_domain = ""
            domain_file = "/opt/vless/server_domain.txt"
            if os.path.exists(domain_file):
                with open(domain_file, 'r') as f:
                    sni_domain = f.read().strip()
            
            # If server_address is a domain, use it as SNI default if sni not set
            if not sni_domain and not server_address[0].isdigit():
                 sni_domain = server_address

            sni_param = f"&sni={sni_domain}" if sni_domain else ""
            link = f"vless://{user_uuid}@{server_address}:{server_port}?encryption=none&security=tls&type=tcp&headerType=none{sni_param}#{username}"
        
        else:
            # REALITY Mode
            # Need Public Key
            pbk = ""
            if os.path.exists("/opt/vless/reality_pub.txt"):
                with open("/opt/vless/reality_pub.txt", 'r') as f:
                    pbk = f.read().strip()
            
            # Need ShortId
            sid = ""
            if os.path.exists("/opt/vless/reality_shortid.txt"):
                with open("/opt/vless/reality_shortid.txt", 'r') as f:
                    sid = f.read().strip()

            sni_server = "www.google.com" # Matches config
            # Reality Link: security=reality&sni=google.com&fp=chrome&pbk=...&type=tcp
            link = f"vless://{user_uuid}@{server_address}:{server_port}?encryption=none&security=reality&sni={sni_server}&fp=chrome&type=tcp&pbk={pbk}&sid={sid}#{username}"

        return {
            "username": username,
            "uuid": user_uuid, 
            "link": link
        }

    def delete_user(self, username: str):
        # 1. DB
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("DELETE FROM users WHERE username = ?", (username,))
        deleted = c.rowcount > 0
        
        # Log
        bg_user_count = c.execute("SELECT count(*) FROM users").fetchone()[0]
        c.execute("INSERT INTO server_stats (timestamp, action, details) VALUES (?, ?, ?)",
                  (datetime.datetime.now(), "delete", f"User deleted: {username}. Total: {bg_user_count}"))
        conn.commit()
        conn.close()

        self._sync_whitelist_file()

        if not deleted:
            return {"error": "User not found"}

        # 2. Xray
        config = self.get_xray_config()
        changed = False
        for inbound in config.get("inbounds", []):
            if inbound["protocol"] == "vless":
                new_clients = [cl for cl in inbound["settings"]["clients"] if cl["email"] != username]
                if len(new_clients) != len(inbound["settings"]["clients"]):
                    inbound["settings"]["clients"] = new_clients
                    changed = True
        
        if changed:
            self.save_xray_config(config)
            return {"status": "deleted", "username": username}
        return {"status": "deleted_from_db_only", "username": username}

    def delete_transient_users(self):
        """Deletes all non-persistent users"""
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("SELECT username FROM users WHERE is_persistent = 0")
        users_to_delete = [r[0] for r in c.fetchall()]
        conn.close()
        
        deleted_count = 0
        deleted_users = []
        for user in users_to_delete:
            res = self.delete_user(user)
            if "error" not in res:
                deleted_count += 1
                deleted_users.append(user)
                
        return {"deleted_count": deleted_count, "users": deleted_users}

    def delete_all_users(self, force: bool = False):
        """Deletes ALL users. If force=True, deletes whitelisted too."""
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        if force:
            c.execute("SELECT username FROM users")
        else:
            c.execute("SELECT username FROM users WHERE is_persistent = 0")
        
        users_to_delete = [r[0] for r in c.fetchall()]
        conn.close()
        
        deleted_count = 0
        deleted_users = []
        for user in users_to_delete:
            res = self.delete_user(user)
            if "error" not in res:
                deleted_count += 1
                deleted_users.append(user)
                
        return {"deleted_count": deleted_count, "users": deleted_users}

    def get_users(self):
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        c.execute("SELECT * FROM users")
        rows = [dict(row) for row in c.fetchall()]
        conn.close()
        return rows

    def get_stats(self):
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        total_users = c.execute("SELECT count(*) FROM users").fetchone()[0]
        active_users = c.execute("SELECT count(*) FROM users WHERE last_active > ?", 
                                 (datetime.datetime.now() - datetime.timedelta(hours=1),)).fetchone()[0]
        # Get history (last 50 events)
        c.execute("SELECT timestamp, action, details FROM server_stats ORDER BY timestamp DESC LIMIT 50")
        history = [{"time": r[0], "action": r[1], "details": r[2]} for r in c.fetchall()]
        conn.close()
        return {
            "total_users": total_users,
            "active_users_last_1h": active_users,
            "history": history
        }

    def update_stats_from_xray(self):
        """Called by cron to query Xray stats and update DB"""
        # Query Xray API for all user stats
        try:
            # We need to query 'user>>>email>>>traffic>>>downlink' and uplink
            # This is complex with raw API. Using a simplified approach:
            # Parse `xray api statsquery` output if available, or just check if traffic changed.
            # Assuming `xray` binary is in path.
            
            # Fetch Uplink
            cmd_up = ["/usr/local/bin/xray", "api", "statsquery", "--server=127.0.0.1:10085", "--pattern", "user>>>*>>>traffic>>>uplink"]
            res_up = subprocess.run(cmd_up, capture_output=True, text=True)
            
            # Fetch Downlink
            cmd_down = ["/usr/local/bin/xray", "api", "statsquery", "--server=127.0.0.1:10085", "--pattern", "user>>>*>>>traffic>>>downlink"]
            res_down = subprocess.run(cmd_down, capture_output=True, text=True)

            if res_up.returncode != 0 or res_down.returncode != 0:
                print("Error querying Xray stats")
                return

            def parse_xray_output(output):
                # Output format: "user>>>email>>>traffic>>>uplink: 12345"
                data = {}
                for line in output.splitlines():
                    if "value" in line and "name" in line: # JSON format usually?
                        pass 
                    # Actually `xray api statsquery` returns JSONish or text depending on version.
                    # Standard simplified output:
                    # name: user>>>email>>>traffic>>>uplink  value: 1024
                    parts = line.split()
                    if len(parts) >= 4 and "name:" in line:
                         name = parts[1]
                         value = int(parts[3])
                         email = name.split(">>>")[1]
                         data[email] = value
                return data

            # Note: The output format of `xray api statsquery` depends on the tool version.
            # Assuming standard text output. If JSON, need json.loads.
            # Let's try to handle JSON if the command supports -json or detects it?
            # Default is proto/text.
            
            # Parsing simplified text output (heuristic)
            # "stat: user>>>foo>>>traffic>>>uplink 100"
            
            # Better approach:
            # Iterate known users and query them specifically if pattern fails?
            # No, pattern is better.
            
            current_uplinks = {}
            current_downlinks = {}
            
            # Manual parse of standard output
            for line in res_up.stdout.splitlines():
                if "user>>>" in line:
                    parts = line.strip().split()
                    # Pattern: name: ... value: ...
                    try:
                        name_idx = parts.index("name:") + 1
                        val_idx = parts.index("value:") + 1
                        name = parts[name_idx]
                        val = int(parts[val_idx])
                        email = name.split(">>>")[1]
                        current_uplinks[email] = val
                    except:
                        pass

            for line in res_down.stdout.splitlines():
                if "user>>>" in line:
                    parts = line.strip().split()
                    try:
                        name_idx = parts.index("name:") + 1
                        val_idx = parts.index("value:") + 1
                        name = parts[name_idx]
                        val = int(parts[val_idx])
                        email = name.split(">>>")[1]
                        current_downlinks[email] = val
                    except:
                        pass

            # Update DB
            conn = sqlite3.connect(DB_PATH)
            c = conn.cursor()
            users = c.execute("SELECT username, traffic_up, traffic_down, last_active FROM users").fetchall()
            
            for u in users:
                username = u[0]
                old_up = u[1]
                old_down = u[2]
                
                new_up = current_uplinks.get(username, old_up)
                new_down = current_downlinks.get(username, old_down)
                
                # Check for activity
                # Note: Xray stats accumulate? Yes.
                # If generated logic resets stats, we need to handle that. 
                # StatsService usually valid until Xray restart.
                
                if new_up > old_up or new_down > old_down:
                    # Activity detected
                    c.execute("UPDATE users SET traffic_up=?, traffic_down=?, last_active=? WHERE username=?",
                              (new_up, new_down, datetime.datetime.now(), username))
                else:
                    # Just update stats, not last_active
                     c.execute("UPDATE users SET traffic_up=?, traffic_down=? WHERE username=?",
                              (new_up, new_down, username))
            
            conn.commit()
            conn.close()

        except Exception as e:
            print(f"Stats update failed: {e}")
