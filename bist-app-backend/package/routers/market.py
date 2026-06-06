from fastapi import APIRouter, HTTPException
import requests
import pandas as pd
from pathlib import Path
from functools import lru_cache
import time

router = APIRouter(prefix="/market", tags=["market"])

# Yahoo Finance session (cookie tabanlı erişim)
_yahoo_session: requests.Session | None = None
_yahoo_session_time: float = 0
SESSION_TTL = 3600  # 1 saat


def _get_yahoo_session() -> requests.Session:
    global _yahoo_session, _yahoo_session_time
    if _yahoo_session is None or (time.time() - _yahoo_session_time) > SESSION_TTL:
        session = requests.Session()
        session.get(
            "https://finance.yahoo.com",
            headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"},
            timeout=10,
        )
        _yahoo_session = session
        _yahoo_session_time = time.time()
    return _yahoo_session

BIST30_SYMBOLS = [
    "THYAO", "ASELS", "GARAN", "AKBNK", "SISE",
    "EREGL", "KCHOL", "SASA", "HEKTS", "PETKM",
    "FROTO", "ISCTR", "AYGAZ", "MGROS", "SOKM",
    "TCELL", "TUPRS", "YKBNK", "TTKOM", "ULKER",
    "BIMAS", "HALKB", "VAKBN", "ENKAI", "ANSGR",
    "SAHOL", "KOZAL", "PGSUS", "TOASO", "ARCLK"
]

BIST30_NAMES = {
    "THYAO": "Türk Hava Yolları",
    "ASELS": "Aselsan",
    "GARAN": "Garanti BBVA",
    "AKBNK": "Akbank",
    "SISE":  "Şişecam",
    "EREGL": "Ereğli Demir Çelik",
    "KCHOL": "Koç Holding",
    "SASA":  "Sasa Polyester",
    "HEKTS": "Hektaş",
    "PETKM": "Petkim",
    "FROTO": "Ford Otosan",
    "ISCTR": "İş Bankası",
    "AYGAZ": "Aygaz",
    "MGROS": "Migros",
    "SOKM":  "Şok Market",
    "TCELL": "Turkcell",
    "TUPRS": "Tüpraş",
    "YKBNK": "Yapı Kredi",
    "TTKOM": "Türk Telekom",
    "ULKER": "Ülker Bisküvi",
    "BIMAS": "BİM Mağazalar",
    "HALKB": "Halkbank",
    "VAKBN": "Vakıfbank",
    "ENKAI": "Enka İnşaat",
    "ANSGR": "Anadolu Sigorta",
    "SAHOL": "Sabancı Holding",
    "KOZAL": "Koza Altın",
    "PGSUS": "Pegasus",
    "TOASO": "Tofaş Otomobil",
    "ARCLK": "Arçelik",
}

RAW_DATA_PATH = Path(__file__).resolve().parents[2] / "data" / "raw" / "bist_ohlcv_3y.csv"


def _parse_price(price_str: str) -> float:
    """Türkçe formatlanmış fiyatı (virgülü) float'a çevir: '9,28' → 9.28"""
    if not price_str:
        return 0.0
    return float(price_str.replace(",", ".").strip())


def _normalize_symbol(symbol: str) -> str:
    cleaned = symbol.strip().upper()
    if not cleaned.endswith(".IS"):
        cleaned = f"{cleaned}.IS"
    return cleaned


def _extract_series(history: pd.DataFrame, symbol: str) -> pd.Series:
    # yfinance returns MultiIndex for multi-ticker downloads and a flat frame for single ticker.
    if history.empty:
        return pd.Series(dtype=float)

    if isinstance(history.columns, pd.MultiIndex):
        if ("Close", symbol) in history.columns:
            return history[("Close", symbol)].dropna()
        if (symbol, "Close") in history.columns:
            return history[(symbol, "Close")].dropna()
        return pd.Series(dtype=float)

    if "Close" in history.columns:
        return history["Close"].dropna()

    return pd.Series(dtype=float)


@lru_cache(maxsize=1)
def _load_local_dataset() -> pd.DataFrame:
    if not RAW_DATA_PATH.exists():
        return pd.DataFrame()

    frame = pd.read_csv(RAW_DATA_PATH)
    if frame.empty or "symbol" not in frame.columns or "date" not in frame.columns or "close" not in frame.columns:
        return pd.DataFrame()

    frame["symbol"] = frame["symbol"].astype(str).str.upper().str.strip()
    frame["date"] = pd.to_datetime(frame["date"], errors="coerce")
    frame = frame.dropna(subset=["date", "close"]).sort_values(["symbol", "date"]).reset_index(drop=True)
    return frame


def _local_close_series(symbol: str) -> pd.Series:
    local = _load_local_dataset()
    if local.empty:
        return pd.Series(dtype=float)

    symbol_rows = local[local["symbol"] == symbol]
    if symbol_rows.empty:
        return pd.Series(dtype=float)

    return pd.Series(symbol_rows["close"].values)

