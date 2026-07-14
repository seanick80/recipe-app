from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from auth import get_current_user
from database import get_db
from models.grocery import (
    GroceryItem,
    GroceryList,
    ShoppingTemplate,
    TemplateItem,
)
from models.user import AllowedUser
from rate_limit import limiter
from schemas.grocery import (
    GroceryItemCreate,
    GroceryItemPatch,
    GroceryItemResponse,
    GroceryListCreate,
    GroceryListResponse,
    ShoppingTemplateCreate,
    ShoppingTemplateResponse,
    SyncListItem,
)

router = APIRouter(prefix="/api/v1/grocery", tags=["grocery"])


def _now() -> datetime:
    return datetime.now(timezone.utc)


# --- Grocery Lists ---


@router.get("/lists")
@limiter.limit("120/minute")
def list_grocery_lists(
    request: Request,
    fields: Optional[str] = Query(None),
    db: Session = Depends(get_db),
) -> list:
    """List grocery lists. Use ?fields=id,updated_at for lightweight sync."""
    if fields:
        requested = {f.strip() for f in fields.split(",")}
        if requested == {"id", "updated_at"}:
            rows = (
                db.query(GroceryList.id, GroceryList.updated_at)
                .order_by(GroceryList.updated_at.desc())
                .all()
            )
            return [
                SyncListItem(id=row.id, updated_at=row.updated_at).model_dump(
                    mode="json",
                )
                for row in rows
            ]
    lists = (
        db.query(GroceryList)
        .order_by(GroceryList.created_at.desc())
        .all()
    )
    return [
        GroceryListResponse.model_validate(gl).model_dump(mode="json")
        for gl in lists
    ]


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
    _user: AllowedUser = Depends(get_current_user),
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
    _user: AllowedUser = Depends(get_current_user),
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
    _user: AllowedUser = Depends(get_current_user),
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
    _user: AllowedUser = Depends(get_current_user),
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
    _user: AllowedUser = Depends(get_current_user),
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
    # Bump parent list so a list-level watermark reflects item edits.
    grocery_list.updated_at = _now()
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
    _user: AllowedUser = Depends(get_current_user),
) -> GroceryItem:
    item = (
        db.query(GroceryItem)
        .filter(GroceryItem.id == item_id)
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    item.is_checked = not item.is_checked
    item.grocery_list.updated_at = _now()
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
    _user: AllowedUser = Depends(get_current_user),
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

    item.grocery_list.updated_at = _now()
    db.commit()
    db.refresh(item)
    return item


@router.delete("/items/{item_id}", status_code=204, response_model=None)
@limiter.limit("30/minute")
def delete_item(
    request: Request,
    item_id: UUID,
    db: Session = Depends(get_db),
    _user: AllowedUser = Depends(get_current_user),
):
    item = (
        db.query(GroceryItem)
        .filter(GroceryItem.id == item_id)
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    item.grocery_list.updated_at = _now()
    db.delete(item)
    db.commit()


# --- Shopping Templates ---


@router.get("/templates")
@limiter.limit("120/minute")
def list_templates(
    request: Request,
    fields: Optional[str] = Query(None),
    db: Session = Depends(get_db),
) -> list:
    """List templates. Use ?fields=id,updated_at for lightweight sync."""
    if fields:
        requested = {f.strip() for f in fields.split(",")}
        if requested == {"id", "updated_at"}:
            rows = (
                db.query(ShoppingTemplate.id, ShoppingTemplate.updated_at)
                .order_by(ShoppingTemplate.updated_at.desc())
                .all()
            )
            return [
                SyncListItem(id=row.id, updated_at=row.updated_at).model_dump(
                    mode="json",
                )
                for row in rows
            ]
    templates = (
        db.query(ShoppingTemplate)
        .order_by(ShoppingTemplate.sort_order)
        .all()
    )
    return [
        ShoppingTemplateResponse.model_validate(t).model_dump(mode="json")
        for t in templates
    ]


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
    _user: AllowedUser = Depends(get_current_user),
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
    _user: AllowedUser = Depends(get_current_user),
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
    template.updated_at = _now()

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
    _user: AllowedUser = Depends(get_current_user),
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
