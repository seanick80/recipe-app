from __future__ import annotations

from tests.conftest import make_jwt


def test_login_redirects_to_google(client):
    response = client.get("/api/v1/auth/login", follow_redirects=False)
    assert response.status_code == 307
    assert "accounts.google.com" in response.headers["location"]


def test_me_without_auth_returns_401(client):
    response = client.get("/api/v1/auth/me")
    assert response.status_code == 401


def test_me_with_valid_jwt_returns_user(client, auth_cookie):
    response = client.get("/api/v1/auth/me", cookies=auth_cookie)
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "admin@test.com"
    assert data["name"] == "Test Admin"
    assert data["role"] == "admin"


def test_logout_clears_cookie(client, auth_cookie):
    response = client.post("/api/v1/auth/logout", cookies=auth_cookie)
    assert response.status_code == 200
    assert "session_token" in response.headers.get("set-cookie", "")


def test_invite_requires_admin(client, editor_cookie):
    # First seed the editor user so JWT lookup succeeds
    from sqlalchemy.orm import Session

    from database import get_db
    from models.user import AllowedUser

    db = next(client.app.dependency_overrides[get_db]())
    editor = AllowedUser(
        email="editor@test.com",
        name="Editor",
        role="editor",
    )
    db.add(editor)
    db.commit()
    db.close()

    response = client.post(
        "/api/v1/auth/invite",
        json={"email": "new@test.com", "name": "New User"},
        cookies=editor_cookie,
    )
    assert response.status_code == 403


def test_invite_as_admin_creates_user(client, auth_cookie):
    response = client.post(
        "/api/v1/auth/invite",
        json={"email": "invited@test.com", "name": "Invited", "role": "viewer"},
        cookies=auth_cookie,
    )
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "invited@test.com"
    assert data["name"] == "Invited"
    assert data["role"] == "viewer"


def test_list_users_requires_admin(client, editor_cookie):
    # Seed editor user
    from database import get_db
    from models.user import AllowedUser

    db = next(client.app.dependency_overrides[get_db]())
    editor = AllowedUser(
        email="editor@test.com",
        name="Editor",
        role="editor",
    )
    db.add(editor)
    db.commit()
    db.close()

    response = client.get("/api/v1/auth/users", cookies=editor_cookie)
    assert response.status_code == 403


def test_list_users_as_admin(client, auth_cookie):
    response = client.get("/api/v1/auth/users", cookies=auth_cookie)
    assert response.status_code == 200
    users = response.json()
    assert len(users) >= 1
    assert any(u["email"] == "admin@test.com" for u in users)


# ---------------------------------------------------------------------------
# Bearer token auth (mobile clients)
# ---------------------------------------------------------------------------


def test_me_with_bearer_token(client):
    """Authorization: Bearer header should authenticate like a cookie."""
    token = make_jwt()
    response = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "admin@test.com"
    assert data["role"] == "admin"


def test_me_with_invalid_bearer_returns_401(client):
    response = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": "Bearer garbage-token"},
    )
    assert response.status_code == 401


def test_bearer_takes_priority_over_cookie(client, auth_cookie):
    """If both Bearer and cookie are present, Bearer wins."""
    from database import get_db
    from models.user import AllowedUser

    # Seed a second user
    db = next(client.app.dependency_overrides[get_db]())
    db.add(AllowedUser(email="other@test.com", name="Other", role="viewer"))
    db.commit()
    db.close()

    bearer_token = make_jwt("other@test.com", "Other", "viewer")
    response = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {bearer_token}"},
        cookies=auth_cookie,
    )
    assert response.status_code == 200
    assert response.json()["email"] == "other@test.com"


# ---------------------------------------------------------------------------
# Mobile OAuth flow
# ---------------------------------------------------------------------------


def test_mobile_login_redirects_to_google(client):
    response = client.get("/api/v1/auth/mobile/login", follow_redirects=False)
    assert response.status_code == 307
    assert "accounts.google.com" in response.headers["location"]
    assert "mobile_oauth_state" in response.headers.get("set-cookie", "")


# ---------------------------------------------------------------------------
# Token refresh
# ---------------------------------------------------------------------------


def test_refresh_with_valid_bearer(client):
    token = make_jwt()
    response = client.post(
        "/api/v1/auth/refresh",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "admin@test.com"
    assert data["role"] == "admin"
    assert "token" in data
    assert len(data["token"]) > 50  # valid JWT issued


def test_refresh_with_cookie(client, auth_cookie):
    response = client.post("/api/v1/auth/refresh", cookies=auth_cookie)
    assert response.status_code == 200
    assert response.json()["email"] == "admin@test.com"


def test_refresh_without_token_returns_401(client):
    response = client.post("/api/v1/auth/refresh")
    assert response.status_code == 401


def test_refresh_with_invalid_token_returns_401(client):
    response = client.post(
        "/api/v1/auth/refresh",
        headers={"Authorization": "Bearer totally-invalid"},
    )
    assert response.status_code == 401


# ---------------------------------------------------------------------------
# Native Google Sign-In (POST /mobile/google)
# ---------------------------------------------------------------------------


def test_mobile_google_valid_token(client, monkeypatch):
    """Valid Google ID token for an allowed user returns a JWT."""

    def fake_verify(token, request, **kwargs):
        return {
            "aud": "test-client-id",
            "email": "admin@test.com",
            "name": "Test Admin",
        }

    monkeypatch.setattr(
        "routers.auth_routes.google_id_token.verify_oauth2_token",
        fake_verify,
    )
    response = client.post(
        "/api/v1/auth/mobile/google",
        json={"id_token": "valid-google-token"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "admin@test.com"
    assert data["role"] == "admin"
    assert len(data["token"]) > 50


def test_mobile_google_invalid_token(client, monkeypatch):
    """Invalid Google ID token returns 401."""

    def fake_verify(token, request, **kwargs):
        raise ValueError("Invalid token")

    monkeypatch.setattr(
        "routers.auth_routes.google_id_token.verify_oauth2_token",
        fake_verify,
    )
    response = client.post(
        "/api/v1/auth/mobile/google",
        json={"id_token": "garbage"},
    )
    assert response.status_code == 401


def test_mobile_google_wrong_audience(client, monkeypatch):
    """Token with wrong audience returns 401."""

    def fake_verify(token, request, **kwargs):
        return {
            "aud": "some-other-client-id",
            "email": "admin@test.com",
            "name": "Test Admin",
        }

    monkeypatch.setattr(
        "routers.auth_routes.google_id_token.verify_oauth2_token",
        fake_verify,
    )
    response = client.post(
        "/api/v1/auth/mobile/google",
        json={"id_token": "wrong-aud-token"},
    )
    assert response.status_code == 401


def test_mobile_google_user_not_allowed(client, monkeypatch):
    """Valid token for a non-allowed user returns 403."""

    def fake_verify(token, request, **kwargs):
        return {
            "aud": "test-client-id",
            "email": "stranger@example.com",
            "name": "Stranger",
        }

    monkeypatch.setattr(
        "routers.auth_routes.google_id_token.verify_oauth2_token",
        fake_verify,
    )
    response = client.post(
        "/api/v1/auth/mobile/google",
        json={"id_token": "valid-but-not-allowed"},
    )
    assert response.status_code == 403
