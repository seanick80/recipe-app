from __future__ import annotations

import os
import secrets

from fastapi import HTTPException, Security
from fastapi.security import APIKeyHeader

_header = APIKeyHeader(name="X-API-Key", auto_error=False)

API_KEY = os.getenv("API_KEY", "")


def get_api_key(key: str | None = Security(_header)) -> str:
    if not API_KEY:
        raise HTTPException(503, detail="Server not configured")
    if not key or not secrets.compare_digest(key, API_KEY):
        raise HTTPException(401, detail="Invalid or missing API key")
    return key
