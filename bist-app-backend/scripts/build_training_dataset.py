from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd


def compute_rsi(close: pd.Series, window: int = 14) -> pd.Series:
    delta = close.diff()
    gain = delta.clip(lower=0).rolling(window=window).mean()
    loss = (-delta.clip(upper=0)).rolling(window=window).mean()
    rs = gain / loss.replace(0, pd.NA)
    return 100 - (100 / (1 + rs))


def compute_ema_ratio(close: pd.Series, window: int) -> pd.Series:
    ema = close.ewm(span=window, adjust=False).mean()
    return close / ema - 1


def compute_sma_ratio(close: pd.Series, window: int) -> pd.Series:
    sma = close.rolling(window=window).mean()
    return close / sma.replace(0, pd.NA) - 1


def compute_stochastic(high: pd.Series, low: pd.Series, close: pd.Series, window: int = 14, smooth_window: int = 3) -> tuple[pd.Series, pd.Series]:
    lowest_low = low.rolling(window=window).min()
    highest_high = high.rolling(window=window).max()
    k_percent = 100 * ((close - lowest_low) / (highest_high - lowest_low)).fillna(50)
    d_percent = k_percent.rolling(window=smooth_window).mean()
    return k_percent, d_percent


def build_symbol_features(frame: pd.DataFrame, horizon: int) -> pd.DataFrame:
    frame = frame.sort_values("date").copy()
    frame["date"] = pd.to_datetime(frame["date"])

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

    frame["future_close"] = frame["close"].shift(-horizon)
    frame["future_return"] = frame["future_close"] / frame["close"] - 1
    frame["target_up"] = (frame["future_return"] > 0.02).astype(int)

    return frame


def build_training_dataset(input_path: Path, output_path: Path, horizon: int) -> pd.DataFrame:
    raw = pd.read_csv(input_path)

    required_columns = {"symbol", "date", "open", "high", "low", "close", "volume"}
    missing = required_columns - set(raw.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")

    raw["symbol"] = raw["symbol"].astype(str)
    raw["date"] = pd.to_datetime(raw["date"])

    feature_frames = []
    for symbol, symbol_frame in raw.groupby("symbol", sort=False):
        enriched = build_symbol_features(symbol_frame, horizon=horizon)
        enriched["symbol"] = symbol
        feature_frames.append(enriched)

    combined = pd.concat(feature_frames, ignore_index=True)

    feature_columns = [
        "symbol",
        "date",
        "open",
        "high",
        "low",
        "close",
        "adj_close",
        "volume",
        "return_1d",
        "return_3d",
        "return_5d",
        "sma_5_ratio",
        "sma_10_ratio",
        "sma_20_ratio",
        "ema_12_ratio",
        "ema_26_ratio",
        "rsi_14",
        "macd",
        "macd_signal",
        "macd_histogram",
        "macd_positive",
        "macd_signal_diff",
        "stochastic_k",
        "stochastic_d",
        "stochastic_diff",
        "stochastic_overbought",
        "stochastic_oversold",
        "volatility_5d",
        "volatility_10d",
        "volume_change_1d",
        "volume_change_5d",
        "volume_sma_20_ratio",
        "future_return",
        "target_up",
    ]

    existing_columns = [column for column in feature_columns if column in combined.columns]
    combined = combined[existing_columns].copy()
    combined = combined.replace([float("inf"), float("-inf")], pd.NA)
    combined = combined.dropna().reset_index(drop=True)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    combined.to_csv(output_path, index=False)

    return combined


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a training dataset from raw BIST OHLCV data")
    parser.add_argument(
        "--input",
        default="data/raw/bist_ohlcv_3y.csv",
        help="Raw dataset CSV generated by collect_market_dataset.py",
    )
    parser.add_argument(
        "--output",
        default="data/processed/bist_training_dataset.csv",
        help="Output CSV path for the model training dataset",
    )
    parser.add_argument(
        "--horizon",
        type=int,
        default=5,
        help="Forecast horizon in trading days",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)

    dataset = build_training_dataset(input_path=input_path, output_path=output_path, horizon=args.horizon)

    print(f"Saved training dataset to: {output_path}")
    print(f"Rows: {len(dataset)}")
    print(f"Target positive rate: {dataset['target_up'].mean():.4f}")


if __name__ == "__main__":
    main()