@router.get("/bist30")
def get_bist30():
    """Yahoo Finance'den BIST30 güncel fiyatlarını çek, hata olursa CSV'ye düş"""
    session = _get_yahoo_session()
    stocks_data = []
    headers = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"}

    for symbol in BIST30_SYMBOLS:
        yahoo_symbol = f"{symbol}.IS"
        try:
            r = session.get(
                f"https://query1.finance.yahoo.com/v8/finance/chart/{yahoo_symbol}?interval=1d&range=2d",
                headers=headers,
                timeout=8,
            )
            if r.status_code != 200:
                raise ValueError(f"HTTP {r.status_code}")

            data = r.json()
            result = data["chart"]["result"][0]
            meta = result["meta"]
            current_price = float(meta.get("regularMarketPrice") or 0)
            prev_price = float(meta.get("chartPreviousClose") or current_price)

            if current_price <= 0:
                raise ValueError("Fiyat sıfır")

            change_percent = ((current_price - prev_price) / prev_price * 100) if prev_price else 0.0
            stocks_data.append({
                "symbol": symbol,
                "name": BIST30_NAMES.get(symbol, symbol),
                "price": round(current_price, 4),
                "change_percent": round(change_percent, 4),
            })
        except Exception as e:
            print(f"Yahoo Finance hatası {symbol}: {e} — CSV'ye düşülüyor")
            # Fallback: yerel CSV
            local = _load_local_dataset()
            rows = local[local["symbol"] == yahoo_symbol]
            if not rows.empty:
                rows = rows.sort_values("date")
                cp = float(rows.iloc[-1]["close"])
                pp = float(rows.iloc[-2]["close"]) if len(rows) >= 2 else cp
                ch = ((cp - pp) / pp * 100) if pp else 0.0
                stocks_data.append({
                    "symbol": symbol,
                    "name": BIST30_NAMES.get(symbol, symbol),
                    "price": round(cp, 4),
                    "change_percent": round(ch, 4),
                })

    if not stocks_data:
        raise HTTPException(status_code=404, detail="BIST30 verisi bulunamadı")

    return stocks_data


@router.get("/stock/{symbol}")
def get_stock_detail(symbol: str, period: str = "1mo"):
    """Yahoo Finance'den güncel fiyat + chart verisi çek, CSV ile destekle"""
    yahoo_symbol = _normalize_symbol(symbol)

    # Period → Yahoo Finance range/interval eşleşmesi
    period_map = {
        "1d":  ("1d",  "5m"),
        "1w":  ("5d",  "1h"),
        "1mo": ("1mo", "1d"),
        "3mo": ("3mo", "1d"),
        "6mo": ("6mo", "1d"),
        "1y":  ("1y",  "1d"),
    }
    yf_range, yf_interval = period_map.get(period, ("1mo", "1d"))

    current_price = None
    prev_price = None
    chart_data = []

    # Yahoo Finance'den çek
    try:
        session = _get_yahoo_session()
        r = session.get(
            f"https://query1.finance.yahoo.com/v8/finance/chart/{yahoo_symbol}"
            f"?interval={yf_interval}&range={yf_range}",
            headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"},
            timeout=10,
        )
        if r.status_code == 200:
            data = r.json()
            result = data["chart"]["result"][0]
            meta = result["meta"]
            current_price = float(meta.get("regularMarketPrice") or 0) or None
            prev_price = float(meta.get("chartPreviousClose") or 0) or None

            timestamps = result.get("timestamp", [])
            closes = result["indicators"]["quote"][0].get("close", [])

            from datetime import datetime
            for ts, c in zip(timestamps, closes):
                if c is None:
                    continue
                date_str = datetime.fromtimestamp(ts).strftime(
                    "%Y-%m-%d %H:%M" if yf_interval in ("5m", "1h") else "%Y-%m-%d"
                )
                chart_data.append({"date": date_str, "close": round(float(c), 4)})
    except Exception as e:
        print(f"Yahoo Finance chart hatası {symbol}: {e}")

    # Fiyat veya chart gelmezse CSV'ye düş
    if not chart_data or current_price is None:
        try:
            local = _load_local_dataset()
            symbol_rows = local[local["symbol"] == yahoo_symbol].copy()
            if not symbol_rows.empty:
                period_days_map = {"1d": 1, "1w": 7, "1mo": 30, "3mo": 90, "6mo": 180, "1y": 365}
                days = period_days_map.get(period, 30)
                symbol_rows = symbol_rows.sort_values("date").tail(days)
                if not chart_data:
                    chart_data = [
                        {"date": row["date"].strftime("%Y-%m-%d"), "close": float(row["close"])}
                        for _, row in symbol_rows.iterrows()
                    ]
                closes_csv = symbol_rows["close"].astype(float).reset_index(drop=True)
                if current_price is None:
                    current_price = float(closes_csv.iloc[-1])
                if prev_price is None:
                    prev_price = float(closes_csv.iloc[-2]) if len(closes_csv) >= 2 else current_price
        except Exception as e:
            print(f"CSV fallback hatası {symbol}: {e}")

    if not chart_data or current_price is None:
        raise HTTPException(status_code=404, detail=f"Hisse verisi bulunamadı: {symbol}")

    prev_price = prev_price or current_price
    change = ((current_price - prev_price) / prev_price * 100) if prev_price else 0.0

    return {
        "symbol": symbol,
        "name": yahoo_symbol,
        "price": round(current_price, 4),
        "change_percent": round(change, 4),
        "chart": chart_data,
    }
