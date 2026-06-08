"""
analysis_service.py — BIST30 XGBoost+LightGBM ensemble entegrasyonu
Flutter backend'in /analyze/{symbol} endpoint'i bu servisi kullanır.
Dönen JSON formatı değişmedi — Flutter tarafında güncelleme gerekmez.
"""
from __future__ import annotations

import pickle
import sys
from functools import lru_cache
from pathlib import Path

import numpy as np
import pandas as pd
import yfinance as yf

# check_stats.py'nin bulunduğu dizini Python path'e ekle
_PKG_DIR = Path(__file__).resolve().parent          # .../package/services/
_ROOT    = _PKG_DIR.parents[1]                       # .../bist-app-backend/
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from check_stats import add_derived_features, ProbBlend  # noqa: F401 — ProbBlend pickle için gerekli

# ── Sabitler ──────────────────────────────────────────────────────────────────
MODEL_DIR   = _ROOT / "saved_models"
MODEL_PATH  = MODEL_DIR / "model_bist30_multiclass_v2.pkl"
RAW_DATA    = _ROOT / "data" / "raw" / "bist_ohlcv_3y.csv"
CLASS_NAMES = ["SELL", "HOLD", "BUY"]
TR_LABELS   = {"BUY": "AL", "HOLD": "TUT", "SELL": "SAT"}
HORIZON_DAYS = 1


# ── Yardımcı fonksiyonlar ─────────────────────────────────────────────────────

def normalize_symbol(symbol: str) -> str:
    s = symbol.strip().upper()
    return s if s.endswith(".IS") else f"{s}.IS"


def fetch_history(symbol: str, period: str = "2y") -> pd.DataFrame:
    """Yahoo Finance'den OHLCV çek; hata durumunda CSV'ye düş."""
    ticker_symbol = normalize_symbol(symbol)

    for lookback in (period, "2y", "5y", "max"):
        try:
            raw = yf.download(
                ticker_symbol, period=lookback, interval="1d",
                auto_adjust=False, progress=False, threads=False,
            )
            if raw.empty:
                continue
            frame = raw.reset_index().copy()
            date_col = "Date" if "Date" in frame.columns else "Datetime"
            frame = frame.rename(columns={
                date_col:    "date",
                "Open":      "open",
                "High":      "high",
                "Low":       "low",
                "Close":     "close",
                "Adj Close": "adj_close",
                "Volume":    "volume",
            })
            # yfinance bazen MultiIndex döndürür — düzleştir
            frame.columns = [c[0] if isinstance(c, tuple) else c for c in frame.columns]
            frame["date"] = pd.to_datetime(frame["date"], errors="coerce")
            frame = frame.dropna(subset=["date", "close"]).sort_values("date").reset_index(drop=True)
            if not frame.empty:
                return frame
        except Exception:
            continue

    # CSV fallback
    if RAW_DATA.exists():
        try:
            raw = pd.read_csv(RAW_DATA)
            raw["date"] = pd.to_datetime(raw["date"], errors="coerce")
            rows = raw[raw["symbol"].astype(str) == ticker_symbol].copy()
            if not rows.empty:
                return rows.sort_values("date").reset_index(drop=True)
        except Exception:
            pass

    return pd.DataFrame()


@lru_cache(maxsize=1)
def _fetch_market_returns() -> dict:
    """XU100 ve USDTRY günlük getirilerini çek (cache'li)."""
    out = {"xu100_1d": 0.0, "xu100_5d": 0.0, "usdtry_1d": 0.0}
    try:
        xu = yf.download("XU100.IS", period="30d", interval="1d", auto_adjust=False,
                         progress=False, threads=False)["Close"].dropna()
        if len(xu) >= 6:
            out["xu100_1d"] = float((xu.iloc[-1] - xu.iloc[-2]) / xu.iloc[-2])
            out["xu100_5d"] = float((xu.iloc[-1] - xu.iloc[-6]) / xu.iloc[-6])
    except Exception:
        pass
    try:
        usd = yf.download("USDTRY=X", period="10d", interval="1d", auto_adjust=False,
                          progress=False, threads=False)["Close"].dropna()
        if len(usd) >= 2:
            out["usdtry_1d"] = float((usd.iloc[-1] - usd.iloc[-2]) / usd.iloc[-2])
    except Exception:
        pass
    return out


