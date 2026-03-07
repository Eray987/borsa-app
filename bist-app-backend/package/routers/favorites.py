from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from ..deps import get_db, get_current_user
from .. import models, schemas

router = APIRouter(prefix="/favorites", tags=["favorites"])

@router.post("/{symbol}")
def add_favorite(
    symbol: str,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user)
):
    existing = db.query(models.Favorite).filter(
        models.Favorite.user_id == user.id,
        models.Favorite.symbol == symbol.upper()
    ).first()
    
    if existing:
        return {"message": "Zaten favorilerde var"}
    
    favorite = models.Favorite(
        user_id=user.id,
        symbol=symbol.upper()
    )
    db.add(favorite)
    db.commit()
    return {"message": "Favoriye eklendi"}


@router.get("/")
def get_favorites(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user)
):
    favorites = db.query(models.Favorite).filter(
        models.Favorite.user_id == user.id
    ).all()
    
    return [{"id": f.id, "symbol": f.symbol, "added_at": f.added_at} for f in favorites]


@router.delete("/{symbol}")
def remove_favorite(
    symbol: str,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user)
):
    favorite = db.query(models.Favorite).filter(
        models.Favorite.user_id == user.id,
        models.Favorite.symbol == symbol.upper()
    ).first()
    
    if not favorite:
        raise HTTPException(status_code=404, detail="Favori bulunamadı")
    
    db.delete(favorite)
    db.commit()
    return {"message": "Favorilerden çıkarıldı"}
