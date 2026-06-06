from pydantic import BaseModel, EmailStr, Field
from datetime import datetime
from typing import Literal, Optional


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6)
    first_name: str = Field(min_length=1)
    last_name: str = Field(min_length=1)


class UserOut(BaseModel):
    email: EmailStr
    first_name: Optional[str] = None
    last_name: Optional[str] = None

    class Config:
        from_attributes = True


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


class AlarmCreate(BaseModel):
    symbol: str = Field(min_length=1)
    lower_bound: Optional[float] = None
    upper_bound: Optional[float] = None


class AlarmOut(BaseModel):
    id: int
    symbol: str
    lower_bound: Optional[float] = None
    upper_bound: Optional[float] = None
    is_triggered: bool
    created_at: datetime
    triggered_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class AnalyzeResponse(BaseModel):
    symbol: str
    recommendation: str
    up_probability: float
    risk_score: float
    confidence: float
    horizon_days: int
    reasons: list[str]
    current_price: float
    change_percent: float