def _add_market_cols(df: pd.DataFrame) -> pd.DataFrame:
    """
    check_stats.add_derived_features bazı kolonları bekler.
    Eğer veri setinde yoksa hesapla veya doldur.
    """
    mkt = _fetch_market_returns()

    defaults = {
        "xu100_return_1d": mkt["xu100_1d"],
        "xu100_return_5d": mkt["xu100_5d"],
        "usdtry_return_1d": mkt["usdtry_1d"],
        "volatility_10d": 0.0,
        "volatility_20d": 0.0,
        "price_vs_sma50": 0.0,
        "price_vs_sma200": 0.0,
        "rsi14": 50.0,
        "macd_hist": 0.0,
        "return_1d": 0.0,
        "return_5d": 0.0,
        "return_10d": 0.0,
        "volume_ratio": 1.0,
        "sentiment_score": 0.5,
        "news_count": 0.0,
        "news_up_probability": 0.5,
    }
    # return_1d hesapla (varsa override etme)
    if "return_1d" not in df.columns or df["return_1d"].isna().all():
        df["return_1d"] = df["close"].pct_change(1)
    if "return_5d" not in df.columns or df["return_5d"].isna().all():
        df["return_5d"] = df["close"].pct_change(5)
    if "return_10d" not in df.columns or df["return_10d"].isna().all():
        df["return_10d"] = df["close"].pct_change(10)

    # Teknik indikatörler
    if "rsi14" not in df.columns or df["rsi14"].isna().all():
        delta = df["close"].diff()
        gain  = delta.clip(lower=0).rolling(14).mean()
        loss  = (-delta.clip(upper=0)).rolling(14).mean()
        rs    = gain / loss.replace(0, np.nan)
        df["rsi14"] = 100 - (100 / (1 + rs))

    if "volatility_20d" not in df.columns or df["volatility_20d"].isna().all():
        df["volatility_20d"] = df["return_1d"].rolling(20).std()
    if "volatility_10d" not in df.columns or df["volatility_10d"].isna().all():
        df["volatility_10d"] = df["return_1d"].rolling(10).std()

    if "macd_hist" not in df.columns or df["macd_hist"].isna().all():
        ema12 = df["close"].ewm(span=12, adjust=False).mean()
        ema26 = df["close"].ewm(span=26, adjust=False).mean()
        macd  = ema12 - ema26
        sig   = macd.ewm(span=9, adjust=False).mean()
        df["macd_hist"] = macd - sig

    if "price_vs_sma50" not in df.columns or df["price_vs_sma50"].isna().all():
        sma50 = df["close"].rolling(50).mean()
        df["price_vs_sma50"] = df["close"] / sma50.replace(0, np.nan) - 1

    if "price_vs_sma200" not in df.columns or df["price_vs_sma200"].isna().all():
        sma200 = df["close"].rolling(200).mean()
        df["price_vs_sma200"] = df["close"] / sma200.replace(0, np.nan) - 1

    if "volume_ratio" not in df.columns or df["volume_ratio"].isna().all():
        vol_sma20 = df["volume"].rolling(20).mean() if "volume" in df.columns else 1
        df["volume_ratio"] = (df["volume"] / vol_sma20.replace(0, np.nan)) if "volume" in df.columns else 1.0

    # Geri kalan default kolonlar
    for col, val in defaults.items():
        if col not in df.columns:
            df[col] = val

    return df


@lru_cache(maxsize=1)
def load_model_assets() -> tuple:
    """Model pickle'ını bir kez yükle, cache'te tut."""
    if not MODEL_PATH.exists():
        raise FileNotFoundError(f"Model bulunamadi: {MODEL_PATH}")
    with open(MODEL_PATH, "rb") as f:
        artifact = pickle.load(f)
    model           = artifact["model"]
    model_features  = artifact["model_features"]
    return model, model_features


# ── Yorum ve risk mantığı ─────────────────────────────────────────────────────

