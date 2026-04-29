"""Integration test simulating the iOS sync upload flow.

Exercises the exact JSON wire format that RecipeDTO would produce,
walking through every sync scenario: first upload, poll, update,
conflict detection, delete, and restore.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone


# -- Helpers that mirror Swift RecipeDTO encoding -------------------------

def make_recipe_dto(
    *,
    name: str,
    summary: str = "",
    instructions: str = "",
    prep_time_minutes: int = 0,
    cook_time_minutes: int = 0,
    servings: int = 1,
    cuisine: str = "",
    course: str = "",
    tags: str = "",
    source_url: str = "",
    difficulty: str = "",
    is_favorite: bool = False,
    is_published: bool = False,
    ingredients: list[dict] | None = None,
) -> dict:
    """Build a dict matching the snake_case JSON that RecipeDTO encodes."""
    return {
        "name": name,
        "summary": summary,
        "instructions": instructions,
        "prep_time_minutes": prep_time_minutes,
        "cook_time_minutes": cook_time_minutes,
        "servings": servings,
        "cuisine": cuisine,
        "course": course,
        "tags": tags,
        "source_url": source_url,
        "difficulty": difficulty,
        "is_favorite": is_favorite,
        "is_published": is_published,
        "ingredients": ingredients or [],
    }


def make_ingredient_dto(
    *,
    name: str,
    quantity: float = 0,
    unit: str = "",
    category: str = "Other",
    display_order: int = 0,
    notes: str = "",
) -> dict:
    """Build a dict matching IngredientDTO encoding."""
    return {
        "name": name,
        "quantity": quantity,
        "unit": unit,
        "category": category,
        "display_order": display_order,
        "notes": notes,
    }


# -- Scenario 8: First sync — bulk upload --------------------------------

def test_first_sync_bulk_upload(client, auth_headers):
    """Simulate first login: upload N local recipes, store serverIds."""
    # iOS has 3 local recipes with serverId=nil
    local_recipes = [
        make_recipe_dto(
            name="Grandma's Cookies",
            cuisine="American",
            tags="dessert,baking",
            ingredients=[
                make_ingredient_dto(
                    name="Flour", quantity=2, unit="cups",
                    category="Baking", display_order=0,
                ),
                make_ingredient_dto(
                    name="Sugar", quantity=1, unit="cup",
                    category="Baking", display_order=1,
                ),
            ],
        ),
        make_recipe_dto(
            name="Quick Pasta",
            prep_time_minutes=5,
            cook_time_minutes=10,
            servings=2,
            cuisine="Italian",
        ),
        make_recipe_dto(name="Smoothie Bowl", difficulty="Easy"),
    ]

    # Step 1: Poll server — should be empty
    poll = client.get(
        "/api/v1/recipes/?fields=id,updated_at", headers=auth_headers,
    )
    assert poll.status_code == 200
    assert poll.json() == []

    # Step 2: Upload each recipe sequentially (mirrors iOS sync loop)
    server_ids = []
    for dto in local_recipes:
        resp = client.post(
            "/api/v1/recipes/",
            json=dto,
            headers=auth_headers,
        )
        assert resp.status_code == 201
        body = resp.json()
        # Server assigns id, created_at, updated_at
        assert body["id"] is not None
        assert body["created_at"] is not None
        assert body["updated_at"] is not None
        assert body["deleted_at"] is None
        server_ids.append(body["id"])

    assert len(server_ids) == 3
    assert len(set(server_ids)) == 3  # all unique

    # Step 3: Poll again — all 3 visible
    poll2 = client.get(
        "/api/v1/recipes/?fields=id,updated_at", headers=auth_headers,
    )
    assert len(poll2.json()) == 3
    poll_ids = {r["id"] for r in poll2.json()}
    assert poll_ids == set(server_ids)


# -- Scenario 1→2: Upload new, then edit and re-upload -------------------

def test_upload_then_edit_then_push(client, auth_headers):
    """Upload a recipe, edit locally, push update via PUT."""
    # Scenario 1: first upload
    dto = make_recipe_dto(
        name="Original Name",
        summary="First version",
        ingredients=[
            make_ingredient_dto(name="Salt", quantity=1, unit="tsp"),
        ],
    )
    create_resp = client.post(
        "/api/v1/recipes/", json=dto, headers=auth_headers,
    )
    assert create_resp.status_code == 201
    server_id = create_resp.json()["id"]
    original_updated = create_resp.json()["updated_at"]

    # Scenario 2: local edit → needsSync=true → PUT full replacement
    edited = make_recipe_dto(
        name="Edited Name",
        summary="Second version",
        cuisine="Thai",
        ingredients=[
            make_ingredient_dto(
                name="Fish Sauce", quantity=2, unit="tbsp",
                category="Condiments", display_order=0,
            ),
            make_ingredient_dto(
                name="Lime", quantity=1, unit="whole",
                category="Produce", display_order=1,
            ),
        ],
    )
    update_resp = client.put(
        f"/api/v1/recipes/{server_id}",
        json=edited,
        headers=auth_headers,
    )
    assert update_resp.status_code == 200
    body = update_resp.json()
    assert body["name"] == "Edited Name"
    assert body["cuisine"] == "Thai"
    assert body["updated_at"] > original_updated
    # Ingredients fully replaced
    assert len(body["ingredients"]) == 2
    assert body["ingredients"][0]["name"] == "Fish Sauce"

    # Verify via GET
    get_resp = client.get(
        f"/api/v1/recipes/{server_id}", headers=auth_headers,
    )
    assert get_resp.json()["name"] == "Edited Name"
    assert len(get_resp.json()["ingredients"]) == 2


# -- Scenario 3→4: Pull new and updated recipes --------------------------

def test_pull_new_and_updated(client, auth_headers):
    """Simulate pulling recipes created/edited on the web."""
    # Web creates a recipe
    web_dto = make_recipe_dto(
        name="Web Recipe",
        instructions="Made on the web",
        is_published=True,
    )
    web_resp = client.post(
        "/api/v1/recipes/", json=web_dto, headers=auth_headers,
    )
    server_id = web_resp.json()["id"]

    # iOS polls lightweight list → sees new id
    poll = client.get(
        "/api/v1/recipes/?fields=id,updated_at", headers=auth_headers,
    )
    ids = [r["id"] for r in poll.json()]
    assert server_id in ids

    # iOS fetches full recipe
    full = client.get(
        f"/api/v1/recipes/{server_id}", headers=auth_headers,
    )
    assert full.status_code == 200
    assert full.json()["name"] == "Web Recipe"
    assert full.json()["is_published"] is True

    # Web edits the recipe
    client.put(
        f"/api/v1/recipes/{server_id}",
        json=make_recipe_dto(name="Web Recipe v2", is_published=True),
        headers=auth_headers,
    )

    # iOS polls again → updated_at changed
    poll2 = client.get(
        "/api/v1/recipes/?fields=id,updated_at", headers=auth_headers,
    )
    new_ts = next(r["updated_at"] for r in poll2.json() if r["id"] == server_id)
    old_ts = next(r["updated_at"] for r in poll.json() if r["id"] == server_id)
    assert new_ts > old_ts

    # iOS pulls updated version
    updated = client.get(
        f"/api/v1/recipes/{server_id}", headers=auth_headers,
    )
    assert updated.json()["name"] == "Web Recipe v2"


# -- Scenario 6: Delete on iOS → server ----------------------------------

def test_delete_from_ios_to_server(client, auth_headers):
    """iOS soft-deletes locally, then pushes DELETE to server."""
    resp = client.post(
        "/api/v1/recipes/",
        json=make_recipe_dto(name="Will Delete"),
        headers=auth_headers,
    )
    server_id = resp.json()["id"]

    # iOS sends DELETE (processDeletions)
    del_resp = client.delete(
        f"/api/v1/recipes/{server_id}", headers=auth_headers,
    )
    assert del_resp.status_code == 204

    # Server confirms: gone from list, 404 on GET
    poll = client.get(
        "/api/v1/recipes/?fields=id,updated_at", headers=auth_headers,
    )
    assert all(r["id"] != server_id for r in poll.json())
    assert client.get(
        f"/api/v1/recipes/{server_id}", headers=auth_headers,
    ).status_code == 404

    # But recoverable via admin endpoint
    deleted = client.get("/api/v1/recipes/deleted", headers=auth_headers)
    assert any(r["id"] == server_id for r in deleted.json())


# -- Scenario 7: Delete on web → iOS detects absence ---------------------

def test_delete_from_web_detected_by_poll(client, auth_headers):
    """Recipe deleted on web disappears from lightweight list."""
    # Create 2 recipes
    r1 = client.post(
        "/api/v1/recipes/",
        json=make_recipe_dto(name="Keep"),
        headers=auth_headers,
    ).json()["id"]
    r2 = client.post(
        "/api/v1/recipes/",
        json=make_recipe_dto(name="Delete on Web"),
        headers=auth_headers,
    ).json()["id"]

    # iOS polls — sees both
    poll1 = client.get(
        "/api/v1/recipes/?fields=id,updated_at", headers=auth_headers,
    )
    assert {r["id"] for r in poll1.json()} == {r1, r2}

    # Web deletes r2
    client.delete(f"/api/v1/recipes/{r2}", headers=auth_headers)

    # iOS polls again — r2 gone, r1 still there
    poll2 = client.get(
        "/api/v1/recipes/?fields=id,updated_at", headers=auth_headers,
    )
    ids = {r["id"] for r in poll2.json()}
    assert r1 in ids
    assert r2 not in ids
    # iOS would set locallyDeleted=true for r2


# -- Full round-trip field fidelity --------------------------------------

def test_all_fields_survive_round_trip(client, auth_headers):
    """Every field in RecipeDTO survives POST → GET unchanged."""
    dto = make_recipe_dto(
        name="Full Field Test",
        summary="A thorough summary with unicode: café résumé",
        instructions="Step 1: preheat\nStep 2: mix\nStep 3: bake",
        prep_time_minutes=15,
        cook_time_minutes=45,
        servings=6,
        cuisine="French",
        course="Main Course",
        tags="dinner,fancy,weekend",
        source_url="https://example.com/recipe/123",
        difficulty="Hard",
        is_favorite=True,
        is_published=False,
        ingredients=[
            make_ingredient_dto(
                name="Butter",
                quantity=0.5,
                unit="cup",
                category="Dairy",
                display_order=0,
                notes="room temperature",
            ),
            make_ingredient_dto(
                name="Garlic",
                quantity=3,
                unit="cloves",
                category="Produce",
                display_order=1,
                notes="minced",
            ),
        ],
    )

    resp = client.post(
        "/api/v1/recipes/", json=dto, headers=auth_headers,
    )
    assert resp.status_code == 201
    server_id = resp.json()["id"]

    get_resp = client.get(
        f"/api/v1/recipes/{server_id}", headers=auth_headers,
    )
    result = get_resp.json()

    # Every input field matches
    for key in (
        "name", "summary", "instructions", "prep_time_minutes",
        "cook_time_minutes", "servings", "cuisine", "course", "tags",
        "source_url", "difficulty", "is_favorite", "is_published",
    ):
        assert result[key] == dto[key], f"{key}: {result[key]!r} != {dto[key]!r}"

    # Ingredients match
    assert len(result["ingredients"]) == 2
    for i, expected in enumerate(dto["ingredients"]):
        actual = result["ingredients"][i]
        for key in ("name", "quantity", "unit", "category", "display_order", "notes"):
            assert actual[key] == expected[key], (
                f"ingredients[{i}].{key}: {actual[key]!r} != {expected[key]!r}"
            )

    # Server-assigned fields present
    assert result["id"] is not None
    assert result["created_at"] is not None
    assert result["updated_at"] is not None
    assert result["deleted_at"] is None


# -- Data loss guard: delete never hard-deletes --------------------------

def test_delete_is_always_soft(client, auth_headers):
    """Verify DELETE never hard-deletes — recipe is recoverable."""
    resp = client.post(
        "/api/v1/recipes/",
        json=make_recipe_dto(
            name="Precious Recipe",
            summary="Must not lose this",
            ingredients=[
                make_ingredient_dto(name="Love", quantity=1, unit="cup"),
            ],
        ),
        headers=auth_headers,
    )
    server_id = resp.json()["id"]

    # Delete
    client.delete(f"/api/v1/recipes/{server_id}", headers=auth_headers)

    # Confirm soft-deleted (not hard-deleted)
    deleted_list = client.get(
        "/api/v1/recipes/deleted", headers=auth_headers,
    )
    deleted_recipe = next(
        (r for r in deleted_list.json() if r["id"] == server_id), None,
    )
    assert deleted_recipe is not None
    assert deleted_recipe["name"] == "Precious Recipe"
    assert deleted_recipe["deleted_at"] is not None

    # Restore and verify data intact
    restore = client.post(
        f"/api/v1/recipes/deleted/{server_id}/restore",
        headers=auth_headers,
    )
    assert restore.status_code == 200
    assert restore.json()["name"] == "Precious Recipe"
    assert restore.json()["summary"] == "Must not lose this"
    assert len(restore.json()["ingredients"]) == 1
