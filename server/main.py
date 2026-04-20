from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded

from logging_config import get_audit_logger, setup_logging
from rate_limit import limiter
from routers import auth_routes, grocery, recipes

logger = logging.getLogger(__name__)


setup_logging()


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Recipe App server starting")
    yield
    logger.info("Recipe App server shutting down")


app = FastAPI(title="Recipe App API", version="1.0.0", lifespan=lifespan)

audit = get_audit_logger()

app.state.limiter = limiter


async def _rate_limit_handler(request: Request, exc: RateLimitExceeded) -> JSONResponse:
    audit.warning("RATE_LIMITED ip=%s path=%s", request.client.host, request.url.path)
    return JSONResponse(status_code=429, content={"detail": "Rate limit exceeded"})


app.add_exception_handler(RateLimitExceeded, _rate_limit_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "https://recipes.ouryearofwander.com",
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "X-API-Key"],
)

app.include_router(auth_routes.router)
app.include_router(recipes.router)
app.include_router(grocery.router)


@app.exception_handler(Exception)
async def global_exception_handler(
    request: Request,
    exc: Exception,
) -> JSONResponse:
    logger.exception("Unhandled exception: %s", exc)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"},
    )


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
