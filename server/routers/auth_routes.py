from __future__ import annotations

import secrets
from datetime import timedelta
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from auth import create_jwt, decode_jwt, get_current_user, require_admin
from config import (
    FRONTEND_URL,
    GOOGLE_CLIENT_ID,
    GOOGLE_CLIENT_SECRET,
    GOOGLE_IOS_CLIENT_ID,
    MOBILE_APP_SCHEME,
    MOBILE_REDIRECT_URI,
    OAUTH_REDIRECT_URI,
)
from database import get_db
from logging_config import get_audit_logger
from models.user import AllowedUser

audit = get_audit_logger()

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])

GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"


class GoogleIdTokenRequest(BaseModel):
    id_token: str = Field(..., min_length=1)


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


class TokenResponse(BaseModel):
    token: str
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
        audit.warning("OAUTH_CSRF_MISMATCH")
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
        audit.warning("OAUTH_TOKEN_EXCHANGE_FAILED status=%s", token_resp.status_code)
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
        audit.warning("OAUTH_ID_TOKEN_INVALID status=%s", info_resp.status_code)
        raise HTTPException(400, detail="Invalid ID token")

    info = info_resp.json()
    email = info.get("email", "")
    name = info.get("name", info.get("given_name", ""))

    # Verify audience
    if info.get("aud") != GOOGLE_CLIENT_ID:
        audit.warning("OAUTH_AUDIENCE_MISMATCH aud=%s", info.get("aud"))
        raise HTTPException(400, detail="Token audience mismatch")

    # Check allowlist
    user = db.query(AllowedUser).filter(AllowedUser.email == email).first()
    if not user:
        audit.warning("OAUTH_DENIED email=%s reason=not_in_allowlist", email)
        raise HTTPException(
            403,
            detail="Not authorized -- ask Nick for an invite",
        )

    # Issue JWT and redirect to frontend
    audit.info("LOGIN_SUCCESS email=%s role=%s", user.email, user.role)
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
    audit.info(
        "USER_INVITED email=%s role=%s by=%s",
        user.email, user.role, admin.email,
    )
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
    audit.info("USER_DELETED email=%s by=admin", user.email)
    db.delete(user)
    db.commit()


# ---------------------------------------------------------------------------
# Mobile OAuth flow (iOS / Android)
#
# Instead of setting a cookie, the mobile callback redirects to the app's
# custom URL scheme with the JWT as a query parameter:
#   recipeapp://auth?token=<jwt>
#
# The iOS app opens the /mobile/login URL in ASWebAuthenticationSession,
# which captures the redirect and extracts the token.
# ---------------------------------------------------------------------------


@router.get("/mobile/login")
def mobile_login(response: Response) -> RedirectResponse:
    """Redirect to Google OAuth for mobile clients."""
    state = secrets.token_urlsafe(32)
    params = {
        "client_id": GOOGLE_CLIENT_ID,
        "redirect_uri": MOBILE_REDIRECT_URI,
        "response_type": "code",
        "scope": "openid email profile",
        "state": state,
        "access_type": "offline",
        "prompt": "consent",
    }
    query = "&".join(f"{k}={v}" for k, v in params.items())
    redirect = RedirectResponse(url=f"{GOOGLE_AUTH_URL}?{query}")
    redirect.set_cookie(
        key="mobile_oauth_state",
        value=state,
        httponly=True,
        samesite="lax",
        max_age=600,
    )
    return redirect


@router.get("/mobile/callback")
def mobile_callback(
    request: Request,
    code: str = "",
    state: str = "",
    db: Session = Depends(get_db),
) -> RedirectResponse:
    """Handle Google OAuth callback for mobile clients.

    Redirects to recipeapp://auth?token=<jwt> on success,
    or recipeapp://auth?error=<message> on failure.
    """
    error_url = f"{MOBILE_APP_SCHEME}://auth?error="

    # CSRF check
    stored_state = request.cookies.get("mobile_oauth_state", "")
    if not state or not stored_state or state != stored_state:
        audit.warning("MOBILE_OAUTH_CSRF_MISMATCH")
        return RedirectResponse(url=f"{error_url}csrf_mismatch", status_code=302)

    # Exchange auth code for tokens
    token_data = {
        "code": code,
        "client_id": GOOGLE_CLIENT_ID,
        "client_secret": GOOGLE_CLIENT_SECRET,
        "redirect_uri": MOBILE_REDIRECT_URI,
        "grant_type": "authorization_code",
    }
    with httpx.Client() as client:
        token_resp = client.post(GOOGLE_TOKEN_URL, data=token_data)
    if token_resp.status_code != 200:
        audit.warning(
            "MOBILE_OAUTH_TOKEN_EXCHANGE_FAILED status=%s",
            token_resp.status_code,
        )
        return RedirectResponse(url=f"{error_url}token_exchange_failed", status_code=302)

    tokens = token_resp.json()
    id_token = tokens.get("id_token", "")

    # Verify ID token
    with httpx.Client() as client:
        info_resp = client.get(GOOGLE_TOKENINFO_URL, params={"id_token": id_token})
    if info_resp.status_code != 200:
        audit.warning("MOBILE_OAUTH_ID_TOKEN_INVALID status=%s", info_resp.status_code)
        return RedirectResponse(url=f"{error_url}invalid_id_token", status_code=302)

    info = info_resp.json()
    email = info.get("email", "")
    name = info.get("name", info.get("given_name", ""))

    # Verify audience
    if info.get("aud") != GOOGLE_CLIENT_ID:
        audit.warning("MOBILE_OAUTH_AUDIENCE_MISMATCH aud=%s", info.get("aud"))
        return RedirectResponse(url=f"{error_url}audience_mismatch", status_code=302)

    # Check allowlist
    user = db.query(AllowedUser).filter(AllowedUser.email == email).first()
    if not user:
        audit.warning("MOBILE_OAUTH_DENIED email=%s reason=not_in_allowlist", email)
        return RedirectResponse(url=f"{error_url}not_authorized", status_code=302)

    # Issue JWT and redirect to app
    audit.info("MOBILE_LOGIN_SUCCESS email=%s role=%s", user.email, user.role)
    jwt_token = create_jwt(user.email, user.name, user.role)
    redirect = RedirectResponse(
        url=f"{MOBILE_APP_SCHEME}://auth?token={jwt_token}",
        status_code=302,
    )
    redirect.delete_cookie("mobile_oauth_state")
    return redirect


