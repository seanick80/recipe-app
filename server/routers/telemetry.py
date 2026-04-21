from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from database import get_db
from models.telemetry import ImportNormalizationLog
from rate_limit import limiter
from schemas.telemetry import ImportNormalizationBatch, ImportNormalizationResponse

router = APIRouter(prefix="/api/v1/telemetry", tags=["telemetry"])


@router.post(
    "/import-normalizations",
    response_model=ImportNormalizationResponse,
    status_code=200,
)
@limiter.limit("60/minute")
def log_import_normalizations(
    request: Request,
    batch: ImportNormalizationBatch,
    db: Session = Depends(get_db),
) -> ImportNormalizationResponse:
    """Accept a batch of ingredient normalization events from the iOS app."""
    logs = [
        ImportNormalizationLog(
            source_url=entry.source_url,
            original_text=entry.original_text,
            cleaned_text=entry.cleaned_text,
            normalization_type=entry.normalization_type,
        )
        for entry in batch.entries
    ]
    db.add_all(logs)
    db.commit()
    return ImportNormalizationResponse(accepted=len(logs))
