from __future__ import annotations

import logging
import re
from contextlib import asynccontextmanager
from html import escape as html_escape
from pathlib import Path
from uuid import UUID

from fastapi import FastAPI, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from slowapi.errors import RateLimitExceeded

from database import SessionLocal
from logging_config import get_audit_logger, setup_logging
from models.recipe import Recipe
from rate_limit import limiter
from routers import auth_routes, grocery, recipes, telemetry

logger = logging.getLogger(__name__)


setup_logging()


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Recipe App server starting")
    yield
    logger.info("Recipe App server shutting down")


app = FastAPI(
    title="Recipe App API",
    version="1.0.0",
    lifespan=lifespan,
    redirect_slashes=False,
)

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
app.include_router(telemetry.router)


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


# --- Serve frontend SPA from static/ (must be after all API routes) ---

STATIC_DIR = Path(__file__).parent / "static"
INDEX_FILE = STATIC_DIR / "index.html"

# Matches a client-side single-recipe route: "recipes/<uuid>".
_RECIPE_PATH_RE = re.compile(r"^recipes/([0-9a-fA-F-]{36})$")


def inject_recipe_meta(index_html: str, name: str, summary: str) -> str:
    """Return the built index.html with the recipe's title and Open Graph tags
    substituted in, so a shared recipe link shows the recipe name in the browser
    tab (before JS runs) and in link-preview unfurls. Pure string transform —
    unit-tested independently of the DB and the request path."""
    result = index_html.replace(
        "<title>Recipe App</title>",
        f"<title>{html_escape(f'{name} · Recipe App')}</title>",
        1,
    )
    result = result.replace(
        '<meta property="og:title" content="Recipe App" />',
        f'<meta property="og:title" content="{html_escape(name)}" />',
        1,
    )
    if summary:
        desc = f'<meta property="og:description" content="{html_escape(summary)}" />'
        result = result.replace("</head>", f"    {desc}\n  </head>", 1)
    return result


def _published_recipe_meta(recipe_id: str) -> tuple[str, str] | None:
    """(name, summary) for a published, non-deleted recipe, else None.

    Short synchronous DB lookup used only to enrich the served HTML; mirrors the
    gate on GET /api/v1/recipes/{id}/public so nothing unpublished leaks.
    """
    try:
        rid = UUID(recipe_id)
    except ValueError:
        return None
    db = SessionLocal()
    try:
        recipe = (
            db.query(Recipe)
            .filter(
                Recipe.id == rid,
                Recipe.deleted_at.is_(None),
                Recipe.is_published.is_(True),
            )
            .first()
        )
        if recipe is None:
            return None
        return (recipe.name, recipe.summary or "")
    finally:
        db.close()


if STATIC_DIR.is_dir():
    # Serve JS/CSS/assets at their exact paths
    app.mount(
        "/assets",
        StaticFiles(directory=STATIC_DIR / "assets"),
        name="static-assets",
    )

    @app.get("/{path:path}")
    async def spa_fallback(path: str) -> Response:
        """Serve index.html for all non-API routes (SPA client-side routing).

        For a published single-recipe route, inject the recipe's title/OG tags
        so shared links render the recipe name rather than the generic default.
        """
        file = STATIC_DIR / path
        if file.is_file():
            return FileResponse(file)

        match = _RECIPE_PATH_RE.match(path)
        if match and INDEX_FILE.is_file():
            try:
                meta = await run_in_threadpool(_published_recipe_meta, match.group(1))
                if meta is not None:
                    index_html = await run_in_threadpool(
                        INDEX_FILE.read_text, "utf-8"
                    )
                    return HTMLResponse(inject_recipe_meta(index_html, meta[0], meta[1]))
            except Exception:  # noqa: BLE001 — never let enrichment break serving
                logger.exception("recipe meta injection failed for %s", path)

        return FileResponse(INDEX_FILE)
