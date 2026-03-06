from pydantic import BaseModel, EmailStr, Field
from datetime import datetime
from typing import Literal


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class TransactionCreate(BaseModel):
    symbol: str = Field(min_length=1)
    side: Literal["BUY", "SELL"]
    qty: float = Field(gt=0)
    price: float = Field(gt=0)


class TransactionOut(BaseModel):
    id: int
    symbol: str
    side: str
    qty: float
    price: float
    created_at: datetime

    class Config:
        from_attributes = True


class PositionSummary(BaseModel):
    symbol: str
    qty: float
    avg_cost: float
    total_cost: float


class PortfolioSummaryResponse(BaseModel):
    positions: list[PositionSummary]