from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

import joblib
import pandas as pd
import yfinance as yf


MODEL_DIR = Path(__file__).resolve().parents[2] / "saved_models"
MODEL_PATH = MODEL_DIR / "bist_up_probability_model.joblib"
FEATURE_COLUMNS_PATH = MODEL_DIR / "bist_up_probability_feature_columns.json"
HORIZON_DAYS = 5
RAW_DATA_PATH = Path(__file__).resolve().parents[2] / "data" / "raw" / "bist_ohlcv_3y.csv"


def normalize_symbol(symbol: str) -> str:
    cleaned = symbol.strip().upper()
    if cleaned.endswith(".IS"):
        return cleaned
    return f"{cleaned}.IS"


def compute_rsi(close: pd.Series, window: int = 14) -> pd.Series:
    delta = close.diff()
    gain = delta.clip(lower=0).rolling(window=window).mean()
    loss = (-delta.clip(upper=0)).rolling(window=window).mean()
    rs = gain / loss.replace(0, pd.NA)
    return 100 - (100 / (1 + rs))


def compute_ema_ratio(close: pd.Series, window: int) -> pd.Series:
    ema = close.ewm(span=window, adjust=False).mean()
    return close / ema.replace(0, pd.NA) - 1


def compute_sma_ratio(close: pd.Series, window: int) -> pd.Series:
    sma = close.rolling(window=window).mean()
    return close / sma.replace(0, pd.NA) - 1


def compute_stochastic(high: pd.Series, low: pd.Series, close: pd.Series, window: int = 14, smooth_window: int = 3) -> tuple[pd.Series, pd.Series]:
    lowest_low = low.rolling(window=window).min()
    highest_high = high.rolling(window=window).max()
    k_percent = 100 * ((close - lowest_low) / (highest_high - lowest_low)).fillna(50)
    d_percent = k_percent.rolling(window=smooth_window).mean()
    return k_percent, d_percent


def fetch_history(symbol: str, period: str = "1y", interval: str = "1d") -> pd.DataFrame:
    ticker_symbol = normalize_symbol(symbol)
    lookback_periods = [period, "2y", "5y", "max"]

    for lookback in lookback_periods:
        try:
            history = yf.download(
                ticker_symbol,
                period=lookback,
                interval=interval,
                auto_adjust=False,
                progress=False,
                threads=False,
            )
            if history.empty:
                continue

            frame = history.reset_index().copy()
            date_column = "Date" if "Date" in frame.columns else "Datetime"
            frame = frame.rename(
                columns={
                    date_column: "date",
                    "Open": "open",
                    "High": "high",
                    "Low": "low",
                    "Close": "close",
                    "Adj Close": "adj_close",
                    "Volume": "volume",
                }
            )

            frame["date"] = pd.to_datetime(frame["date"], errors="coerce")
            frame = frame.dropna(subset=["date", "close", "volume"])
            frame = frame.sort_values("date").reset_index(drop=True)
            if not frame.empty:
                return frame
        except Exception:
            continue

    if RAW_DATA_PATH.exists():
        try:
            raw = pd.read_csv(RAW_DATA_PATH)
            raw["date"] = pd.to_datetime(raw["date"], errors="coerce")
            symbol_rows = raw[raw["symbol"].astype(str) == ticker_symbol].copy()
            if not symbol_rows.empty:
                symbol_rows = symbol_rows.sort_values("date").reset_index(drop=True)
                return symbol_rows
        except Exception:
            pass

    return pd.DataFrame()


def build_feature_frame(history: pd.DataFrame) -> pd.DataFrame:
    frame = history.copy()

    frame["return_1d"] = frame["close"].pct_change(1)
    frame["return_3d"] = frame["close"].pct_change(3)
    frame["return_5d"] = frame["close"].pct_change(5)

    frame["sma_5_ratio"] = compute_sma_ratio(frame["close"], 5)
    frame["sma_10_ratio"] = compute_sma_ratio(frame["close"], 10)
    frame["sma_20_ratio"] = compute_sma_ratio(frame["close"], 20)

    frame["ema_12_ratio"] = compute_ema_ratio(frame["close"], 12)
    frame["ema_26_ratio"] = compute_ema_ratio(frame["close"], 26)

    ema_12 = frame["close"].ewm(span=12, adjust=False).mean()
    ema_26 = frame["close"].ewm(span=26, adjust=False).mean()
    frame["macd"] = ema_12 - ema_26
    frame["macd_signal"] = frame["macd"].ewm(span=9, adjust=False).mean()
    frame["macd_histogram"] = frame["macd"] - frame["macd_signal"]
    frame["macd_signal_diff"] = frame["macd"] - frame["macd_signal"]
    frame["macd_positive"] = (frame["macd"] > frame["macd_signal"]).astype(int)

    frame["stochastic_k"], frame["stochastic_d"] = compute_stochastic(frame["high"], frame["low"], frame["close"])
    frame["stochastic_diff"] = frame["stochastic_k"] - frame["stochastic_d"]
    frame["stochastic_overbought"] = (frame["stochastic_k"] > 80).astype(int)
    frame["stochastic_oversold"] = (frame["stochastic_k"] < 20).astype(int)

    frame["rsi_14"] = compute_rsi(frame["close"], 14)
    frame["volatility_5d"] = frame["return_1d"].rolling(window=5).std()
    frame["volatility_10d"] = frame["return_1d"].rolling(window=10).std()

    frame["volume_change_1d"] = frame["volume"].pct_change(1)
    frame["volume_change_5d"] = frame["volume"].pct_change(5)
    volume_sma_20 = frame["volume"].rolling(window=20).mean()
    frame["volume_sma_20_ratio"] = frame["volume"] / volume_sma_20.replace(0, pd.NA) - 1

    frame = frame.replace([float("inf"), float("-inf")], pd.NA)
    return frame


