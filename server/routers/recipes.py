from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models.recipe import Ingredient, Recipe
from schemas.recipe import RecipeCreate, RecipeResponse, RecipeUpdate

router = APIRouter(prefix="/api/v1/recipes", tags=["recipes"])


@router.get("/", response_model=list[RecipeResponse])
def list_recipes(db: Session = Depends(get_db)) -> list[Recipe]:
    return db.query(Recipe).order_by(Recipe.updated_at.desc()).all()


@router.get("/{recipe_id}", response_model=RecipeResponse)
def get_recipe(
    recipe_id: UUID,
    db: Session = Depends(get_db),
) -> Recipe:
    recipe = db.query(Recipe).filter(Recipe.id == recipe_id).first()
    if not recipe:
        raise HTTPException(status_code=404, detail="Recipe not found")
    return recipe


@router.post("/", response_model=RecipeResponse, status_code=201)
def create_recipe(
    data: RecipeCreate,
    db: Session = Depends(get_db),
) -> Recipe:
    recipe = Recipe(
        name=data.name,
        summary=data.summary,
        instructions=data.instructions,
        prep_time_minutes=data.prep_time_minutes,
        cook_time_minutes=data.cook_time_minutes,
        servings=data.servings,
        cuisine=data.cuisine,
        course=data.course,
        tags=data.tags,
        source_url=data.source_url,
        difficulty=data.difficulty,
        is_favorite=data.is_favorite,
        is_published=data.is_published,
    )
    for ing in data.ingredients:
        recipe.ingredients.append(
            Ingredient(
                name=ing.name,
                quantity=ing.quantity,
                unit=ing.unit,
                category=ing.category,
                display_order=ing.display_order,
                notes=ing.notes,
            ),
        )
    db.add(recipe)
    db.commit()
    db.refresh(recipe)
    return recipe


@router.put("/{recipe_id}", response_model=RecipeResponse)
def update_recipe(
    recipe_id: UUID,
    data: RecipeUpdate,
    db: Session = Depends(get_db),
) -> Recipe:
    recipe = db.query(Recipe).filter(Recipe.id == recipe_id).first()
    if not recipe:
        raise HTTPException(status_code=404, detail="Recipe not found")

    recipe.name = data.name
    recipe.summary = data.summary
    recipe.instructions = data.instructions
    recipe.prep_time_minutes = data.prep_time_minutes
    recipe.cook_time_minutes = data.cook_time_minutes
    recipe.servings = data.servings
    recipe.cuisine = data.cuisine
    recipe.course = data.course
    recipe.tags = data.tags
    recipe.source_url = data.source_url
    recipe.difficulty = data.difficulty
    recipe.is_favorite = data.is_favorite
    recipe.is_published = data.is_published

    db.query(Ingredient).filter(Ingredient.recipe_id == recipe_id).delete()
    for ing in data.ingredients:
        recipe.ingredients.append(
            Ingredient(
                name=ing.name,
                quantity=ing.quantity,
                unit=ing.unit,
                category=ing.category,
                display_order=ing.display_order,
                notes=ing.notes,
            ),
        )
    db.commit()
    db.refresh(recipe)
    return recipe


@router.patch("/{recipe_id}", response_model=RecipeResponse)
def patch_recipe(
    recipe_id: UUID,
    updates: dict,
    db: Session = Depends(get_db),
) -> Recipe:
    """Toggle individual fields like is_favorite or is_published."""
    recipe = db.query(Recipe).filter(Recipe.id == recipe_id).first()
    if not recipe:
        raise HTTPException(status_code=404, detail="Recipe not found")

    allowed = {"is_favorite", "is_published"}
    for key, value in updates.items():
        if key in allowed:
            setattr(recipe, key, value)

    db.commit()
    db.refresh(recipe)
    return recipe


@router.delete("/{recipe_id}", status_code=204, response_model=None)
def delete_recipe(
    recipe_id: UUID,
    db: Session = Depends(get_db),
):
    recipe = db.query(Recipe).filter(Recipe.id == recipe_id).first()
    if not recipe:
        raise HTTPException(status_code=404, detail="Recipe not found")
    db.delete(recipe)
    db.commit()
