from __future__ import annotations

import uuid


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_create_recipe(client, auth_headers):
    data = {
        "name": "Spaghetti Bolognese",
        "summary": "Classic Italian pasta",
        "instructions": "Boil pasta. Make sauce. Combine.",
        "prep_time_minutes": 15,
        "cook_time_minutes": 30,
        "servings": 4,
        "ingredients": [
            {"name": "Spaghetti", "quantity": 1, "unit": "lb"},
            {"name": "Ground Beef", "quantity": 1, "unit": "lb"},
        ],
    }
    response = client.post(
        "/api/v1/recipes/",
        json=data,
        headers=auth_headers,
    )
    assert response.status_code == 201
    result = response.json()
    assert result["name"] == "Spaghetti Bolognese"
    assert len(result["ingredients"]) == 2


def test_list_recipes(client, auth_headers):
    client.post(
        "/api/v1/recipes/",
        json={"name": "Recipe 1"},
        headers=auth_headers,
    )
    client.post(
        "/api/v1/recipes/",
        json={"name": "Recipe 2"},
        headers=auth_headers,
    )
    response = client.get("/api/v1/recipes/", headers=auth_headers)
    assert response.status_code == 200
    assert len(response.json()) == 2


def test_delete_recipe(client, auth_headers):
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "To Delete"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]
    response = client.delete(
        f"/api/v1/recipes/{recipe_id}",
        headers=auth_headers,
    )
    assert response.status_code == 204


def test_get_recipe(client, auth_headers):
    resp = client.post("/api/v1/recipes/", json={
        "name": "Test Get",
        "summary": "A summary",
        "cuisine": "Italian",
        "course": "Main",
        "ingredients": [
            {"name": "Salt", "quantity": 1, "unit": "tsp"},
        ],
    }, headers=auth_headers)
    assert resp.status_code == 201
    recipe_id = resp.json()["id"]

    response = client.get(f"/api/v1/recipes/{recipe_id}", headers=auth_headers)
    assert response.status_code == 200
    result = response.json()
    assert result["name"] == "Test Get"
    assert result["summary"] == "A summary"
    assert result["cuisine"] == "Italian"
    assert result["course"] == "Main"
    assert result["is_favorite"] is False
    assert result["is_published"] is False
    assert len(result["ingredients"]) == 1


def test_update_recipe(client, auth_headers):
    resp = client.post("/api/v1/recipes/", json={
        "name": "Original",
        "servings": 2,
    }, headers=auth_headers)
    recipe_id = resp.json()["id"]

    update_data = {
        "name": "Updated",
        "servings": 6,
        "cuisine": "Mexican",
        "ingredients": [
            {"name": "Tortilla", "quantity": 4, "unit": "pieces"},
        ],
    }
    response = client.put(
        f"/api/v1/recipes/{recipe_id}",
        json=update_data,
        headers=auth_headers,
    )
    assert response.status_code == 200
    result = response.json()
    assert result["name"] == "Updated"
    assert result["servings"] == 6
    assert result["cuisine"] == "Mexican"
    assert len(result["ingredients"]) == 1
    assert result["ingredients"][0]["name"] == "Tortilla"


def test_recipe_not_found(client, auth_headers):
    fake_id = str(uuid.uuid4())
    response = client.get(f"/api/v1/recipes/{fake_id}", headers=auth_headers)
    assert response.status_code == 404


def test_create_recipe_with_all_fields(client, auth_headers):
    data = {
        "name": "Full Recipe",
        "summary": "Full summary",
        "instructions": "Do all things",
        "prep_time_minutes": 10,
        "cook_time_minutes": 20,
        "servings": 2,
        "cuisine": "Thai",
        "course": "Appetizer",
        "tags": "spicy,quick",
        "source_url": "https://example.com/recipe",
        "difficulty": "Easy",
        "is_favorite": True,
        "is_published": True,
        "ingredients": [],
    }
    response = client.post(
        "/api/v1/recipes/",
        json=data,
        headers=auth_headers,
    )
    assert response.status_code == 201
    result = response.json()
    assert result["cuisine"] == "Thai"
    assert result["course"] == "Appetizer"
    assert result["tags"] == "spicy,quick"
    assert result["source_url"] == "https://example.com/recipe"
    assert result["difficulty"] == "Easy"
    assert result["is_favorite"] is True
    assert result["is_published"] is True


