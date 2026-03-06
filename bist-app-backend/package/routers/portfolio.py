from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..deps import get_db, get_current_user
from .. import models, schemas

router = APIRouter(prefix="/portfolio", tags=["portfolio"])


@router.post("/transactions", response_model=schemas.TransactionOut)
def add_transaction(
    payload: schemas.TransactionCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    tx = models.Transaction(
        user_id=user.id,
        symbol=payload.symbol.upper(),
        side=payload.side,
        qty=payload.qty,
        price=payload.price,
    )
    db.add(tx)
    db.commit()
    db.refresh(tx)
    return tx


@router.get("/transactions", response_model=list[schemas.TransactionOut])
def list_transactions(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    return (
        db.query(models.Transaction)
        .filter(models.Transaction.user_id == user.id)
        .order_by(models.Transaction.created_at.desc())
        .all()
    )


@router.get("/summary", response_model=schemas.PortfolioSummaryResponse)
def get_portfolio_summary(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    transactions = (
        db.query(models.Transaction)
        .filter(models.Transaction.user_id == user.id)
        .order_by(models.Transaction.created_at.asc())
        .all()
    )

    portfolio_map = {}

    for tx in transactions:
        symbol = tx.symbol.upper()

        if symbol not in portfolio_map:
            portfolio_map[symbol] = {
                "qty": 0.0,
                "avg_cost": 0.0,
            }

        current_qty = portfolio_map[symbol]["qty"]
        current_avg = portfolio_map[symbol]["avg_cost"]

        if tx.side == "BUY":
            new_qty = current_qty + tx.qty
            new_avg = ((current_qty * current_avg) + (tx.qty * tx.price)) / new_qty

            portfolio_map[symbol]["qty"] = new_qty
            portfolio_map[symbol]["avg_cost"] = new_avg

        elif tx.side == "SELL":
            new_qty = current_qty - tx.qty
            if new_qty < 0:
                new_qty = 0

            portfolio_map[symbol]["qty"] = new_qty

            if new_qty == 0:
                portfolio_map[symbol]["avg_cost"] = 0.0

    positions = []

    for symbol, data in portfolio_map.items():
        qty = round(data["qty"], 4)
        avg_cost = round(data["avg_cost"], 4)
        total_cost = round(qty * avg_cost, 4)

        if qty > 0:
            positions.append(
                {
                    "symbol": symbol,
                    "qty": qty,
                    "avg_cost": avg_cost,
                    "total_cost": total_cost,
                }
            )

    return {"positions": positions}