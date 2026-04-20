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
    LargeBinary,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from database import Base


class Recipe(Base):
    __tablename__ = "recipes"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(Text, nullable=False)
    summary = Column(Text, default="")
    instructions = Column(Text, default="")
    prep_time_minutes = Column(Integer, default=0)
    cook_time_minutes = Column(Integer, default=0)
    servings = Column(Integer, default=1)
    cuisine = Column(Text, default="")
    course = Column(Text, default="")
    tags = Column(Text, default="")
    source_url = Column(Text, default="")
    difficulty = Column(Text, default="")
    is_favorite = Column(Boolean, default=False)
    is_published = Column(Boolean, default=False)
    image_data = Column(LargeBinary, nullable=True)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    ingredients = relationship(
        "Ingredient",
        back_populates="recipe",
        cascade="all, delete-orphan",
        order_by="Ingredient.display_order",
    )


class Ingredient(Base):
    __tablename__ = "ingredients"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(Text, nullable=False)
    quantity = Column(Float, default=0)
    unit = Column(Text, default="")
    category = Column(Text, default="Other")
    display_order = Column(Integer, default=0)
    notes = Column(Text, default="")
    recipe_id = Column(
        UUID(as_uuid=True),
        ForeignKey("recipes.id"),
        nullable=False,
    )

    recipe = relationship("Recipe", back_populates="ingredients")
