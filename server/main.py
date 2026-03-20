from fastapi import FastAPI
from database import Base, engine
from routers import recipes, grocery

Base.metadata.create_all(bind=engine)

app = FastAPI(title="Recipe App API", version="1.0.0")

app.include_router(recipes.router)
app.include_router(grocery.router)


@app.get("/health")
def health():
    return {"status": "ok"}
