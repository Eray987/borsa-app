from fastapi import APIRouter, HTTPException
from concurrent.futures import ThreadPoolExecutor
from ..services.analysis_service import load_model_assets, _add_market_cols, CLASS_NAMES, TR_LABELS, compute_risk_score, compute_confidence
from ..routers.market import _get_yahoo_session
from ..check_stats import add_derived_features
import numpy as np
import pandas as pd
import time

router = APIRouter(prefix="/signals", tags=["signals"])

# CSV eğitim verisiyle birebir aynı semboller (ticker_code sırası korunur)
BIST30 = [
    "AKBNK","AKGRT","ARCLK","ASELS","BERA","BIMAS","CCOLA","EKGYO",
    "ENKAI","EREGL","FROTO","GARAN","HALKB","ISCTR","KCHOL","KLSER",
    "MAVI","OYAKC","PETKM","PGSUS","SAHOL","SISE","TAVHL","TCELL",
    "THYAO","TOASO","TUPRS","ULKER","VAKBN","VESTL",
]

def _fetch_one(sym: str) -> tuple:
    """Yahoo Finance cookie session ile OHLCV çek."""
    ticker = f"{sym}.IS"
    try:
        session = _get_yahoo_session()
        headers = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"}
        r = session.get(
            f"https://query1.finance.yahoo.com/v8/finance/chart/{ticker}?interval=1d&range=2y",
            headers=headers, timeout=10,
        )
        if r.status_code != 200:
            raise ValueError(f"HTTP {r.status_code}")
        data = r.json()
        result = data["chart"]["result"][0]
        timestamps = result.get("timestamp", [])
        quote = result["indicators"]["quote"][0]
        closes  = quote.get("close", [])
        opens   = quote.get("open", [])
        highs   = quote.get("high", [])
        lows    = quote.get("low", [])
        volumes = quote.get("volume", [])

        from datetime import datetime
        rows = []
        for i, ts in enumerate(timestamps):
            c = closes[i] if i < len(closes) else None
            if c is None:
                continue
            rows.append({
                "date":   pd.to_datetime(datetime.fromtimestamp(ts)),
                "open":   opens[i]   if i < len(opens)   else c,
                "high":   highs[i]   if i < len(highs)   else c,
                "low":    lows[i]    if i < len(lows)     else c,
                "close":  c,
                "volume": volumes[i] if i < len(volumes)  else 0,
            })
        df = pd.DataFrame(rows).sort_values("date").reset_index(drop=True)
        return sym, df
    except Exception as e:
        return sym, e


@router.get("/all")
def get_all_signals():
    import pandas as pd
    model, model_features = load_model_assets()

    # 1) Tüm hisselerin verisini paralel çek
    frames: dict[str, object] = {}
    with ThreadPoolExecutor(max_workers=8) as executor:
        for sym, result in executor.map(lambda s: _fetch_one(s), BIST30):
            frames[sym] = result

    # 2) Geçerli frame'leri birleştir — ticker_code eğitimle aynı sırayla üretilsin
    parts = []
    for sym in BIST30:
        df = frames.get(sym)
        if isinstance(df, pd.DataFrame) and not df.empty and len(df) >= 60:
            df = df.copy()
            df["ticker"] = f"{sym}.IS"
            df = _add_market_cols(df)
            parts.append(df)

    results = []
    if not parts:
        return {"signals": [], "count": 0}

    # 3) Tek seferde birleştir → add_derived_features → ticker_code tutarlı
    combined = pd.concat(parts, ignore_index=True)
    combined = add_derived_features(combined)

    # 4) Her hisse için son satırı al, tahmin yap
    for sym in BIST30:
        ticker = f"{sym}.IS"
        try:
            sub = combined[combined["ticker"] == ticker].dropna(subset=["close"])
            if sub.empty:
                raise ValueError("Veri yok")

            for col in model_features:
                if col not in sub.columns:
                    sub = sub.copy()
                    sub[col] = 0.0

            last_row = sub.iloc[[-1]]
            X = last_row[model_features].fillna(0)
            probs = model.predict_proba(X)[0]
            pred_idx = int(np.argmax(probs))
            pred_tr = TR_LABELS[CLASS_NAMES[pred_idx]]

            sell_p, hold_p, buy_p = float(probs[0]), float(probs[1]), float(probs[2])
            latest = last_row.iloc[0]
            risk = compute_risk_score(latest)
            conf = compute_confidence(buy_p, hold_p, sell_p, risk)

            current_price = float(latest["close"])
            prev = float(sub.iloc[-2]["close"]) if len(sub) >= 2 else current_price
            change_pct = round(((current_price - prev) / prev) * 100, 2) if prev else 0.0

            results.append({
                "symbol": sym,
                "recommendation": pred_tr,
                "buy_probability": round(buy_p, 4),
                "hold_probability": round(hold_p, 4),
                "sell_probability": round(sell_p, 4),
                "confidence": round(conf, 4),
                "risk_score": round(risk, 4),
                "current_price": round(current_price, 2),
                "change_percent": change_pct,
            })
        except Exception as e:
            results.append({
                "symbol": sym, "recommendation": "?",
                "buy_probability": 0.0, "hold_probability": 0.0,
                "sell_probability": 0.0, "confidence": 0.0,
                "risk_score": 0.0, "current_price": 0.0,
                "change_percent": 0.0, "error": str(e),
            })

    results.sort(key=lambda x: x["buy_probability"], reverse=True)
    return {"signals": results, "count": len(results)}