import datetime
from manage_vless import VPNManager
import logging
import os
from dotenv import load_dotenv

logging.basicConfig(filename='/var/log/vless_autodel.log', level=logging.INFO, 
                    format='%(asctime)s %(message)s')

# Load .env
load_dotenv("/opt/vless/.env")

def auto_delete_idle_users():
    manager = VPNManager()
    
    # 1. Update Traffic Stats first
    manager.update_stats_from_xray() 
    
    # Get timeout from env (default 3)
    try:
        timeout_hours = int(os.getenv("IDLE_TIMEOUT_HOURS", 3))
    except:
        timeout_hours = 3

    # 2. Check Logic
    users = manager.get_users()
    cutoff_time = datetime.datetime.now() - datetime.timedelta(hours=timeout_hours)
    
    deleted_count = 0
    
    for user in users:
        # DB returns row objects or dicts
        username = user['username']
        is_persistent = user['is_persistent']
        last_active_str = user['last_active']
        
        # Parse timestamp
        # Depending on sqlite storage, might need parsing. 
        # Assuming ISO format storage by default python behavior if str
        try:
            last_active = datetime.datetime.fromisoformat(str(last_active_str))
        except:
            last_active = datetime.datetime.now() # Fail safe
            
        if is_persistent:
            continue
            
        if last_active < cutoff_time:
            # Check traffic diff - if logic requires confirming "idle" via traffic
            # For now, assuming last_active is updated by the update_stats_from_xray() logic when traffic flows
            logging.info(f"User {username} idle since {last_active}. Deleting.")
            manager.delete_user(username)
            deleted_count += 1
            
    if deleted_count > 0:
        logging.info(f"Cleaned up {deleted_count} idle users.")

if __name__ == "__main__":
    auto_delete_idle_users()
