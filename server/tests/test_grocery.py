from __future__ import annotations

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
