from __future__ import annotations

import os
import secrets
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, Request, Security
from fastapi.security import APIKeyHeader
from sqlalchemy.orm import Session

from config import GOOGLE_CLIENT_ID, JWT_SECRET
from database import get_db
from logging_config import get_audit_logger
from models.user import AllowedUser

_header = APIKeyHeader(name="X-API-Key", auto_error=False)
audit = get_audit_logger()

API_KEY = os.getenv("API_KEY", "")

JWT_ALGORITHM = "HS256"
JWT_EXPIRY_DAYS = 7


def create_jwt(email: str, name: str, role: str) -> str:
    """Create a JWT token with 7-day expiry."""
    payload = {
        "sub": email,
        "name": name,
        "role": role,
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + timedelta(days=JWT_EXPIRY_DAYS),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_jwt(token: str) -> dict:
    """Decode and validate a JWT token."""
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        audit.warning("JWT_EXPIRED token presented")
        raise HTTPException(401, detail="Token expired")
    except jwt.InvalidTokenError:
        audit.warning("JWT_INVALID token presented")
        raise HTTPException(401, detail="Invalid token")


def get_api_key(key: str | None = Security(_header)) -> str:
    """Validate API key (kept for backward compatibility)."""
    if not API_KEY:
        raise HTTPException(503, detail="Server not configured")
    if not key or not secrets.compare_digest(key, API_KEY):
        audit.warning("API_KEY_REJECTED")
        raise HTTPException(401, detail="Invalid or missing API key")
    return key


def get_current_user(
    request: Request,
    db: Session = Depends(get_db),
    key: str | None = Security(_header),
) -> AllowedUser:
    """Authenticate via JWT cookie first, then fall back to API key.

    Returns the AllowedUser record for the authenticated user.
    """
    # Try JWT cookie first
    token = request.cookies.get("session_token")
    if token:
        payload = decode_jwt(token)
        email = payload.get("sub", "")
        user = db.query(AllowedUser).filter(AllowedUser.email == email).first()
        if user:
            return user
        audit.warning("AUTH_DENIED email=%s reason=not_in_allowlist", email)
        raise HTTPException(401, detail="User not found in allowlist")

    # Fall back to API key
    if API_KEY and key and secrets.compare_digest(key, API_KEY):
        # Return the admin user for API key auth
        admin = (
            db.query(AllowedUser)
            .filter(AllowedUser.role == "admin")
            .first()
        )
        if admin:
            return admin
        # Synthetic admin if no admin user exists yet (e.g., tests)
        return AllowedUser(
            email="api-key@system",
            name="API Key User",
            role="admin",
        )

    audit.warning("AUTH_MISSING no JWT cookie or API key")
    raise HTTPException(401, detail="Not authenticated")


def require_admin(
    user: AllowedUser = Depends(get_current_user),
) -> AllowedUser:
    """Require admin role."""
    if user.role != "admin":
        audit.warning(
            "ADMIN_DENIED email=%s role=%s", user.email, user.role,
        )
        raise HTTPException(403, detail="Admin access required")
    return user
