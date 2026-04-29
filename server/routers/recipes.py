from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from auth import get_current_user
from database import get_db
from models.recipe import Ingredient, Recipe
from models.user import AllowedUser
from rate_limit import limiter
from schemas.recipe import (
    RecipeCreate,
    RecipeListItem,
    RecipePatch,
    RecipeResponse,
    RecipeUpdate,
)

router = APIRouter(prefix="/api/v1/recipes", tags=["recipes"])


def _active_recipes(db: Session, user: AllowedUser | None = None):
    """Base query filtering out soft-deleted recipes, optionally scoped to user."""
    q = db.query(Recipe).filter(Recipe.deleted_at.is_(None))
    if user is not None:
        q = q.filter(Recipe.user_id == user.id)
    return q


@router.get("")
@router.get("/")
@limiter.limit("120/minute")
def list_recipes(
    request: Request,
    fields: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    user: AllowedUser = Depends(get_current_user),
) -> list:
    """List recipes. Use ?fields=id,updated_at for lightweight sync."""
    if fields:
        requested = {f.strip() for f in fields.split(",")}
        if requested == {"id", "updated_at"}:
            rows = (
                _active_recipes(db, user)
                .with_entities(Recipe.id, Recipe.updated_at)
                .order_by(Recipe.updated_at.desc())
                .all()
            )
            return [
                RecipeListItem(id=row.id, updated_at=row.updated_at).model_dump(
                    mode="json",
                )
                for row in rows
            ]
    recipes = _active_recipes(db, user).order_by(Recipe.updated_at.desc()).all()
    return [RecipeResponse.model_validate(r).model_dump(mode="json") for r in recipes]


@router.get("/deleted", response_model=list[RecipeResponse])
@limiter.limit("30/minute")
def list_deleted_recipes(
    request: Request,
    db: Session = Depends(get_db),
    user: AllowedUser = Depends(get_current_user),
) -> list[Recipe]:
    """List soft-deleted recipes for the current user."""
    return (
        db.query(Recipe)
        .filter(Recipe.deleted_at.isnot(None), Recipe.user_id == user.id)
        .order_by(Recipe.deleted_at.desc())
        .all()
    )


@router.post(
    "/deleted/{recipe_id}/restore",
    response_model=RecipeResponse,
)
@limiter.limit("30/minute")
def restore_recipe(
    request: Request,
    recipe_id: UUID,
    db: Session = Depends(get_db),
    user: AllowedUser = Depends(get_current_user),
) -> Recipe:
    """Restore a soft-deleted recipe."""
    recipe = (
        db.query(Recipe)
        .filter(
            Recipe.id == recipe_id,
            Recipe.deleted_at.isnot(None),
            Recipe.user_id == user.id,
        )
        .first()
    )
    if not recipe:
        raise HTTPException(
            status_code=404,
            detail="Deleted recipe not found",
        )
    recipe.deleted_at = None
    db.commit()
    db.refresh(recipe)
    return recipe


@router.get("/{recipe_id}", response_model=RecipeResponse)
@limiter.limit("120/minute")
def get_recipe(
    request: Request,
    recipe_id: UUID,
    db: Session = Depends(get_db),
    user: AllowedUser = Depends(get_current_user),
) -> Recipe:
    recipe = _active_recipes(db, user).filter(Recipe.id == recipe_id).first()
    if not recipe:
        raise HTTPException(status_code=404, detail="Recipe not found")
    return recipe


@router.post("", response_model=RecipeResponse, status_code=201)
@router.post("/", response_model=RecipeResponse, status_code=201)
@limiter.limit("30/minute")
def create_recipe(
    request: Request,
    data: RecipeCreate,
    db: Session = Depends(get_db),
    user: AllowedUser = Depends(get_current_user),
) -> Recipe:
    recipe = Recipe(
        user_id=user.id,
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
@limiter.limit("30/minute")
def update_recipe(
    request: Request,
    recipe_id: UUID,
    data: RecipeUpdate,
    db: Session = Depends(get_db),
    user: AllowedUser = Depends(get_current_user),
) -> Recipe:
    recipe = _active_recipes(db, user).filter(Recipe.id == recipe_id).first()
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
@limiter.limit("30/minute")
def patch_recipe(
    request: Request,
    recipe_id: UUID,
    updates: RecipePatch,
    db: Session = Depends(get_db),
    user: AllowedUser = Depends(get_current_user),
) -> Recipe:
    """Toggle individual fields like is_favorite or is_published."""
    recipe = _active_recipes(db, user).filter(Recipe.id == recipe_id).first()
    if not recipe:
        raise HTTPException(status_code=404, detail="Recipe not found")

    patch_data = updates.model_dump(exclude_unset=True)
    for key, value in patch_data.items():
        setattr(recipe, key, value)

    db.commit()
    db.refresh(recipe)
    return recipe


@router.delete("/{recipe_id}", status_code=204, response_model=None)
@limiter.limit("30/minute")
def delete_recipe(
    request: Request,
    recipe_id: UUID,
    db: Session = Depends(get_db),
    user: AllowedUser = Depends(get_current_user),
):
    recipe = (
        db.query(Recipe)
        .filter(Recipe.id == recipe_id, Recipe.user_id == user.id)
        .first()
    )
    if not recipe:
        raise HTTPException(status_code=404, detail="Recipe not found")
    recipe.deleted_at = datetime.now(timezone.utc)
    db.commit()
