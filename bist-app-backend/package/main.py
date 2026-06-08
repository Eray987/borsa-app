from contextlib import asynccontextmanager
import asyncio
from fastapi import FastAPI

from .db import Base, engine
from . import models
from .routers.auth import router as auth_router
from .routers.portfolio import router as portfolio_router
from .routers.market import router as market_router
from .routers.favorites import router as favorites_router
from .routers.news import router as news_router
from .routers.analyze import router as analyze_router
from .routers.alarms import router as alarms_router
from .routers.signals import router as signals_router
from .alarm_scheduler import alarm_scheduler_loop

Base.metadata.create_all(bind=engine)


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(alarm_scheduler_loop())
    yield
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass


app = FastAPI(title="BIST Mobile Backend", lifespan=lifespan)

app.include_router(auth_router)
app.include_router(portfolio_router)
app.include_router(market_router)
app.include_router(favorites_router)
app.include_router(news_router)
app.include_router(analyze_router)
app.include_router(alarms_router)
app.include_router(signals_router)


@app.get("/")
def health():
    return {"ok": True}