def build_reasons(latest: pd.Series, pred: str, buy_p: float, sell_p: float) -> list[str]:
    reasons: list[str] = []

    rsi = latest.get("rsi14", np.nan)
    if pd.notna(rsi):
        if rsi >= 60:
            reasons.append("RSI pozitif bölgede (güçlü momentum)")
        elif rsi <= 40:
            reasons.append("RSI zayıf bölgede (satış baskısı)")
        else:
            reasons.append("RSI nötr bölgede")

    sma_ratio = latest.get("price_vs_sma50", np.nan)
    if pd.notna(sma_ratio):
        reasons.append(
            "Fiyat 50 günlük ortalamanın üstünde" if sma_ratio > 0
            else "Fiyat 50 günlük ortalamanın altında"
        )

    macd = latest.get("macd_hist", np.nan)
    if pd.notna(macd):
        reasons.append("MACD momentumu pozitif" if macd > 0 else "MACD momentumu negatif")

    sent = latest.get("sentiment_score", 0.5)
    if pd.notna(sent):
        if sent > 0.65:
            reasons.append("Haber sentiment pozitif")
        elif sent < 0.40:
            reasons.append("Haber sentiment negatif")

    if pred == "BUY" and buy_p >= 0.45:
        reasons.append(f"Model AL sinyali üretiyor (%{buy_p*100:.0f} güven)")
    elif pred == "SELL" and sell_p >= 0.30:
        reasons.append(f"Model SAT sinyali üretiyor (%{sell_p*100:.0f} güven)")

    return reasons[:4] if reasons else ["Yeterli sinyal bulunamadı"]


def compute_risk_score(latest: pd.Series) -> float:
    vol   = latest.get("volatility_20d", np.nan)
    ret5d = latest.get("return_5d", np.nan)
    vol_c = 0.0 if pd.isna(vol)   else float(abs(vol) * 10)
    dd_c  = 0.0 if pd.isna(ret5d) else float(max(0.0, -ret5d) * 4)
    return round(max(0.0, min(1.0, vol_c + dd_c)), 4)


def compute_confidence(buy_p: float, hold_p: float, sell_p: float, risk: float) -> float:
    """En yüksek sınıf olasılığından risk düşülerek güven skoru üretilir."""
    max_p    = max(buy_p, hold_p, sell_p)
    base     = 0.5 + (max_p - 1/3) * 1.5   # 1/3 = random baseline
    adjusted = base - risk * 0.15
    return round(max(0.50, min(0.99, adjusted)), 4)


# ── Ana analiz fonksiyonu ─────────────────────────────────────────────────────

def analyze_symbol(symbol: str) -> dict:
    model, model_features = load_model_assets()

    history = fetch_history(symbol)
    if history.empty or len(history) < 60:
        raise ValueError(f"Yeterli veri bulunamadı: {symbol}")

    # Ticker kolonu ekle (add_derived_features için gerekli)
    history["ticker"] = normalize_symbol(symbol)

    # Eksik teknik kolonları hesapla
    history = _add_market_cols(history)

    # check_stats pipeline'ı çalıştır (sentiment shift, log return, vb.)
    history = add_derived_features(history)

    # Modelin beklediği kolonları doldur
    for col in model_features:
        if col not in history.columns:
            history[col] = 0.0

    last_row = history.dropna(subset=["close"]).iloc[[-1]]
    X = last_row[model_features].fillna(0)

    probs    = model.predict_proba(X)[0]          # [sell_p, hold_p, buy_p]
    pred_idx = int(np.argmax(probs))
    pred_en  = CLASS_NAMES[pred_idx]              # "BUY" / "HOLD" / "SELL"
    pred_tr  = TR_LABELS[pred_en]                 # "AL"  / "TUT"  / "SAT"

    sell_p, hold_p, buy_p = float(probs[0]), float(probs[1]), float(probs[2])

    latest     = last_row.iloc[0]
    risk_score = compute_risk_score(latest)
    confidence = compute_confidence(buy_p, hold_p, sell_p, risk_score)
    reasons    = build_reasons(latest, pred_en, buy_p, sell_p)

    current_price = float(latest["close"])
    prev_rows     = history.dropna(subset=["close"])
    if len(prev_rows) >= 2:
        prev_close     = float(prev_rows.iloc[-2]["close"])
        change_percent = round(((current_price - prev_close) / prev_close) * 100, 4) if prev_close else 0.0
    else:
        change_percent = 0.0

    # up_probability: Flutter'ın beklediği alan — BUY olasılığını kullan
    return {
        "symbol":          normalize_symbol(symbol),
        "recommendation":  pred_tr,           # "AL" / "TUT" / "SAT"
        "up_probability":  round(buy_p, 4),   # BUY olasılığı (0-1)
        "sell_probability": round(sell_p, 4),
        "hold_probability": round(hold_p, 4),
        "risk_score":      risk_score,
        "confidence":      confidence,
        "horizon_days":    HORIZON_DAYS,
        "reasons":         reasons,
        "current_price":   round(current_price, 4),
        "change_percent":  round(change_percent, 4),
    }
