from fastapi import APIRouter, HTTPException

from ..schemas import AnalyzeResponse
from ..services.analysis_service import analyze_symbol


router = APIRouter(prefix="/analyze", tags=["analyze"])


@router.get("/{symbol}", response_model=AnalyzeResponse)
def analyze_stock(symbol: str):
    try:
        return analyze_symbol(symbol)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Analiz sırasında hata oluştu: {exc}")