from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class GroceryItemCreate(BaseModel):
    name: str
    quantity: float = 1.0
    unit: str = ""
    category: str = "Other"
    source_recipe_name: str = ""
    source_recipe_id: str = ""


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
    name: str


class GroceryListResponse(BaseModel):
    id: UUID
    name: str
    items: list[GroceryItemResponse]
    created_at: datetime
    archived_at: datetime | None

    model_config = {"from_attributes": True}


class TemplateItemCreate(BaseModel):
    name: str
    quantity: float = 0
    unit: str = ""
    category: str = "Other"
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
    name: str
    sort_order: int = 0
    items: list[TemplateItemCreate] = []


class ShoppingTemplateResponse(BaseModel):
    id: UUID
    name: str
    sort_order: int
    items: list[TemplateItemResponse]
    created_at: datetime

    model_config = {"from_attributes": True}
