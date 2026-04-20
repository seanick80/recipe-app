from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from auth import get_api_key
from database import get_db
from rate_limit import limiter
from models.grocery import (
    GroceryItem,
    GroceryList,
    ShoppingTemplate,
    TemplateItem,
)
from schemas.grocery import (
    GroceryItemCreate,
    GroceryItemPatch,
    GroceryItemResponse,
    GroceryListCreate,
    GroceryListResponse,
    ShoppingTemplateCreate,
    ShoppingTemplateResponse,
)

router = APIRouter(prefix="/api/v1/grocery", tags=["grocery"])


# --- Grocery Lists ---


@router.get("/lists", response_model=list[GroceryListResponse])
@limiter.limit("120/minute")
def list_grocery_lists(
    request: Request,
    db: Session = Depends(get_db),
) -> list[GroceryList]:
    return (
        db.query(GroceryList)
        .order_by(GroceryList.created_at.desc())
        .all()
    )


@router.get("/lists/{list_id}", response_model=GroceryListResponse)
@limiter.limit("120/minute")
def get_grocery_list(
    request: Request,
    list_id: UUID,
    db: Session = Depends(get_db),
) -> GroceryList:
    grocery_list = (
        db.query(GroceryList)
        .filter(GroceryList.id == list_id)
        .first()
    )
    if not grocery_list:
        raise HTTPException(status_code=404, detail="List not found")
    return grocery_list


@router.post("/lists", response_model=GroceryListResponse, status_code=201)
@limiter.limit("30/minute")
def create_grocery_list(
    request: Request,
    data: GroceryListCreate,
    db: Session = Depends(get_db),
    _key: str = Depends(get_api_key),
) -> GroceryList:
    grocery_list = GroceryList(name=data.name)
    db.add(grocery_list)
    db.commit()
    db.refresh(grocery_list)
    return grocery_list


@router.delete("/lists/{list_id}", status_code=204, response_model=None)
@limiter.limit("30/minute")
def delete_grocery_list(
    request: Request,
    list_id: UUID,
    db: Session = Depends(get_db),
    _key: str = Depends(get_api_key),
):
    grocery_list = (
        db.query(GroceryList)
        .filter(GroceryList.id == list_id)
        .first()
    )
    if not grocery_list:
        raise HTTPException(status_code=404, detail="List not found")
    db.delete(grocery_list)
    db.commit()


@router.patch(
    "/lists/{list_id}/archive",
    response_model=GroceryListResponse,
)
@limiter.limit("30/minute")
def archive_grocery_list(
    request: Request,
    list_id: UUID,
    db: Session = Depends(get_db),
    _key: str = Depends(get_api_key),
) -> GroceryList:
    grocery_list = (
        db.query(GroceryList)
        .filter(GroceryList.id == list_id)
        .first()
    )
    if not grocery_list:
        raise HTTPException(status_code=404, detail="List not found")
    grocery_list.archived_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(grocery_list)
    return grocery_list


@router.patch(
    "/lists/{list_id}/restore",
    response_model=GroceryListResponse,
)
@limiter.limit("30/minute")
def restore_grocery_list(
    request: Request,
    list_id: UUID,
    db: Session = Depends(get_db),
    _key: str = Depends(get_api_key),
) -> GroceryList:
    grocery_list = (
        db.query(GroceryList)
        .filter(GroceryList.id == list_id)
        .first()
    )
    if not grocery_list:
        raise HTTPException(status_code=404, detail="List not found")
    grocery_list.archived_at = None
    db.commit()
    db.refresh(grocery_list)
    return grocery_list


# --- Grocery Items ---


