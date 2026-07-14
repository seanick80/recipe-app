from __future__ import annotations

import time
import uuid


def test_create_grocery_list(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/lists",
        json={"name": "Weekly"},
        headers=auth_headers,
    )
    assert resp.status_code == 201
    result = resp.json()
    assert result["name"] == "Weekly"
    assert result["archived_at"] is None


def test_get_grocery_list(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/lists",
        json={"name": "My List"},
        headers=auth_headers,
    )
    list_id = resp.json()["id"]

    response = client.get(f"/api/v1/grocery/lists/{list_id}")
    assert response.status_code == 200
    assert response.json()["name"] == "My List"


def test_grocery_list_not_found(client):
    fake_id = str(uuid.uuid4())
    response = client.get(f"/api/v1/grocery/lists/{fake_id}")
    assert response.status_code == 404


def test_add_item_with_source(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/lists",
        json={"name": "Source Test"},
        headers=auth_headers,
    )
    list_id = resp.json()["id"]

    item_data = {
        "name": "Chicken",
        "quantity": 2,
        "unit": "lbs",
        "category": "Meat",
        "source_recipe_name": "Chicken Soup",
        "source_recipe_id": "abc-123",
    }
    response = client.post(
        f"/api/v1/grocery/lists/{list_id}/items",
        json=item_data,
        headers=auth_headers,
    )
    assert response.status_code == 201
    result = response.json()
    assert result["source_recipe_name"] == "Chicken Soup"
    assert result["source_recipe_id"] == "abc-123"


def test_toggle_item(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/lists",
        json={"name": "Toggle List"},
        headers=auth_headers,
    )
    list_id = resp.json()["id"]

    item_resp = client.post(
        f"/api/v1/grocery/lists/{list_id}/items",
        json={"name": "Milk"},
        headers=auth_headers,
    )
    item_id = item_resp.json()["id"]
    assert item_resp.json()["is_checked"] is False

    toggle_resp = client.patch(
        f"/api/v1/grocery/items/{item_id}/toggle",
        headers=auth_headers,
    )
    assert toggle_resp.status_code == 200
    assert toggle_resp.json()["is_checked"] is True


def test_delete_item(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/lists",
        json={"name": "Delete Item List"},
        headers=auth_headers,
    )
    list_id = resp.json()["id"]

    item_resp = client.post(
        f"/api/v1/grocery/lists/{list_id}/items",
        json={"name": "Bread"},
        headers=auth_headers,
    )
    item_id = item_resp.json()["id"]

    del_resp = client.delete(
        f"/api/v1/grocery/items/{item_id}",
        headers=auth_headers,
    )
    assert del_resp.status_code == 204


def test_archive_restore_list(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/lists",
        json={"name": "Archive Test"},
        headers=auth_headers,
    )
    list_id = resp.json()["id"]
    assert resp.json()["archived_at"] is None

    archive_resp = client.patch(
        f"/api/v1/grocery/lists/{list_id}/archive",
        headers=auth_headers,
    )
    assert archive_resp.status_code == 200
    assert archive_resp.json()["archived_at"] is not None

    restore_resp = client.patch(
        f"/api/v1/grocery/lists/{list_id}/restore",
        headers=auth_headers,
    )
    assert restore_resp.status_code == 200
    assert restore_resp.json()["archived_at"] is None


def test_create_template(client, auth_headers):
    data = {
        "name": "Breakfast Basics",
        "sort_order": 1,
        "items": [
            {
                "name": "Eggs",
                "quantity": 12,
                "unit": "count",
                "category": "Dairy",
                "sort_order": 0,
            },
            {
                "name": "Bacon",
                "quantity": 1,
                "unit": "lb",
                "category": "Meat",
                "sort_order": 1,
            },
        ],
    }
    response = client.post(
        "/api/v1/grocery/templates",
        json=data,
        headers=auth_headers,
    )
    assert response.status_code == 201
    result = response.json()
    assert result["name"] == "Breakfast Basics"
    assert result["sort_order"] == 1
    assert len(result["items"]) == 2
    assert result["items"][0]["name"] == "Eggs"


def test_list_templates(client, auth_headers):
    client.post("/api/v1/grocery/templates", json={
        "name": "Template A",
        "sort_order": 0,
    }, headers=auth_headers)
    client.post("/api/v1/grocery/templates", json={
        "name": "Template B",
        "sort_order": 1,
    }, headers=auth_headers)

    response = client.get("/api/v1/grocery/templates")
    assert response.status_code == 200
    assert len(response.json()) == 2


def test_get_template(client, auth_headers):
    resp = client.post("/api/v1/grocery/templates", json={
        "name": "Get Me",
        "sort_order": 0,
        "items": [
            {"name": "Milk", "quantity": 1, "unit": "gallon"},
        ],
    }, headers=auth_headers)
    template_id = resp.json()["id"]

    response = client.get(
        f"/api/v1/grocery/templates/{template_id}",
    )
    assert response.status_code == 200
    assert response.json()["name"] == "Get Me"
    assert len(response.json()["items"]) == 1


def test_update_template(client, auth_headers):
    resp = client.post("/api/v1/grocery/templates", json={
        "name": "Original",
        "sort_order": 0,
        "items": [
            {"name": "Item A", "quantity": 1, "unit": "each"},
        ],
    }, headers=auth_headers)
    template_id = resp.json()["id"]

    update_data = {
        "name": "Updated",
        "sort_order": 5,
        "items": [
            {"name": "Item B", "quantity": 2, "unit": "lbs"},
            {"name": "Item C", "quantity": 3, "unit": "oz"},
        ],
    }
    response = client.put(
        f"/api/v1/grocery/templates/{template_id}",
        json=update_data,
        headers=auth_headers,
    )
    assert response.status_code == 200
    result = response.json()
    assert result["name"] == "Updated"
    assert result["sort_order"] == 5
    assert len(result["items"]) == 2


