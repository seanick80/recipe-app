from uuid import UUID
from datetime import datetime
from pydantic import BaseModel


class IngredientCreate(BaseModel):
    name: str
    quantity: float = 0
    unit: str = ""


class IngredientResponse(IngredientCreate):
    id: UUID

    model_config = {"from_attributes": True}


class RecipeCreate(BaseModel):
    name: str
    summary: str = ""
    instructions: str = ""
    prep_time_minutes: int = 0
    cook_time_minutes: int = 0
    servings: int = 1
    ingredients: list[IngredientCreate] = []


class RecipeUpdate(RecipeCreate):
    pass


class RecipeResponse(BaseModel):
    id: UUID
    name: str
    summary: str
    instructions: str
    prep_time_minutes: int
    cook_time_minutes: int
    servings: int
    ingredients: list[IngredientResponse]
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
