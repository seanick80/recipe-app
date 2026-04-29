from __future__ import annotations

import os

# Set env vars before importing app modules
TEST_API_KEY = "test-api-key-for-unit-tests"
os.environ["API_KEY"] = TEST_API_KEY
os.environ["GOOGLE_CLIENT_ID"] = "test-client-id"
os.environ["GOOGLE_CLIENT_SECRET"] = "test-client-secret"
os.environ["JWT_SECRET"] = "test-secret-that-is-long-enough-for-hmac-sha256"
os.environ["RATE_LIMIT_ENABLED"] = "0"

import jwt
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base, get_db
from main import app
from models.user import AllowedUser

SQLALCHEMY_DATABASE_URL = "sqlite://"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base.metadata.create_all(bind=engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db


def _seed_test_users(session) -> None:
    """Seed the admin + second user for isolation tests."""
    admin = AllowedUser(
        email="admin@test.com",
        name="Test Admin",
        role="admin",
        invited_by="system",
    )
    user_b = AllowedUser(
        email="userb@test.com",
        name="User B",
        role="editor",
        invited_by="system",
    )
    session.add_all([admin, user_b])
    session.commit()


def make_jwt(
    email: str = "admin@test.com",
    name: str = "Test Admin",
    role: str = "admin",
) -> str:
    """Create a valid test JWT cookie value."""
    from auth import create_jwt

    return create_jwt(email, name, role)


@pytest.fixture
def client():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    _seed_test_users(db)
    db.close()
    with TestClient(app) as c:
        yield c


@pytest.fixture
def auth_headers() -> dict[str, str]:
    return {"X-API-Key": TEST_API_KEY}


@pytest.fixture
def auth_cookie() -> dict[str, str]:
    """Return a cookie dict with a valid JWT for the test admin user."""
    return {"session_token": make_jwt()}


@pytest.fixture
def editor_cookie() -> dict[str, str]:
    """Return a cookie dict with a valid JWT for an editor user."""
    return {"session_token": make_jwt("editor@test.com", "Editor", "editor")}


@pytest.fixture
def user_b_headers() -> dict[str, str]:
    """Auth headers for a second user — should NOT see admin's recipes."""
    return {"Authorization": f"Bearer {make_jwt('userb@test.com', 'User B', 'editor')}"}
