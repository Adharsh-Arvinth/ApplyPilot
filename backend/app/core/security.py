import secrets
from fastapi import Header, HTTPException, status, Depends
from cryptography.fernet import Fernet
from backend.app.core.config import settings

# Initialize Fernet cipher for data encryption at rest
_fernet = None

def get_fernet() -> Fernet:
    global _fernet
    if _fernet is None:
        key = settings.APPLYPILOT_ENCRYPTION_KEY.encode()
        _fernet = Fernet(key)
    return _fernet

def encrypt_value(raw: str) -> str:
    """Encrypt a string at rest using AES-256 (Fernet)."""
    if not raw:
        return ""
    return get_fernet().encrypt(raw.encode()).decode()

def decrypt_value(cipher: str) -> str:
    """Decrypt a stored ciphertext."""
    if not cipher:
        return ""
    try:
        return get_fernet().decrypt(cipher.encode()).decode()
    except Exception:
        # Fallback if value was stored in plaintext
        return cipher

from typing import Optional

def verify_token(authorization: Optional[str] = Header(None)) -> bool:
    """
    Validate that incoming requests carry the correct Bearer token.
    Enforces that only the authenticated mobile app can access the PC backend.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header. Expected Bearer token.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    token = authorization.split("Bearer ", 1)[1].strip()
    if not secrets.compare_digest(token, settings.APPLYPILOT_TOKEN):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid security token. Phone access denied.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return True