@router.post(
    "/lists/{list_id}/items",
    response_model=GroceryItemResponse,
    status_code=201,
)
@limiter.limit("30/minute")
def add_item(
    request: Request,
    list_id: UUID,
    data: GroceryItemCreate,
    db: Session = Depends(get_db),
    _key: str = Depends(get_api_key),
) -> GroceryItem:
    grocery_list = (
        db.query(GroceryList)
        .filter(GroceryList.id == list_id)
        .first()
    )
    if not grocery_list:
        raise HTTPException(status_code=404, detail="List not found")
    item = GroceryItem(
        name=data.name,
        quantity=data.quantity,
        unit=data.unit,
        category=data.category,
        source_recipe_name=data.source_recipe_name,
        source_recipe_id=data.source_recipe_id,
        grocery_list_id=list_id,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.patch(
    "/items/{item_id}/toggle",
    response_model=GroceryItemResponse,
)
@limiter.limit("30/minute")
def toggle_item(
    request: Request,
    item_id: UUID,
    db: Session = Depends(get_db),
    _key: str = Depends(get_api_key),
) -> GroceryItem:
    item = (
        db.query(GroceryItem)
        .filter(GroceryItem.id == item_id)
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    item.is_checked = not item.is_checked
    db.commit()
    db.refresh(item)
    return item


@router.patch("/items/{item_id}", response_model=GroceryItemResponse)
@limiter.limit("30/minute")
def update_item(
    request: Request,
    item_id: UUID,
    updates: GroceryItemPatch,
    db: Session = Depends(get_db),
    _key: str = Depends(get_api_key),
) -> GroceryItem:
    """Update item fields (name, quantity, unit, category, is_checked)."""
    item = (
        db.query(GroceryItem)
        .filter(GroceryItem.id == item_id)
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    patch_data = updates.model_dump(exclude_unset=True)
    for key, value in patch_data.items():
        setattr(item, key, value)

    db.commit()
    db.refresh(item)
    return item


@router.delete("/items/{item_id}", status_code=204, response_model=None)
@limiter.limit("30/minute")
def delete_item(
    request: Request,
    item_id: UUID,
    db: Session = Depends(get_db),
    _key: str = Depends(get_api_key),
):
    item = (
        db.query(GroceryItem)
        .filter(GroceryItem.id == item_id)
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    db.delete(item)
    db.commit()


# --- Shopping Templates ---


@router.get("/templates", response_model=list[ShoppingTemplateResponse])
@limiter.limit("120/minute")
def list_templates(
    request: Request,
    db: Session = Depends(get_db),
) -> list[ShoppingTemplate]:
    return (
        db.query(ShoppingTemplate)
        .order_by(ShoppingTemplate.sort_order)
        .all()
    )


@router.get(
    "/templates/{template_id}",
    response_model=ShoppingTemplateResponse,
)
@limiter.limit("120/minute")
def get_template(
    request: Request,
    template_id: UUID,
    db: Session = Depends(get_db),
) -> ShoppingTemplate:
    template = (
        db.query(ShoppingTemplate)
        .filter(ShoppingTemplate.id == template_id)
        .first()
    )
    if not template:
        raise HTTPException(
            status_code=404,
            detail="Template not found",
        )
    return template


@router.post(
    "/templates",
    response_model=ShoppingTemplateResponse,
    status_code=201,
)
@limiter.limit("30/minute")
def create_template(
    request: Request,
    data: ShoppingTemplateCreate,
    db: Session = Depends(get_db),
    _key: str = Depends(get_api_key),
) -> ShoppingTemplate:
    template = ShoppingTemplate(
        name=data.name,
        sort_order=data.sort_order,
    )
    for item in data.items:
        template.items.append(
            TemplateItem(
                name=item.name,
                quantity=item.quantity,
                unit=item.unit,
                category=item.category,
                sort_order=item.sort_order,
            ),
        )
    db.add(template)
    db.commit()
    db.refresh(template)
    return template


@router.put(
    "/templates/{template_id}",
    response_model=ShoppingTemplateResponse,
)
@limiter.limit("30/minute")
def update_template(
    request: Request,
    template_id: UUID,
    data: ShoppingTemplateCreate,
    db: Session = Depends(get_db),
    _key: str = Depends(get_api_key),
) -> ShoppingTemplate:
    template = (
        db.query(ShoppingTemplate)
        .filter(ShoppingTemplate.id == template_id)
        .first()
    )
    if not template:
        raise HTTPException(
            status_code=404,
            detail="Template not found",
        )

    template.name = data.name
    template.sort_order = data.sort_order

    db.query(TemplateItem).filter(
        TemplateItem.template_id == template_id,
    ).delete()
    for item in data.items:
        template.items.append(
            TemplateItem(
                name=item.name,
                quantity=item.quantity,
                unit=item.unit,
                category=item.category,
                sort_order=item.sort_order,
            ),
        )
    db.commit()
    db.refresh(template)
    return template


@router.delete("/templates/{template_id}", status_code=204, response_model=None)
@limiter.limit("30/minute")
def delete_template(
    request: Request,
    template_id: UUID,
    db: Session = Depends(get_db),
    _key: str = Depends(get_api_key),
):
    template = (
        db.query(ShoppingTemplate)
        .filter(ShoppingTemplate.id == template_id)
        .first()
    )
    if not template:
        raise HTTPException(
            status_code=404,
            detail="Template not found",
        )
    db.delete(template)
    db.commit()
