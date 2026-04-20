from __future__ import annotations

import secrets
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from auth import create_jwt, get_current_user, require_admin
from config import (
    FRONTEND_URL,
    GOOGLE_CLIENT_ID,
    GOOGLE_CLIENT_SECRET,
    OAUTH_REDIRECT_URI,
)
from database import get_db
from models.user import AllowedUser

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])

GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"


class InviteRequest(BaseModel):
    email: str = Field(..., min_length=3)
    name: str = Field("")
    role: str = Field("editor")


class UserResponse(BaseModel):
    id: UUID
    email: str
    name: str
    role: str

    model_config = {"from_attributes": True}


class MeResponse(BaseModel):
    email: str
    name: str
    role: str


@router.get("/login")
def login(response: Response) -> RedirectResponse:
    """Redirect to Google OAuth consent screen."""
    state = secrets.token_urlsafe(32)
    params = {
        "client_id": GOOGLE_CLIENT_ID,
        "redirect_uri": OAUTH_REDIRECT_URI,
        "response_type": "code",
        "scope": "openid email profile",
        "state": state,
        "access_type": "offline",
        "prompt": "consent",
    }
    query = "&".join(f"{k}={v}" for k, v in params.items())
    redirect = RedirectResponse(url=f"{GOOGLE_AUTH_URL}?{query}")
    redirect.set_cookie(
        key="oauth_state",
        value=state,
        httponly=True,
        samesite="lax",
        max_age=600,
    )
    return redirect


@router.get("/callback")
def callback(
    request: Request,
    code: str = "",
    state: str = "",
    db: Session = Depends(get_db),
) -> RedirectResponse:
    """Handle Google OAuth callback."""
    # CSRF check
    stored_state = request.cookies.get("oauth_state", "")
    if not state or not stored_state or state != stored_state:
        raise HTTPException(400, detail="Invalid OAuth state")

    # Exchange auth code for tokens
    token_data = {
        "code": code,
        "client_id": GOOGLE_CLIENT_ID,
        "client_secret": GOOGLE_CLIENT_SECRET,
        "redirect_uri": OAUTH_REDIRECT_URI,
        "grant_type": "authorization_code",
    }
    with httpx.Client() as client:
        token_resp = client.post(GOOGLE_TOKEN_URL, data=token_data)
    if token_resp.status_code != 200:
        raise HTTPException(400, detail="Failed to exchange auth code")

    tokens = token_resp.json()
    id_token = tokens.get("id_token", "")

    # Verify ID token via Google's tokeninfo endpoint
    with httpx.Client() as client:
        info_resp = client.get(
            GOOGLE_TOKENINFO_URL,
            params={"id_token": id_token},
        )
    if info_resp.status_code != 200:
        raise HTTPException(400, detail="Invalid ID token")

    info = info_resp.json()
    email = info.get("email", "")
    name = info.get("name", info.get("given_name", ""))

    # Verify audience
    if info.get("aud") != GOOGLE_CLIENT_ID:
        raise HTTPException(400, detail="Token audience mismatch")

    # Check allowlist
    user = db.query(AllowedUser).filter(AllowedUser.email == email).first()
    if not user:
        raise HTTPException(
            403,
            detail="Not authorized -- ask Nick for an invite",
        )

    # Issue JWT and redirect to frontend
    token = create_jwt(user.email, user.name, user.role)
    redirect = RedirectResponse(url=FRONTEND_URL, status_code=302)
    redirect.set_cookie(
        key="session_token",
        value=token,
        httponly=True,
        samesite="lax",
        max_age=7 * 24 * 3600,
    )
    redirect.delete_cookie("oauth_state")
    return redirect


@router.get("/me", response_model=MeResponse)
def me(user: AllowedUser = Depends(get_current_user)) -> MeResponse:
    """Return current user info."""
    return MeResponse(email=user.email, name=user.name, role=user.role)


@router.post("/logout")
def logout() -> dict[str, str]:
    """Clear the session cookie."""
    response = Response(
        content='{"message":"logged out"}',
        media_type="application/json",
    )
    response.delete_cookie("session_token")
    return response  # type: ignore[return-value]


@router.post("/invite", response_model=UserResponse)
def invite(
    data: InviteRequest,
    db: Session = Depends(get_db),
    admin: AllowedUser = Depends(require_admin),
) -> AllowedUser:
    """Invite a new user (admin only)."""
    if data.role not in ("admin", "editor", "viewer"):
        raise HTTPException(400, detail="Invalid role")
    existing = (
        db.query(AllowedUser).filter(AllowedUser.email == data.email).first()
    )
    if existing:
        raise HTTPException(409, detail="User already exists")
    user = AllowedUser(
        email=data.email,
        name=data.name,
        role=data.role,
        invited_by=admin.email,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.get("/users", response_model=list[UserResponse])
def list_users(
    db: Session = Depends(get_db),
    _admin: AllowedUser = Depends(require_admin),
) -> list[AllowedUser]:
    """List all allowed users (admin only)."""
    return db.query(AllowedUser).order_by(AllowedUser.created_at).all()


@router.delete("/users/{user_id}", status_code=204, response_model=None)
def delete_user(
    user_id: UUID,
    db: Session = Depends(get_db),
    _admin: AllowedUser = Depends(require_admin),
) -> None:
    """Remove a user (admin only)."""
    user = db.query(AllowedUser).filter(AllowedUser.id == user_id).first()
    if not user:
        raise HTTPException(404, detail="User not found")
    db.delete(user)
    db.commit()