@lru_cache(maxsize=1)
def load_model_assets() -> tuple[object, list[str]]:
    if not MODEL_PATH.exists():
        raise FileNotFoundError(f"Model file not found: {MODEL_PATH}")
    if not FEATURE_COLUMNS_PATH.exists():
        raise FileNotFoundError(f"Feature columns file not found: {FEATURE_COLUMNS_PATH}")

    model = joblib.load(MODEL_PATH)
    feature_columns = json.loads(FEATURE_COLUMNS_PATH.read_text(encoding="utf-8"))
    return model, feature_columns


def pick_recommendation(up_probability: float) -> str:
    if up_probability >= 0.65:
        return "AL"
    if up_probability >= 0.45:
        return "TUT"
    return "SAT"


def build_reasons(latest_row: pd.Series) -> list[str]:
    reasons: list[str] = []

    rsi = latest_row.get("rsi_14")
    if pd.notna(rsi):
        if rsi >= 55:
            reasons.append("RSI pozitif bölgede")
        elif rsi <= 45:
            reasons.append("RSI zayıf bölgede")

    sma_20_ratio = latest_row.get("sma_20_ratio")
    if pd.notna(sma_20_ratio):
        if sma_20_ratio > 0:
            reasons.append("Fiyat 20 günlük ortalamanın üstünde")
        else:
            reasons.append("Fiyat 20 günlük ortalamanın altında")

    macd_signal_diff = latest_row.get("macd_signal_diff")
    if pd.notna(macd_signal_diff):
        if macd_signal_diff > 0:
            reasons.append("Momentum pozitif")
        else:
            reasons.append("Momentum zayıf")

    volume_change_5d = latest_row.get("volume_change_5d")
    if pd.notna(volume_change_5d) and volume_change_5d > 0:
        reasons.append("Hacim artışı var")

    if not reasons:
        reasons.append("Son fiyat verisi dengeli görünüyor")

    return reasons[:4]


def compute_risk_score(latest_row: pd.Series) -> float:
    volatility = latest_row.get("volatility_10d")
    return_5d = latest_row.get("return_5d")

    volatility_component = 0.0 if pd.isna(volatility) else float(abs(volatility) * 10)
    drawdown_component = 0.0 if pd.isna(return_5d) else float(max(0.0, -return_5d) * 4)

    risk_score = volatility_component + drawdown_component
    return round(max(0.0, min(1.0, risk_score)), 4)


def compute_confidence(up_probability: float, risk_score: float) -> float:
    base = 0.5 + abs(up_probability - 0.5)
    adjusted = base - (risk_score * 0.15)
    return round(max(0.5, min(0.99, adjusted)), 4)


def analyze_symbol(symbol: str) -> dict:
    model, feature_columns = load_model_assets()

    history = fetch_history(symbol)
    if history.empty or len(history) < 30:
        raise ValueError(f"Yeterli veri bulunamadı: {symbol}")

    feature_frame = build_feature_frame(history)
    feature_frame = feature_frame.dropna(subset=feature_columns + ["close"])
    if feature_frame.empty:
        raise ValueError(f"Feature üretilemedi: {symbol}")

    latest_row = feature_frame.iloc[-1]
    x_input = feature_frame.iloc[[-1]][feature_columns]

    up_probability = float(model.predict_proba(x_input)[:, 1][0])
    recommendation = pick_recommendation(up_probability)
    risk_score = compute_risk_score(latest_row)
    confidence = compute_confidence(up_probability, risk_score)
    reasons = build_reasons(latest_row)

    current_price = float(latest_row["close"])
    if len(feature_frame) >= 2:
        prev_close = float(feature_frame.iloc[-2]["close"])
        change_percent = round(((current_price - prev_close) / prev_close) * 100, 4) if prev_close else 0.0
    else:
        change_percent = 0.0

    return {
        "symbol": normalize_symbol(symbol),
        "recommendation": recommendation,
        "up_probability": round(up_probability, 4),
        "risk_score": risk_score,
        "confidence": confidence,
        "horizon_days": HORIZON_DAYS,
        "reasons": reasons,
        "current_price": round(current_price, 4),
        "change_percent": round(change_percent, 4),
    }