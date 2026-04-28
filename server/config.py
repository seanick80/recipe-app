from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/recipe_app",
)

GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "")
JWT_SECRET = os.getenv("JWT_SECRET", "change-me-in-production")
OAUTH_REDIRECT_URI = os.getenv(
    "OAUTH_REDIRECT_URI",
    "http://localhost:8000/api/v1/auth/callback",
)
FRONTEND_URL = os.getenv("FRONTEND_URL", "http://localhost:5173")
MOBILE_REDIRECT_URI = os.getenv(
    "MOBILE_REDIRECT_URI",
    "http://localhost:8000/api/v1/auth/mobile/callback",
)
MOBILE_APP_SCHEME = os.getenv("MOBILE_APP_SCHEME", "recipeapp")
GOOGLE_IOS_CLIENT_ID = os.getenv(
    "GOOGLE_IOS_CLIENT_ID",
    "972511622379-mak8qoj1corsaria7f2k8ainq715al7u.apps.googleusercontent.com",
)
