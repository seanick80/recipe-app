from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class IngredientCreate(BaseModel):
    name: str
    quantity: float = 0
    unit: str = ""
    category: str = "Other"
    display_order: int = 0
    notes: str = ""


class IngredientResponse(BaseModel):
    id: UUID
    name: str
    quantity: float
    unit: str
    category: str
    display_order: int
    notes: str

    model_config = {"from_attributes": True}


class RecipeCreate(BaseModel):
    name: str
    summary: str = ""
    instructions: str = ""
    prep_time_minutes: int = 0
    cook_time_minutes: int = 0
    servings: int = 1
    cuisine: str = ""
    course: str = ""
    tags: str = ""
    source_url: str = ""
    difficulty: str = ""
    is_favorite: bool = False
    is_published: bool = False
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
    cuisine: str
    course: str
    tags: str
    source_url: str
    difficulty: str
    is_favorite: bool
    is_published: bool
    ingredients: list[IngredientResponse]
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
