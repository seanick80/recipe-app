from __future__ import annotations

from pydantic import BaseModel, Field


class NormalizationEntry(BaseModel):
    source_url: str | None = Field(None, max_length=2000)
    original_text: str = Field(..., min_length=1, max_length=5000)
    cleaned_text: str = Field(..., min_length=1, max_length=5000)
    normalization_type: str = Field(..., min_length=1, max_length=100)


class ImportNormalizationBatch(BaseModel):
    entries: list[NormalizationEntry] = Field(..., min_length=1, max_length=500)


class ImportNormalizationResponse(BaseModel):
    accepted: int
