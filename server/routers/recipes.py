from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models.recipe import Recipe, Ingredient
from schemas.recipe import RecipeCreate, RecipeUpdate, RecipeResponse

router = APIRouter(prefix="/api/v1/recipes", tags=["recipes"])


@router.get("/", response_model=list[RecipeResponse])
def list_recipes(db: Session = Depends(get_db)):
    return db.query(Recipe).order_by(Recipe.updated_at.desc()).all()


@router.get("/{recipe_id}", response_model=RecipeResponse)
def get_recipe(recipe_id: UUID, db: Session = Depends(get_db)):
    recipe = db.query(Recipe).filter(Recipe.id == recipe_id).first()
    if not recipe:
        raise HTTPException(status_code=404, detail="Recipe not found")
    return recipe


@router.post("/", response_model=RecipeResponse, status_code=201)
def create_recipe(data: RecipeCreate, db: Session = Depends(get_db)):
    recipe = Recipe(
        name=data.name,
        summary=data.summary,
        instructions=data.instructions,
        prep_time_minutes=data.prep_time_minutes,
        cook_time_minutes=data.cook_time_minutes,
        servings=data.servings,
    )
    for ing in data.ingredients:
        recipe.ingredients.append(
            Ingredient(name=ing.name, quantity=str(ing.quantity), unit=ing.unit)
        )
    db.add(recipe)
    db.commit()
    db.refresh(recipe)
    return recipe


@router.put("/{recipe_id}", response_model=RecipeResponse)
def update_recipe(recipe_id: UUID, data: RecipeUpdate, db: Session = Depends(get_db)):
    recipe = db.query(Recipe).filter(Recipe.id == recipe_id).first()
    if not recipe:
        raise HTTPException(status_code=404, detail="Recipe not found")

    recipe.name = data.name
    recipe.summary = data.summary
    recipe.instructions = data.instructions
    recipe.prep_time_minutes = data.prep_time_minutes
    recipe.cook_time_minutes = data.cook_time_minutes
    recipe.servings = data.servings

    db.query(Ingredient).filter(Ingredient.recipe_id == recipe_id).delete()
    for ing in data.ingredients:
        recipe.ingredients.append(
            Ingredient(name=ing.name, quantity=str(ing.quantity), unit=ing.unit)
        )
    db.commit()
    db.refresh(recipe)
    return recipe


@router.delete("/{recipe_id}", status_code=204)
def delete_recipe(recipe_id: UUID, db: Session = Depends(get_db)):
    recipe = db.query(Recipe).filter(Recipe.id == recipe_id).first()
    if not recipe:
        raise HTTPException(status_code=404, detail="Recipe not found")
    db.delete(recipe)
    db.commit()