def test_ingredient_fields(client, auth_headers):
    data = {
        "name": "Ingredient Test",
        "ingredients": [
            {
                "name": "Flour",
                "quantity": 2.5,
                "unit": "cups",
                "category": "Baking",
                "display_order": 1,
                "notes": "sifted",
            },
            {
                "name": "Sugar",
                "quantity": 1,
                "unit": "cup",
                "category": "Baking",
                "display_order": 2,
                "notes": "",
            },
        ],
    }
    response = client.post(
        "/api/v1/recipes/",
        json=data,
        headers=auth_headers,
    )
    assert response.status_code == 201
    ingredients = response.json()["ingredients"]
    assert ingredients[0]["category"] == "Baking"
    assert ingredients[0]["display_order"] == 1
    assert ingredients[0]["notes"] == "sifted"
    assert ingredients[0]["quantity"] == 2.5
    assert ingredients[1]["display_order"] == 2


def test_toggle_favorite(client, auth_headers):
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Fav Test"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]
    assert resp.json()["is_favorite"] is False

    response = client.patch(
        f"/api/v1/recipes/{recipe_id}",
        json={"is_favorite": True},
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["is_favorite"] is True


def test_toggle_published(client, auth_headers):
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Pub Test"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]
    assert resp.json()["is_published"] is False

    response = client.patch(
        f"/api/v1/recipes/{recipe_id}",
        json={"is_published": True},
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["is_published"] is True


def test_create_recipe_without_api_key_returns_401(client):
    response = client.post("/api/v1/recipes/", json={"name": "No Auth"})
    assert response.status_code == 401


def test_list_recipes_without_auth_returns_401(client):
    response = client.get("/api/v1/recipes/")
    assert response.status_code == 401


def test_create_recipe_with_jwt_cookie_succeeds(client, auth_cookie):
    response = client.post(
        "/api/v1/recipes/",
        json={"name": "Cookie Recipe"},
        cookies=auth_cookie,
    )
    assert response.status_code == 201
    assert response.json()["name"] == "Cookie Recipe"


def test_create_recipe_without_auth_returns_401(client):
    response = client.post("/api/v1/recipes/", json={"name": "No Auth"})
    assert response.status_code == 401


def test_soft_delete_hides_from_list(client, auth_headers):
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Will Be Deleted"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]

    client.delete(f"/api/v1/recipes/{recipe_id}", headers=auth_headers)

    response = client.get("/api/v1/recipes/", headers=auth_headers)
    assert all(r["id"] != recipe_id for r in response.json())


def test_soft_delete_returns_404_on_get(client, auth_headers):
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Ghost"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]

    client.delete(f"/api/v1/recipes/{recipe_id}", headers=auth_headers)

    response = client.get(f"/api/v1/recipes/{recipe_id}", headers=auth_headers)
    assert response.status_code == 404


def test_deleted_recipes_list(client, auth_headers):
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Deleted One"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]
    client.delete(f"/api/v1/recipes/{recipe_id}", headers=auth_headers)

    response = client.get(
        "/api/v1/recipes/deleted",
        headers=auth_headers,
    )
    assert response.status_code == 200
    ids = [r["id"] for r in response.json()]
    assert recipe_id in ids


def test_restore_deleted_recipe(client, auth_headers):
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Restore Me"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]
    client.delete(f"/api/v1/recipes/{recipe_id}", headers=auth_headers)

    response = client.post(
        f"/api/v1/recipes/deleted/{recipe_id}/restore",
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["name"] == "Restore Me"
    assert response.json()["deleted_at"] is None

    get_resp = client.get(f"/api/v1/recipes/{recipe_id}", headers=auth_headers)
    assert get_resp.status_code == 200


def test_lightweight_list(client, auth_headers):
    client.post(
        "/api/v1/recipes/",
        json={"name": "Light 1"},
        headers=auth_headers,
    )
    client.post(
        "/api/v1/recipes/",
        json={"name": "Light 2"},
        headers=auth_headers,
    )

    response = client.get("/api/v1/recipes/?fields=id,updated_at", headers=auth_headers)
    assert response.status_code == 200
    items = response.json()
    assert len(items) == 2
    for item in items:
        assert "id" in item
        assert "updated_at" in item
        assert "name" not in item
        assert "ingredients" not in item


def test_lightweight_list_excludes_deleted(client, auth_headers):
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Active"},
        headers=auth_headers,
    )
    active_id = resp.json()["id"]

    resp2 = client.post(
        "/api/v1/recipes/",
        json={"name": "Deleted"},
        headers=auth_headers,
    )
    deleted_id = resp2.json()["id"]
    client.delete(f"/api/v1/recipes/{deleted_id}", headers=auth_headers)

    response = client.get("/api/v1/recipes/?fields=id,updated_at", headers=auth_headers)
    ids = [r["id"] for r in response.json()]
    assert active_id in ids
    assert deleted_id not in ids


def test_soft_delete_blocks_update(client, auth_headers):
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Will Block"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]
    client.delete(f"/api/v1/recipes/{recipe_id}", headers=auth_headers)

    response = client.put(
        f"/api/v1/recipes/{recipe_id}",
        json={"name": "Updated"},
        headers=auth_headers,
    )
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# Sync-specific endpoint tests
# ---------------------------------------------------------------------------


def test_lightweight_list_updated_at_changes_after_put(client, auth_headers):
    """After PUT, the lightweight list returns the new updated_at."""
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Sync Test"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]

    list_before = client.get("/api/v1/recipes/?fields=id,updated_at", headers=auth_headers)
    ts_before = next(
        r["updated_at"] for r in list_before.json() if r["id"] == recipe_id
    )

    client.put(
        f"/api/v1/recipes/{recipe_id}",
        json={"name": "Sync Test Updated"},
        headers=auth_headers,
    )

    list_after = client.get("/api/v1/recipes/?fields=id,updated_at", headers=auth_headers)
    ts_after = next(
        r["updated_at"] for r in list_after.json() if r["id"] == recipe_id
    )
    assert ts_after > ts_before


def test_create_then_get_round_trip(client, auth_headers):
    """Create a recipe and GET it back — all fields must match."""
    data = {
        "name": "Round Trip",
        "summary": "Test summary",
        "instructions": "Step 1. Step 2.",
        "prep_time_minutes": 5,
        "cook_time_minutes": 10,
        "servings": 2,
        "cuisine": "French",
        "course": "Dessert",
        "tags": "sweet,quick",
        "source_url": "https://example.com",
        "difficulty": "Medium",
        "is_favorite": True,
        "is_published": False,
        "ingredients": [
            {
                "name": "Butter",
                "quantity": 2.5,
                "unit": "tbsp",
                "category": "Dairy",
                "display_order": 0,
                "notes": "unsalted",
            },
        ],
    }
    create_resp = client.post(
        "/api/v1/recipes/",
        json=data,
        headers=auth_headers,
    )
    assert create_resp.status_code == 201
    recipe_id = create_resp.json()["id"]

    get_resp = client.get(f"/api/v1/recipes/{recipe_id}", headers=auth_headers)
    assert get_resp.status_code == 200
    result = get_resp.json()

    for key, value in data.items():
        if key == "ingredients":
            assert len(result["ingredients"]) == 1
            ing = result["ingredients"][0]
            for ik, iv in data["ingredients"][0].items():
                assert ing[ik] == iv, f"ingredient.{ik}: {ing[ik]} != {iv}"
        else:
            assert result[key] == value, f"{key}: {result[key]} != {value}"

    assert result["id"] is not None
    assert result["created_at"] is not None
    assert result["updated_at"] is not None
    assert result["deleted_at"] is None


def test_put_replaces_ingredients(client, auth_headers):
    """PUT with new ingredients replaces old ones entirely."""
    resp = client.post(
        "/api/v1/recipes/",
        json={
            "name": "Ingredient Swap",
            "ingredients": [
                {"name": "Old A", "quantity": 1, "unit": "cup"},
                {"name": "Old B", "quantity": 2, "unit": "tbsp"},
            ],
        },
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]
    assert len(resp.json()["ingredients"]) == 2

    update_resp = client.put(
        f"/api/v1/recipes/{recipe_id}",
        json={
            "name": "Ingredient Swap",
            "ingredients": [
                {"name": "New X", "quantity": 3, "unit": "oz"},
            ],
        },
        headers=auth_headers,
    )
    assert update_resp.status_code == 200
    ingredients = update_resp.json()["ingredients"]
    assert len(ingredients) == 1
    assert ingredients[0]["name"] == "New X"

    # Verify via GET too — no ghost ingredients
    get_resp = client.get(f"/api/v1/recipes/{recipe_id}", headers=auth_headers)
    assert len(get_resp.json()["ingredients"]) == 1


def test_soft_delete_then_restore_preserves_data(client, auth_headers):
    """Soft-delete + restore round trip preserves all recipe data."""
    data = {
        "name": "Preserve Me",
        "summary": "Important recipe",
        "cuisine": "Japanese",
        "ingredients": [
            {"name": "Rice", "quantity": 2, "unit": "cups"},
        ],
    }
    resp = client.post(
        "/api/v1/recipes/",
        json=data,
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]
    original = resp.json()

    client.delete(f"/api/v1/recipes/{recipe_id}", headers=auth_headers)

    restore_resp = client.post(
        f"/api/v1/recipes/deleted/{recipe_id}/restore",
        headers=auth_headers,
    )
    assert restore_resp.status_code == 200
    restored = restore_resp.json()

    assert restored["name"] == original["name"]
    assert restored["summary"] == original["summary"]
    assert restored["cuisine"] == original["cuisine"]
    assert len(restored["ingredients"]) == len(original["ingredients"])
    assert restored["deleted_at"] is None


def test_soft_delete_blocks_patch(client, auth_headers):
    """PATCH on a soft-deleted recipe returns 404."""
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Patch Block"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]
    client.delete(f"/api/v1/recipes/{recipe_id}", headers=auth_headers)

    response = client.patch(
        f"/api/v1/recipes/{recipe_id}",
        json={"is_favorite": True},
        headers=auth_headers,
    )
    assert response.status_code == 404


def test_double_delete_is_idempotent(client, auth_headers):
    """Deleting an already-deleted recipe succeeds without error."""
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Double Delete"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]
    first = client.delete(
        f"/api/v1/recipes/{recipe_id}", headers=auth_headers,
    )
    assert first.status_code == 204

    second = client.delete(
        f"/api/v1/recipes/{recipe_id}", headers=auth_headers,
    )
    # Server re-stamps deleted_at; iOS handles 204 same as 404
    assert second.status_code == 204


# ---------------------------------------------------------------------------
# User-scoping isolation tests
# ---------------------------------------------------------------------------


def test_user_b_cannot_see_admin_recipes(client, auth_headers, user_b_headers):
    """User B's list does not include admin's recipes."""
    client.post(
        "/api/v1/recipes/",
        json={"name": "Admin Only"},
        headers=auth_headers,
    )

    response = client.get("/api/v1/recipes/", headers=user_b_headers)
    assert response.status_code == 200
    assert len(response.json()) == 0


def test_user_b_cannot_get_admin_recipe(client, auth_headers, user_b_headers):
    """User B gets 404 when trying to GET admin's recipe by id."""
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Admin Secret"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]

    response = client.get(
        f"/api/v1/recipes/{recipe_id}", headers=user_b_headers,
    )
    assert response.status_code == 404


def test_user_b_cannot_update_admin_recipe(client, auth_headers, user_b_headers):
    """User B gets 404 when trying to PUT admin's recipe."""
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Admin Recipe"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]

    response = client.put(
        f"/api/v1/recipes/{recipe_id}",
        json={"name": "Hijacked"},
        headers=user_b_headers,
    )
    assert response.status_code == 404


def test_user_b_cannot_delete_admin_recipe(client, auth_headers, user_b_headers):
    """User B gets 404 when trying to DELETE admin's recipe."""
    resp = client.post(
        "/api/v1/recipes/",
        json={"name": "Admin Precious"},
        headers=auth_headers,
    )
    recipe_id = resp.json()["id"]

    response = client.delete(
        f"/api/v1/recipes/{recipe_id}", headers=user_b_headers,
    )
    assert response.status_code == 404


def test_both_users_can_have_same_recipe_name(client, auth_headers, user_b_headers):
    """Two users can each have a recipe named 'Pasta' without conflict."""
    resp_a = client.post(
        "/api/v1/recipes/",
        json={"name": "Pasta"},
        headers=auth_headers,
    )
    assert resp_a.status_code == 201

    resp_b = client.post(
        "/api/v1/recipes/",
        json={"name": "Pasta"},
        headers=user_b_headers,
    )
    assert resp_b.status_code == 201

    list_a = client.get("/api/v1/recipes/", headers=auth_headers)
    list_b = client.get("/api/v1/recipes/", headers=user_b_headers)
    assert len(list_a.json()) == 1
    assert len(list_b.json()) == 1
    assert list_a.json()[0]["id"] != list_b.json()[0]["id"]