def test_delete_template(client, auth_headers):
    resp = client.post("/api/v1/grocery/templates", json={
        "name": "To Delete",
        "sort_order": 0,
    }, headers=auth_headers)
    template_id = resp.json()["id"]

    del_resp = client.delete(
        f"/api/v1/grocery/templates/{template_id}",
        headers=auth_headers,
    )
    assert del_resp.status_code == 204

    get_resp = client.get(
        f"/api/v1/grocery/templates/{template_id}",
    )
    assert get_resp.status_code == 404


# --- Sync: updated_at watermark ---


def test_list_created_with_updated_at(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/lists",
        json={"name": "Watermark"},
        headers=auth_headers,
    )
    assert resp.status_code == 201
    assert resp.json()["updated_at"] is not None


def test_template_created_with_updated_at(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/templates",
        json={"name": "T", "sort_order": 0},
        headers=auth_headers,
    )
    assert resp.status_code == 201
    assert resp.json()["updated_at"] is not None


def test_item_add_bumps_parent_list_updated_at(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/lists",
        json={"name": "Bump"},
        headers=auth_headers,
    )
    list_id = resp.json()["id"]
    original = resp.json()["updated_at"]

    time.sleep(0.01)
    add = client.post(
        f"/api/v1/grocery/lists/{list_id}/items",
        json={"name": "Milk"},
        headers=auth_headers,
    )
    assert add.status_code == 201

    after = client.get(f"/api/v1/grocery/lists/{list_id}").json()["updated_at"]
    assert after > original


def test_item_toggle_bumps_parent_list_updated_at(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/lists",
        json={"name": "ToggleBump"},
        headers=auth_headers,
    )
    list_id = resp.json()["id"]
    item_id = client.post(
        f"/api/v1/grocery/lists/{list_id}/items",
        json={"name": "Eggs"},
        headers=auth_headers,
    ).json()["id"]
    before = client.get(f"/api/v1/grocery/lists/{list_id}").json()["updated_at"]

    time.sleep(0.01)
    client.patch(
        f"/api/v1/grocery/items/{item_id}/toggle",
        headers=auth_headers,
    )
    after = client.get(f"/api/v1/grocery/lists/{list_id}").json()["updated_at"]
    assert after > before


def test_item_patch_bumps_parent_list_updated_at(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/lists",
        json={"name": "PatchBump"},
        headers=auth_headers,
    )
    list_id = resp.json()["id"]
    item_id = client.post(
        f"/api/v1/grocery/lists/{list_id}/items",
        json={"name": "Flour"},
        headers=auth_headers,
    ).json()["id"]
    before = client.get(f"/api/v1/grocery/lists/{list_id}").json()["updated_at"]

    time.sleep(0.01)
    client.patch(
        f"/api/v1/grocery/items/{item_id}",
        json={"quantity": 5},
        headers=auth_headers,
    )
    after = client.get(f"/api/v1/grocery/lists/{list_id}").json()["updated_at"]
    assert after > before


def test_item_delete_bumps_parent_list_updated_at(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/lists",
        json={"name": "DeleteBump"},
        headers=auth_headers,
    )
    list_id = resp.json()["id"]
    item_id = client.post(
        f"/api/v1/grocery/lists/{list_id}/items",
        json={"name": "Sugar"},
        headers=auth_headers,
    ).json()["id"]
    before = client.get(f"/api/v1/grocery/lists/{list_id}").json()["updated_at"]

    time.sleep(0.01)
    client.delete(
        f"/api/v1/grocery/items/{item_id}",
        headers=auth_headers,
    )
    after = client.get(f"/api/v1/grocery/lists/{list_id}").json()["updated_at"]
    assert after > before


def test_template_update_bumps_updated_at(client, auth_headers):
    resp = client.post(
        "/api/v1/grocery/templates",
        json={"name": "Orig", "sort_order": 0},
        headers=auth_headers,
    )
    template_id = resp.json()["id"]
    before = resp.json()["updated_at"]

    time.sleep(0.01)
    upd = client.put(
        f"/api/v1/grocery/templates/{template_id}",
        json={"name": "Orig", "sort_order": 0, "items": []},
        headers=auth_headers,
    )
    assert upd.status_code == 200
    assert upd.json()["updated_at"] > before


def test_lists_fields_sync_listing(client, auth_headers):
    client.post(
        "/api/v1/grocery/lists",
        json={"name": "L1"},
        headers=auth_headers,
    )
    client.post(
        "/api/v1/grocery/lists",
        json={"name": "L2"},
        headers=auth_headers,
    )
    resp = client.get("/api/v1/grocery/lists?fields=id,updated_at")
    assert resp.status_code == 200
    rows = resp.json()
    assert len(rows) == 2
    for row in rows:
        assert set(row.keys()) == {"id", "updated_at"}


def test_templates_fields_sync_listing(client, auth_headers):
    client.post(
        "/api/v1/grocery/templates",
        json={"name": "T1", "sort_order": 0},
        headers=auth_headers,
    )
    resp = client.get("/api/v1/grocery/templates?fields=id,updated_at")
    assert resp.status_code == 200
    rows = resp.json()
    assert len(rows) == 1
    assert set(rows[0].keys()) == {"id", "updated_at"}


def test_lists_full_listing_unaffected_by_fields_absent(client, auth_headers):
    client.post(
        "/api/v1/grocery/lists",
        json={"name": "Full"},
        headers=auth_headers,
    )
    resp = client.get("/api/v1/grocery/lists")
    assert resp.status_code == 200
    row = resp.json()[0]
    assert row["name"] == "Full"
    assert "items" in row
    assert "updated_at" in row
