from __future__ import annotations

from sqlalchemy import Column, DateTime, Integer, Text
from sqlalchemy.sql import func

from database import Base


class ImportNormalizationLog(Base):
    __tablename__ = "import_normalization_logs"

    id = Column(Integer, primary_key=True, index=True)
    source_url = Column(Text, nullable=True)
    original_text = Column(Text, nullable=False)
    cleaned_text = Column(Text, nullable=False)
    normalization_type = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
