from fastapi import FastAPI, Header, HTTPException, Depends
from pydantic import BaseModel
from typing import Optional
import os
from manage_vless import VPNManager

app = FastAPI()
manager = VPNManager()

API_KEY_FILE = "/opt/vless/api_key.txt"

def get_api_key(x_api_key: str = Header(...)):
    if not os.path.exists(API_KEY_FILE):
        raise HTTPException(status_code=500, detail="Server not configured correctly (missing api key file)")
    
    with open(API_KEY_FILE, 'r') as f:
        valid_keys = [k.strip() for k in f.readlines() if k.strip()]
    
    if x_api_key not in valid_keys:
        raise HTTPException(status_code=403, detail="Invalid API Key")
    return x_api_key

class CreateUserRequest(BaseModel):
    username: Optional[str] = None
    persistent: bool = False

@app.post("/user")
def create_user(req: CreateUserRequest, api_key: str = Depends(get_api_key)):
    return manager.create_user(req.username, req.persistent)

@app.delete("/user/{username}")
def delete_user(username: str, api_key: str = Depends(get_api_key)):
    return manager.delete_user(username)

@app.get("/users")
def list_users(api_key: str = Depends(get_api_key)):
    return manager.get_users()

@app.delete("/users/delete_all")
def delete_all_users(force: bool = False, api_key: str = Depends(get_api_key)):
    """
    Deletes users. 
    By default (force=False), deletes only transient users.
    If force=True, deletes ALL users including persistent/whitelisted.
    """
    return manager.delete_all_users(force=force)

@app.get("/stats")
def server_stats(api_key: str = Depends(get_api_key)):
    return manager.get_stats()

class UpdateTokenRequest(BaseModel):
    token: Optional[str] = None

@app.post("/token/update")
def update_token(req: UpdateTokenRequest, api_key: str = Depends(get_api_key)):
    """
    Updates the API Token.
    If 'token' is provided, sets it.
    If not, generates a new random one.
    Returns the new token.
    """
    import secrets
    new_token = req.token
    if not new_token:
        new_token = secrets.token_hex(16)
    
    # Save to file
    try:
        with open(API_KEY_FILE, 'w') as f:
            f.write(new_token)
            
        # Also try to update .env if possible for consistency?
        # Python might not have permission to edit .env easily in a robust way without messy parsing.
        # Minimal viable: update the key file which is the source of truth for auth.
        
        return {"status": "updated", "new_token": new_token}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

