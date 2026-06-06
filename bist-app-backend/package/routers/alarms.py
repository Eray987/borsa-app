from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime

from ..deps import get_db, get_current_user
from .. import models, schemas

router = APIRouter(prefix="/alarms", tags=["alarms"])


@router.post("/", response_model=schemas.AlarmOut)
def create_alarm(
    payload: schemas.AlarmCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    if payload.lower_bound is None and payload.upper_bound is None:
        raise HTTPException(status_code=400, detail="En az bir sınır (alt veya üst) girilmelidir.")

    alarm = models.Alarm(
        user_id=user.id,
        symbol=payload.symbol.upper(),
        lower_bound=payload.lower_bound,
        upper_bound=payload.upper_bound,
    )
    db.add(alarm)
    db.commit()
    db.refresh(alarm)
    return alarm


@router.get("/", response_model=list[schemas.AlarmOut])
def list_alarms(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    return (
        db.query(models.Alarm)
        .filter(models.Alarm.user_id == user.id)
        .order_by(models.Alarm.created_at.desc())
        .all()
    )


@router.get("/{symbol}", response_model=list[schemas.AlarmOut])
def list_alarms_by_symbol(
    symbol: str,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    return (
        db.query(models.Alarm)
        .filter(
            models.Alarm.user_id == user.id,
            models.Alarm.symbol == symbol.upper(),
        )
        .order_by(models.Alarm.created_at.desc())
        .all()
    )


@router.delete("/{alarm_id}")
def delete_alarm(
    alarm_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    alarm = db.query(models.Alarm).filter(
        models.Alarm.id == alarm_id,
        models.Alarm.user_id == user.id,
    ).first()
    if not alarm:
        raise HTTPException(status_code=404, detail="Alarm bulunamadı.")
    db.delete(alarm)
    db.commit()
    return {"ok": True}
