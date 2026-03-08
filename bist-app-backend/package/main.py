from fastapi import FastAPI

from .db import Base, engine
from . import models
from .routers.auth import router as auth_router
from .routers.portfolio import router as portfolio_router
from .routers.market import router as market_router
from .routers.favorites import router as favorites_router
from .routers.news import router as news_router

Base.metadata.create_all(bind=engine)

app = FastAPI(title="BIST Mobile Backend")

app.include_router(auth_router)
app.include_router(portfolio_router)
app.include_router(market_router)
app.include_router(favorites_router)
app.include_router(news_router)

@app.get("/")
def health():
    return {"ok": True}
