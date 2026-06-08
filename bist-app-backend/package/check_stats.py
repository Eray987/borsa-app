import pandas as pd
import numpy as np
import pickle
from pathlib import Path
import warnings
warnings.filterwarnings('ignore')


class ProbBlend:
    """Picklable soft-vote wrapper for two fitted classifiers."""

    def __init__(self, m1, m2, w1=0.5, w2=0.5):
        self.m1, self.m2, self.w1, self.w2 = m1, m2, w1, w2
        self.classes_ = m1.classes_

    def predict_proba(self, X):
        p1 = self.m1.predict_proba(X)
        p2 = self.m2.predict_proba(X)
        return self.w1 * p1 + self.w2 * p2

    def predict(self, X):
        return np.argmax(self.predict_proba(X), axis=1)

# Constants from train.py
INPUT_FILE = "bist30_2year_long_format.csv"
MODEL_PATH = "models/model_bist30_multiclass_v1.pkl"
DOWN_THRESHOLD = -0.03
UP_THRESHOLD = 0.02

def label_target(series):
    result = np.ones(len(series), dtype=int)
    result[series <= DOWN_THRESHOLD] = 0
    result[series >= UP_THRESHOLD] = 2
    return result

def add_derived_features(df):
    out = df.copy()
    eps = 1e-6

    # --- Log-return features (more normally distributed than raw pct returns) ---
    for col in ["return_1d", "return_5d", "return_10d"]:
        if col in out.columns:
            out[f"log_{col}"] = np.log1p(out[col].clip(-0.9, 10.0))

    # Core derived features
    out["momentum_spread"] = out["return_10d"] - out["return_1d"]
    out["trend_gap"] = out["price_vs_sma50"] - out["price_vs_sma200"]
    out["vol_spread"] = out["volatility_20d"] - out["volatility_10d"]

    out["market_relative_1d"] = out["return_1d"] - out["xu100_return_1d"]
    out["market_relative_5d"] = out["return_5d"] - out["xu100_return_5d"]
    out["usd_pressure_1d"] = out["return_1d"] - out["usdtry_return_1d"]

    out["rsi_centered"] = out["rsi14"] - 50.0
    out["macd_vol_scaled"] = out["macd_hist"] / (out["volatility_20d"].abs() + eps)
    out["risk_adj_return_5d"] = out["return_5d"] / (out["volatility_20d"].abs() + eps)

    if "market_cap" in out.columns:
        out["log_market_cap"] = np.log1p(out["market_cap"].clip(lower=0))
    if "trailing_pe" in out.columns and "price_to_book" in out.columns:
        out["pe_pb_ratio"] = out["trailing_pe"] / (out["price_to_book"].abs() + eps)
    if "return_on_equity" in out.columns and "profit_margins" in out.columns:
        out["roe_x_margin"] = out["return_on_equity"] * out["profit_margins"]
    if "revenue_qoq" in out.columns and "net_income_qoq" in out.columns:
        out["growth_qoq_mix"] = 0.6 * out["revenue_qoq"] + 0.4 * out["net_income_qoq"]
    if "revenue_yoy" in out.columns and "net_income_yoy" in out.columns:
        out["growth_yoy_mix"] = 0.6 * out["revenue_yoy"] + 0.4 * out["net_income_yoy"]
    if "turnover_z20" in out.columns and "amihud_20d" in out.columns:
        out["liquidity_pressure"] = out["turnover_z20"] - np.log1p(out["amihud_20d"].abs())

    # --- Sentiment: shift by 1 day per ticker to avoid same-day leakage,
    #     then derive all sentiment features used by the model. ---
    if "sentiment_score" in out.columns and "ticker" in out.columns:
        if "date" in out.columns:
            out = out.sort_values(["ticker", "date"])
        out["sentiment_score_raw"] = out["sentiment_score"]
        # t-1 shift: use previous day's sentiment to predict today's next-day return
        out["sentiment_score"] = out.groupby("ticker")["sentiment_score_raw"].shift(1).fillna(0.5)
        for nc in ["news_count", "news_up_probability"]:
            if nc in out.columns:
                out[nc] = out.groupby("ticker")[nc].shift(1).fillna(out[nc].median() if out[nc].notna().any() else 0)

        # Derived sentiment features (same set expected by model_features)
        out["sentiment_shift_1d"] = out.groupby("ticker")["sentiment_score"].diff().fillna(0.0)
        out["sentiment_ewm_5"] = (
            out.groupby("ticker")["sentiment_score"]
            .transform(lambda x: x.ewm(span=5, adjust=False).mean())
            .fillna(0.5)
        )
        out["news_count_norm"] = np.log1p(out["news_count"].fillna(0))
        out["news_up_prob_adj"] = out["news_up_probability"].fillna(0.5) - 0.5
        if "volume_ratio" in out.columns:
            out["sentiment_vol_interaction"] = out["sentiment_score"] * out["volume_ratio"].fillna(0.0)
        else:
            out["sentiment_vol_interaction"] = 0.0

    # --- ticker_code: numeric encoding used as a feature ---
    if "ticker" in out.columns and "ticker_code" not in out.columns:
        tickers_sorted = sorted(out["ticker"].dropna().unique())
        ticker_map = {t: i for i, t in enumerate(tickers_sorted)}
        out["ticker_code"] = out["ticker"].map(ticker_map).fillna(-1).astype(int)

    out = out.replace([np.inf, -np.inf], np.nan)
    return out

if __name__ == "__main__":
    # Load data
    df = pd.read_csv(INPUT_FILE)
    df = add_derived_features(df)

    # Target distribution
    df['true_label'] = label_target(df['target'])
    dist_true = df['true_label'].value_counts(normalize=True).sort_index()
    print("1) Target Class Distribution:")
    for i, name in enumerate(["SELL", "HOLD", "BUY"]):
        print(f"  {name}: {dist_true.get(i, 0):.2%}")

    # Load model
    with open(MODEL_PATH, "rb") as f:
        artifact = pickle.load(f)
    model = artifact["model"]
    model_features = artifact["model_features"]

    # Check for missing features
    missing_features = [f for f in model_features if f not in df.columns]
    if missing_features:
        print(f"\nMissing features: {missing_features}")
        for f in missing_features:
            df[f] = 0

    # Predict
    probs = model.predict_proba(df[model_features].fillna(0))
    preds = np.argmax(probs, axis=1)

    # Model prediction distribution
    dist_pred = pd.Series(preds).value_counts(normalize=True).sort_index()
    print("\n2) Model Prediction Distribution:")
    for i, name in enumerate(["SELL", "HOLD", "BUY"]):
        print(f"  {name}: {dist_pred.get(i, 0):.2%}")

    # Average predicted probabilities
    avg_probs = probs.mean(axis=0)
    print("\n3) Average Predicted Probabilities:")
    for i, name in enumerate(["SELL", "HOLD", "BUY"]):
        print(f"  {name}: {avg_probs[i]:.4f}")
