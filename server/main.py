from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import grocery, recipes

app = FastAPI(title="Recipe App API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "https://recipes.ouryearofwander.com",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(recipes.router)
app.include_router(grocery.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
