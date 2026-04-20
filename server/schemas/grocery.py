from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class GroceryItemCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=500)
    quantity: float = Field(1.0, ge=0, le=100000)
    unit: str = Field("", max_length=50)
    category: str = Field("Other", max_length=100)
    source_recipe_name: str = Field("", max_length=500)
    source_recipe_id: str = Field("", max_length=100)


class GroceryItemPatch(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=500)
    quantity: float | None = Field(None, ge=0, le=100000)
    unit: str | None = Field(None, max_length=50)
    category: str | None = Field(None, max_length=100)
    is_checked: bool | None = None


class GroceryItemResponse(BaseModel):
    id: UUID
    name: str
    quantity: float
    unit: str
    category: str
    is_checked: bool
    source_recipe_name: str
    source_recipe_id: str

    model_config = {"from_attributes": True}


class GroceryListCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=500)


class GroceryListResponse(BaseModel):
    id: UUID
    name: str
    items: list[GroceryItemResponse]
    created_at: datetime
    archived_at: datetime | None

    model_config = {"from_attributes": True}


class TemplateItemCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=500)
    quantity: float = Field(0, ge=0, le=100000)
    unit: str = Field("", max_length=50)
    category: str = Field("Other", max_length=100)
    sort_order: int = 0


class TemplateItemResponse(BaseModel):
    id: UUID
    name: str
    quantity: float
    unit: str
    category: str
    sort_order: int

    model_config = {"from_attributes": True}


class ShoppingTemplateCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=500)
    sort_order: int = 0
    items: list[TemplateItemCreate] = []


class ShoppingTemplateResponse(BaseModel):
    id: UUID
    name: str
    sort_order: int
    items: list[TemplateItemResponse]
    created_at: datetime

    model_config = {"from_attributes": True}