# ---------------------------------------------------------------------------
# Native Google Sign-In (iOS SDK → server token exchange)
# ---------------------------------------------------------------------------


@router.post("/mobile/google", response_model=TokenResponse)
def mobile_google_signin(
    body: GoogleIdTokenRequest,
    db: Session = Depends(get_db),
) -> TokenResponse:
    """Exchange a Google ID token from the iOS SDK for a server JWT.

    The iOS app uses the native Google Sign-In SDK to authenticate,
    then sends the resulting ID token here for verification and JWT
    issuance.
    """
    # Accept tokens issued to either the iOS or web client ID
    valid_client_ids = {GOOGLE_CLIENT_ID, GOOGLE_IOS_CLIENT_ID}

    try:
        idinfo = google_id_token.verify_oauth2_token(
            body.id_token,
            google_requests.Request(),
        )
    except ValueError:
        audit.warning("MOBILE_GOOGLE_ID_TOKEN_INVALID")
        raise HTTPException(401, detail="Invalid Google ID token")

    if idinfo.get("aud") not in valid_client_ids:
        audit.warning(
            "MOBILE_GOOGLE_AUDIENCE_MISMATCH aud=%s", idinfo.get("aud"),
        )
        raise HTTPException(401, detail="Token audience mismatch")

    email = idinfo.get("email", "")
    name = idinfo.get("name", idinfo.get("given_name", ""))

    user = db.query(AllowedUser).filter(AllowedUser.email == email).first()
    if not user:
        audit.warning(
            "MOBILE_GOOGLE_DENIED email=%s reason=not_in_allowlist", email,
        )
        raise HTTPException(
            403, detail="Not authorized -- ask Nick for an invite",
        )

    audit.info("MOBILE_GOOGLE_LOGIN_SUCCESS email=%s role=%s", user.email, user.role)
    jwt_token = create_jwt(user.email, user.name, user.role)
    return TokenResponse(
        token=jwt_token,
        email=user.email,
        name=user.name,
        role=user.role,
    )


# ---------------------------------------------------------------------------
# Token refresh
# ---------------------------------------------------------------------------


@router.post("/refresh", response_model=TokenResponse)
def refresh_token(
    request: Request,
    db: Session = Depends(get_db),
) -> TokenResponse:
    """Exchange a valid (or recently expired) JWT for a fresh one.

    Accepts the token via Authorization: Bearer header or session_token cookie.
    Allows tokens expired by up to 24 hours to be refreshed (grace period).
    """
    # Extract token from Bearer header or cookie
    auth_header = request.headers.get("Authorization", "")
    token: str | None = None
    if auth_header.startswith("Bearer "):
        token = auth_header[7:]
    if not token:
        token = request.cookies.get("session_token")
    if not token:
        raise HTTPException(401, detail="No token provided")

    # Decode with leeway for recently expired tokens (24h grace)
    import jwt as pyjwt

    from auth import JWT_ALGORITHM, JWT_SECRET

    try:
        payload = pyjwt.decode(
            token,
            JWT_SECRET,
            algorithms=[JWT_ALGORITHM],
            options={"verify_exp": True},
            leeway=timedelta(hours=24),
        )
    except pyjwt.ExpiredSignatureError:
        audit.warning("REFRESH_DENIED reason=token_too_old")
        raise HTTPException(401, detail="Token too old to refresh")
    except pyjwt.InvalidTokenError:
        audit.warning("REFRESH_DENIED reason=invalid_token")
        raise HTTPException(401, detail="Invalid token")

    email = payload.get("sub", "")
    user = db.query(AllowedUser).filter(AllowedUser.email == email).first()
    if not user:
        audit.warning("REFRESH_DENIED email=%s reason=not_in_allowlist", email)
        raise HTTPException(401, detail="User not found in allowlist")

    new_token = create_jwt(user.email, user.name, user.role)
    audit.info("TOKEN_REFRESHED email=%s", user.email)
    return TokenResponse(
        token=new_token,
        email=user.email,
        name=user.name,
        role=user.role,
    )
