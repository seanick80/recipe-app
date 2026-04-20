from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class IngredientCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=500)
    quantity: float = Field(0, ge=0, le=100000)
    unit: str = Field("", max_length=50)
    category: str = Field("Other", max_length=100)
    display_order: int = 0
    notes: str = Field("", max_length=1000)


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
    name: str = Field(..., min_length=1, max_length=500)
    summary: str = Field("", max_length=2000)
    instructions: str = Field("", max_length=50000)
    prep_time_minutes: int = Field(0, ge=0, le=10080)
    cook_time_minutes: int = Field(0, ge=0, le=10080)
    servings: int = Field(1, ge=1, le=1000)
    cuisine: str = Field("", max_length=100)
    course: str = Field("", max_length=100)
    tags: str = Field("", max_length=1000)
    source_url: str = Field("", max_length=2000)
    difficulty: str = Field("", max_length=50)
    is_favorite: bool = False
    is_published: bool = False
    ingredients: list[IngredientCreate] = []


class RecipeUpdate(RecipeCreate):
    pass


class RecipePatch(BaseModel):
    is_favorite: bool | None = None
    is_published: bool | None = None


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
