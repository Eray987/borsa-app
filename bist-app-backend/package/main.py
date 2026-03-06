from fastapi import FastAPI

from .db import Base, engine
from . import models
from .routers.auth import router as auth_router
from .routers.portfolio import router as portfolio_router

Base.metadata.create_all(bind=engine)

app = FastAPI(title="BIST Mobile Backend (MVP)")

app.include_router(auth_router)
app.include_router(portfolio_router)

@app.get("/")
def health():
    return {"ok": True}