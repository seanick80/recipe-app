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
