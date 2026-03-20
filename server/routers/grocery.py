from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models.grocery import GroceryList, GroceryItem
from schemas.grocery import GroceryListCreate, GroceryListResponse, GroceryItemCreate, GroceryItemResponse

router = APIRouter(prefix="/api/v1/grocery", tags=["grocery"])


@router.get("/lists", response_model=list[GroceryListResponse])
def list_grocery_lists(db: Session = Depends(get_db)):
    return db.query(GroceryList).order_by(GroceryList.created_at.desc()).all()


@router.post("/lists", response_model=GroceryListResponse, status_code=201)
def create_grocery_list(data: GroceryListCreate, db: Session = Depends(get_db)):
    grocery_list = GroceryList(name=data.name)
    db.add(grocery_list)
    db.commit()
    db.refresh(grocery_list)
    return grocery_list


@router.delete("/lists/{list_id}", status_code=204)
def delete_grocery_list(list_id: UUID, db: Session = Depends(get_db)):
    grocery_list = db.query(GroceryList).filter(GroceryList.id == list_id).first()
    if not grocery_list:
        raise HTTPException(status_code=404, detail="List not found")
    db.delete(grocery_list)
    db.commit()


@router.post("/lists/{list_id}/items", response_model=GroceryItemResponse, status_code=201)
def add_item(list_id: UUID, data: GroceryItemCreate, db: Session = Depends(get_db)):
    grocery_list = db.query(GroceryList).filter(GroceryList.id == list_id).first()
    if not grocery_list:
        raise HTTPException(status_code=404, detail="List not found")
    item = GroceryItem(
        name=data.name,
        quantity=data.quantity,
        unit=data.unit,
        category=data.category,
        grocery_list_id=list_id,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.patch("/items/{item_id}/toggle", response_model=GroceryItemResponse)
def toggle_item(item_id: UUID, db: Session = Depends(get_db)):
    item = db.query(GroceryItem).filter(GroceryItem.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    item.is_checked = not item.is_checked
    db.commit()
    db.refresh(item)
    return item


@router.delete("/items/{item_id}", status_code=204)
def delete_item(item_id: UUID, db: Session = Depends(get_db)):
    item = db.query(GroceryItem).filter(GroceryItem.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    db.delete(item)
    db.commit()
