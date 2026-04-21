"""Smoke test: authenticate to CloudKit Web Services and list zones.

Usage:
    python scripts/test_cloudkit_api.py
"""
from __future__ import annotations

import base64
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import ecdsa
import requests

CONTAINER = "iCloud.com.seanick80.recipeapp"
ENVIRONMENT = "development"
KEY_ID = "e5b711ffebc17e0e0d58ce8ae056b1c798adecaa02c0ea2293ba1181f8e98250"
KEY_FILE = Path(__file__).resolve().parent.parent / "secrets" / "cloudkit_server_key.pem"
BASE_URL = f"https://api.apple-cloudkit.com/database/1/{CONTAINER}/{ENVIRONMENT}"


def sign_request(subpath: str, body: str, debug: bool = False) -> dict[str, str]:
    """Build CloudKit S2S auth headers."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    body_hash = base64.b64encode(hashlib.sha256(body.encode()).digest()).decode()
    message = f"{now}:{body_hash}:{subpath}"

    if debug:
        print(f"  Date: {now}")
        print(f"  Body hash: {body_hash}")
        print(f"  Subpath: {subpath}")
        print(f"  Message to sign: {message}")

    key_pem = KEY_FILE.read_text()
    sk = ecdsa.SigningKey.from_pem(key_pem)
    # Apple docs: ECDSA signature of the message, not its hash
    # The ecdsa library's sign() with hashfunc hashes internally
    sig_der = sk.sign(
        message.encode(),
        hashfunc=hashlib.sha256,
        sigencode=ecdsa.util.sigencode_der,
    )
    signature = base64.b64encode(sig_der).decode()

    if debug:
        print(f"  Signature: {signature[:40]}...")

    return {
        "X-Apple-CloudKit-Request-KeyID": KEY_ID,
        "X-Apple-CloudKit-Request-ISO8601Date": now,
        "X-Apple-CloudKit-Request-SignatureV1": signature,
    }


def list_zones(database: str = "public", debug: bool = False) -> dict:
    """List all record zones."""
    subpath = f"/database/1/{CONTAINER}/{ENVIRONMENT}/{database}/zones/list"
    url = f"https://api.apple-cloudkit.com{subpath}"
    body = "{}"
    headers = sign_request(subpath, body, debug=debug)
    headers["Content-Type"] = "text/plain"
    resp = requests.post(url, headers=headers, data=body, timeout=30)
    return resp.status_code, resp.json()


def query_records(record_type: str, limit: int = 5, debug: bool = False) -> tuple[int, dict]:
    """Query records of a given type from the private database."""
    subpath = f"/database/1/{CONTAINER}/{ENVIRONMENT}/private/records/query"
    url = f"https://api.apple-cloudkit.com{subpath}"
    body = json.dumps({
        "query": {
            "recordType": record_type,
        },
        "resultsLimit": limit,
    })
    headers = sign_request(subpath, body, debug=debug)
    headers["Content-Type"] = "text/plain"
    resp = requests.post(url, headers=headers, data=body, timeout=30)
    return resp.status_code, resp.json()


if __name__ == "__main__":
    print(f"Container: {CONTAINER}")
    print(f"Environment: {ENVIRONMENT}")
    print(f"Key ID: {KEY_ID[:16]}...")
    print(f"Key file: {KEY_FILE}")
    print()

    # Test 1: List private zones
    print("=== List Private Zones ===")
    status, data = list_zones("private")
    print(f"Status: {status}")
    print(json.dumps(data, indent=2)[:500])
    print()

    print("=== List Public Zones (debug) ===")
    pub_status, pub_data = list_zones("public", debug=True)
    print(f"Status: {pub_status}")
    print(json.dumps(pub_data, indent=2)[:500])
    print()

    # Test 2: Try public zones
    if status != 200:
        print("Private zone listing failed, trying public...")
        print()
        print("=== List Public Zones ===")
        status, data = list_zones("public")
        print(f"Status: {status}")
        print(json.dumps(data, indent=2)[:500])
        print()

    # Test 3: Query CD_Recipe records from private DB
    print("=== Query CD_Recipe from private (limit 2) ===")
    status, data = query_records("CD_Recipe", limit=2)
    print(f"Status: {status}")
    print(json.dumps(data, indent=2)[:2000])
