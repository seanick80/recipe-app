from uuid import UUID
from datetime import datetime
from pydantic import BaseModel


class GroceryItemCreate(BaseModel):
    name: str
    quantity: float = 1.0
    unit: str = ""
    category: str = "Other"


class GroceryItemResponse(GroceryItemCreate):
    id: UUID
    is_checked: bool

    model_config = {"from_attributes": True}


class GroceryListCreate(BaseModel):
    name: str


class GroceryListResponse(BaseModel):
    id: UUID
    name: str
    items: list[GroceryItemResponse]
    created_at: datetime

    model_config = {"from_attributes": True}
