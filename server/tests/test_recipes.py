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


def test_create_grocery_list(client):
    resp = client.post("/api/v1/grocery/lists", json={"name": "Weekly"})
    assert resp.status_code == 201
    list_id = resp.json()["id"]

    item_resp = client.post(
        f"/api/v1/grocery/lists/{list_id}/items",
        json={"name": "Milk", "quantity": 1, "unit": "gallon", "category": "Dairy"},
    )
    assert item_resp.status_code == 201
    assert item_resp.json()["name"] == "Milk"
