from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import pandas as pd
import yfinance as yf


DEFAULT_SYMBOLS = [
    "THYAO",
    "ASELS",
    "GARAN",
    "AKBNK",
    "SISE",
    "EREGL",
    "KCHOL",
    "SASA",
    "HEKTS",
    "PETKM",
    "FROTO",
    "ISCTR",
    "AYGAZ",
    "MGROS",
    "SOKM",
    "TCELL",
    "TUPRS",
    "YKBNK",
    "TTKOM",
    "ULKER",
    "BIMAS",
    "ENKAI",
    "HALKB",
    "VAKBN",
]


@dataclass(frozen=True)
class DownloadResult:
    symbol: str
    rows: int


def normalize_symbol(symbol: str) -> str:
    cleaned = symbol.strip().upper()
    if not cleaned.endswith(".IS"):
        cleaned = f"{cleaned}.IS"
    return cleaned


def download_history(symbol: str, period: str, interval: str) -> pd.DataFrame:
    ticker = yf.Ticker(normalize_symbol(symbol))
    history = ticker.history(period=period, interval=interval, auto_adjust=False)

    if history.empty:
        return pd.DataFrame()

    frame = history.reset_index().copy()
    date_column = "Date" if "Date" in frame.columns else "Datetime"

    rename_map = {
        date_column: "date",
        "Open": "open",
        "High": "high",
        "Low": "low",
        "Close": "close",
        "Adj Close": "adj_close",
        "Volume": "volume",
    }
    frame = frame.rename(columns=rename_map)

    keep_columns = [
        "date",
        "open",
        "high",
        "low",
        "close",
        "adj_close",
        "volume",
    ]

    frame = frame[[column for column in keep_columns if column in frame.columns]].copy()
    frame.insert(0, "symbol", normalize_symbol(symbol))
    frame["date"] = pd.to_datetime(frame["date"]).dt.strftime("%Y-%m-%d")
    frame = frame.dropna(subset=["close"])
    frame = frame.sort_values("date")

    return frame


def collect_dataset(symbols: Iterable[str], period: str, interval: str) -> tuple[pd.DataFrame, list[DownloadResult]]:
    frames: list[pd.DataFrame] = []
    results: list[DownloadResult] = []

    for symbol in symbols:
        try:
            frame = download_history(symbol, period=period, interval=interval)
            rows = len(frame)
            results.append(DownloadResult(symbol=normalize_symbol(symbol), rows=rows))
            if not frame.empty:
                frames.append(frame)
        except Exception as exc:
            results.append(DownloadResult(symbol=normalize_symbol(symbol), rows=0))
            print(f"[WARN] {symbol}: {exc}")

    if frames:
        combined = pd.concat(frames, ignore_index=True)
    else:
        combined = pd.DataFrame(columns=["symbol", "date", "open", "high", "low", "close", "adj_close", "volume"])

    return combined, results


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="BIST historical dataset collector")
    parser.add_argument(
        "--symbols",
        nargs="*",
        default=DEFAULT_SYMBOLS,
        help="BIST symbols without .IS suffix. Example: THYAO ASELS GARAN",
    )
    parser.add_argument("--period", default="10y", help="yfinance period, default: 10y")
    parser.add_argument("--interval", default="1d", help="yfinance interval, default: 1d")
    parser.add_argument(
        "--output",
        default="data/raw/bist_ohlcv_3y.csv",
        help="Output CSV path for combined dataset",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    combined, results = collect_dataset(args.symbols, period=args.period, interval=args.interval)

    combined.to_csv(output_path, index=False)

    summary_path = output_path.with_name(f"{output_path.stem}_summary.csv")
    summary_frame = pd.DataFrame([result.__dict__ for result in results])
    summary_frame.to_csv(summary_path, index=False)

    print(f"Saved dataset to: {output_path}")
    print(f"Saved summary to: {summary_path}")
    print(f"Total rows: {len(combined)}")


if __name__ == "__main__":
    main()