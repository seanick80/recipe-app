from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from database import Base


class GroceryList(Base):
    __tablename__ = "grocery_lists"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(Text, nullable=False)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )
    archived_at = Column(DateTime(timezone=True), nullable=True)

    items = relationship(
        "GroceryItem",
        back_populates="grocery_list",
        cascade="all, delete-orphan",
    )


class GroceryItem(Base):
    __tablename__ = "grocery_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(Text, nullable=False)
    quantity = Column(Float, default=1.0)
    unit = Column(Text, default="")
    category = Column(Text, default="Other")
    is_checked = Column(Boolean, default=False)
    source_recipe_name = Column(Text, default="")
    source_recipe_id = Column(Text, default="")
    grocery_list_id = Column(
        UUID(as_uuid=True),
        ForeignKey("grocery_lists.id"),
        nullable=False,
    )

    grocery_list = relationship("GroceryList", back_populates="items")


class ShoppingTemplate(Base):
    __tablename__ = "shopping_templates"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(Text, nullable=False)
    sort_order = Column(Integer, default=0)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )

    items = relationship(
        "TemplateItem",
        back_populates="template",
        cascade="all, delete-orphan",
        order_by="TemplateItem.sort_order",
    )


class TemplateItem(Base):
    __tablename__ = "template_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(Text, nullable=False)
    quantity = Column(Float, default=0)
    unit = Column(Text, default="")
    category = Column(Text, default="Other")
    sort_order = Column(Integer, default=0)
    template_id = Column(
        UUID(as_uuid=True),
        ForeignKey("shopping_templates.id"),
        nullable=False,
    )

    template = relationship("ShoppingTemplate", back_populates="items")
