from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path

import joblib
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, f1_score, precision_score, recall_score, roc_auc_score
from sklearn.pipeline import Pipeline


FEATURE_COLUMNS = [
    "open",
    "high",
    "low",
    "close",
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
]


@dataclass(frozen=True)
class Metrics:
    accuracy: float
    precision: float
    recall: float
    f1: float
    roc_auc: float
    train_rows: int
    test_rows: int
    positive_rate_train: float
    positive_rate_test: float


def load_dataset(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(path)
    if "date" not in frame.columns or "target_up" not in frame.columns:
        raise ValueError("Dataset must contain date and target_up columns")

    frame["date"] = pd.to_datetime(frame["date"])
    frame = frame.sort_values(["date", "symbol"]).reset_index(drop=True)
    return frame


def split_by_time(frame: pd.DataFrame, train_ratio: float = 0.8) -> tuple[pd.DataFrame, pd.DataFrame]:
    unique_dates = sorted(frame["date"].dropna().unique())
    if len(unique_dates) < 10:
        raise ValueError("Not enough dates for time-based split")

    split_index = max(1, int(len(unique_dates) * train_ratio))
    split_date = unique_dates[split_index - 1]

    train_frame = frame[frame["date"] <= split_date].copy()
    test_frame = frame[frame["date"] > split_date].copy()

    if train_frame.empty or test_frame.empty:
        raise ValueError("Time-based split produced an empty train or test set")

    return train_frame, test_frame


def build_pipeline() -> Pipeline:
    numeric_features = FEATURE_COLUMNS

    preprocessor = ColumnTransformer(
        transformers=[
            (
                "numeric",
                Pipeline(steps=[("imputer", SimpleImputer(strategy="median"))]),
                numeric_features,
            )
        ],
        remainder="drop",
    )

    model = RandomForestClassifier(
        n_estimators=300,
        max_depth=12,
        min_samples_leaf=10,
        class_weight="balanced_subsample",
        random_state=42,
        n_jobs=-1,
    )

    return Pipeline(steps=[("preprocessor", preprocessor), ("model", model)])


def evaluate_model(model: Pipeline, test_frame: pd.DataFrame) -> Metrics:
    x_test = test_frame[FEATURE_COLUMNS]
    y_test = test_frame["target_up"]

    predictions = model.predict(x_test)
    probabilities = model.predict_proba(x_test)[:, 1]

    return Metrics(
        accuracy=accuracy_score(y_test, predictions),
        precision=precision_score(y_test, predictions, zero_division=0),
        recall=recall_score(y_test, predictions, zero_division=0),
        f1=f1_score(y_test, predictions, zero_division=0),
        roc_auc=roc_auc_score(y_test, probabilities),
        train_rows=0,
        test_rows=len(test_frame),
        positive_rate_train=0.0,
        positive_rate_test=float(y_test.mean()),
    )


def train_model(input_path: Path, model_dir: Path) -> tuple[Pipeline, Metrics, list[str]]:
    frame = load_dataset(input_path)
    frame = frame.replace([float("inf"), float("-inf")], pd.NA)

    missing_features = [column for column in FEATURE_COLUMNS if column not in frame.columns]
    if missing_features:
        raise ValueError(f"Missing feature columns: {missing_features}")

    train_frame, test_frame = split_by_time(frame)

    x_train = train_frame[FEATURE_COLUMNS]
    y_train = train_frame["target_up"]

    pipeline = build_pipeline()
    pipeline.fit(x_train, y_train)

    metrics = evaluate_model(pipeline, test_frame)
    metrics = Metrics(
        accuracy=metrics.accuracy,
        precision=metrics.precision,
        recall=metrics.recall,
        f1=metrics.f1,
        roc_auc=metrics.roc_auc,
        train_rows=len(train_frame),
        test_rows=metrics.test_rows,
        positive_rate_train=float(y_train.mean()),
        positive_rate_test=metrics.positive_rate_test,
    )

    model_dir.mkdir(parents=True, exist_ok=True)

    model_path = model_dir / "bist_up_probability_model.joblib"
    metadata_path = model_dir / "bist_up_probability_model_metadata.json"
    feature_path = model_dir / "bist_up_probability_feature_columns.json"

    joblib.dump(pipeline, model_path)

    metadata = {
        "model_path": str(model_path),
        "dataset_path": str(input_path),
        "feature_columns": FEATURE_COLUMNS,
        "metrics": asdict(metrics),
        "train_end_date": str(train_frame["date"].max().date()),
        "test_start_date": str(test_frame["date"].min().date()),
    }

    metadata_path.write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    feature_path.write_text(json.dumps(FEATURE_COLUMNS, indent=2, ensure_ascii=False), encoding="utf-8")

    return pipeline, metrics, [str(model_path), str(metadata_path), str(feature_path)]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train a baseline BIST up-probability model")
    parser.add_argument(
        "--input",
        default="data/processed/bist_training_dataset.csv",
        help="Training dataset CSV created by build_training_dataset.py",
    )
    parser.add_argument(
        "--model-dir",
        default="saved_models",
        help="Directory where the trained model and metadata will be saved",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    input_path = Path(args.input)
    model_dir = Path(args.model_dir)

    _, metrics, saved_files = train_model(input_path=input_path, model_dir=model_dir)

    print("Training complete")
    print(f"Saved files: {', '.join(saved_files)}")
    print(
        "Metrics: "
        f"accuracy={metrics.accuracy:.4f}, "
        f"precision={metrics.precision:.4f}, "
        f"recall={metrics.recall:.4f}, "
        f"f1={metrics.f1:.4f}, "
        f"roc_auc={metrics.roc_auc:.4f}"
    )
    print(
        "Rows: "
        f"train={metrics.train_rows}, test={metrics.test_rows}, "
        f"train_positive_rate={metrics.positive_rate_train:.4f}, "
        f"test_positive_rate={metrics.positive_rate_test:.4f}"
    )


if __name__ == "__main__":
    main()