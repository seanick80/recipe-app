from __future__ import annotations

import uuid


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_create_recipe(client):
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
    response = client.post("/api/v1/recipes/", json=data)
    assert response.status_code == 201
    result = response.json()
    assert result["name"] == "Spaghetti Bolognese"
    assert len(result["ingredients"]) == 2


def test_list_recipes(client):
    client.post("/api/v1/recipes/", json={"name": "Recipe 1"})
    client.post("/api/v1/recipes/", json={"name": "Recipe 2"})
    response = client.get("/api/v1/recipes/")
    assert response.status_code == 200
    assert len(response.json()) == 2


def test_delete_recipe(client):
    resp = client.post("/api/v1/recipes/", json={"name": "To Delete"})
    recipe_id = resp.json()["id"]
    response = client.delete(f"/api/v1/recipes/{recipe_id}")
    assert response.status_code == 204


def test_get_recipe(client):
    resp = client.post("/api/v1/recipes/", json={
        "name": "Test Get",
        "summary": "A summary",
        "cuisine": "Italian",
        "course": "Main",
        "ingredients": [
            {"name": "Salt", "quantity": 1, "unit": "tsp"},
        ],
    })
    assert resp.status_code == 201
    recipe_id = resp.json()["id"]

    response = client.get(f"/api/v1/recipes/{recipe_id}")
    assert response.status_code == 200
    result = response.json()
    assert result["name"] == "Test Get"
    assert result["summary"] == "A summary"
    assert result["cuisine"] == "Italian"
    assert result["course"] == "Main"
    assert result["is_favorite"] is False
    assert result["is_published"] is False
    assert len(result["ingredients"]) == 1


def test_update_recipe(client):
    resp = client.post("/api/v1/recipes/", json={
        "name": "Original",
        "servings": 2,
    })
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
    )
    assert response.status_code == 200
    result = response.json()
    assert result["name"] == "Updated"
    assert result["servings"] == 6
    assert result["cuisine"] == "Mexican"
    assert len(result["ingredients"]) == 1
    assert result["ingredients"][0]["name"] == "Tortilla"


def test_recipe_not_found(client):
    fake_id = str(uuid.uuid4())
    response = client.get(f"/api/v1/recipes/{fake_id}")
    assert response.status_code == 404


def test_create_recipe_with_all_fields(client):
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
    response = client.post("/api/v1/recipes/", json=data)
    assert response.status_code == 201
    result = response.json()
    assert result["cuisine"] == "Thai"
    assert result["course"] == "Appetizer"
    assert result["tags"] == "spicy,quick"
    assert result["source_url"] == "https://example.com/recipe"
    assert result["difficulty"] == "Easy"
    assert result["is_favorite"] is True
    assert result["is_published"] is True


def test_ingredient_fields(client):
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
    response = client.post("/api/v1/recipes/", json=data)
    assert response.status_code == 201
    ingredients = response.json()["ingredients"]
    assert ingredients[0]["category"] == "Baking"
    assert ingredients[0]["display_order"] == 1
    assert ingredients[0]["notes"] == "sifted"
    assert ingredients[0]["quantity"] == 2.5
    assert ingredients[1]["display_order"] == 2


def test_toggle_favorite(client):
    resp = client.post("/api/v1/recipes/", json={"name": "Fav Test"})
    recipe_id = resp.json()["id"]
    assert resp.json()["is_favorite"] is False

    response = client.patch(
        f"/api/v1/recipes/{recipe_id}",
        json={"is_favorite": True},
    )
    assert response.status_code == 200
    assert response.json()["is_favorite"] is True


def test_toggle_published(client):
    resp = client.post("/api/v1/recipes/", json={"name": "Pub Test"})
    recipe_id = resp.json()["id"]
    assert resp.json()["is_published"] is False

    response = client.patch(
        f"/api/v1/recipes/{recipe_id}",
        json={"is_published": True},
    )
    assert response.status_code == 200
    assert response.json()["is_published"] is True
