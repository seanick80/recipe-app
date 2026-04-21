from __future__ import annotations


ENDPOINT = "/api/v1/telemetry/import-normalizations"


def _entry(
    original: str = "1/2 cup (,120ml) water",
    cleaned: str = "1/2 cup (120ml) water",
    normalization_type: str = "leading_comma_in_parens",
    source_url: str | None = "https://example.com/recipe",
) -> dict:
    return {
        "source_url": source_url,
        "original_text": original,
        "cleaned_text": cleaned,
        "normalization_type": normalization_type,
    }


def test_log_single_entry(client):
    payload = {"entries": [_entry()]}
    response = client.post(ENDPOINT, json=payload)
    assert response.status_code == 200
    assert response.json() == {"accepted": 1}


def test_log_multiple_entries(client):
    entries = [
        _entry(normalization_type="leading_comma_in_parens"),
        _entry(
            original="((2 cups))",
            cleaned="(2 cups)",
            normalization_type="double_parens",
        ),
        _entry(
            original="1 cup / 240ml milk",
            cleaned="1 cup milk",
            normalization_type="dual_units",
        ),
    ]
    response = client.post(ENDPOINT, json={"entries": entries})
    assert response.status_code == 200
    assert response.json() == {"accepted": 3}


def test_log_entry_without_source_url(client):
    entry = _entry(source_url=None)
    response = client.post(ENDPOINT, json={"entries": [entry]})
    assert response.status_code == 200
    assert response.json() == {"accepted": 1}


def test_empty_entries_rejected(client):
    response = client.post(ENDPOINT, json={"entries": []})
    assert response.status_code == 422


def test_missing_required_fields_rejected(client):
    # original_text is missing
    bad_entry = {
        "cleaned_text": "1/2 cup water",
        "normalization_type": "leading_comma_in_parens",
    }
    response = client.post(ENDPOINT, json={"entries": [bad_entry]})
    assert response.status_code == 422


def test_no_auth_required(client):
    """Telemetry endpoint must be accessible without any credentials."""
    payload = {"entries": [_entry()]}
    # No auth_headers or auth_cookie — should still succeed
    response = client.post(ENDPOINT, json=payload)
    assert response.status_code == 200
