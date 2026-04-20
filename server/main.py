from __future__ import annotations

from fastapi import FastAPI

from routers import grocery, recipes

app = FastAPI(title="Recipe App API", version="1.0.0")

app.include_router(recipes.router)
app.include_router(grocery.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
