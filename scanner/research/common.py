"""Shared helpers for the rule research: cached data loading and date-clustered statistics."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from fxscan.data import CsvProvider, TwelveDataProvider  # noqa: E402
from fxscan.scan import load_universe  # noqa: E402

TRAIN_END = pd.Timestamp("2022-12-31")     # rules are developed on bars up to here only
HOLDOUT_START = pd.Timestamp("2023-01-01")


def load(csv_dir: str | None = None):
    provider = CsvProvider(csv_dir) if csv_dir else TwelveDataProvider(
        cache_dir=ROOT / ".cache", cache_minutes=60 * 24 * 30)
    return load_universe(provider)


def clustered(df: pd.DataFrame, col: str, date_col: str = "date") -> dict:
    """Mean of `col` with a standard error that treats each date as one observation.

    Signals on the same day across pairs share currencies, so they are not independent;
    averaging per date first avoids overstating the evidence.
    """
    if len(df) == 0:
        return {"n": 0, "days": 0, "mean": float("nan"), "t": float("nan")}
    daily = df.groupby(date_col)[col].mean()
    se = daily.std(ddof=1) / np.sqrt(len(daily)) if len(daily) > 1 else float("nan")
    return {"n": int(len(df)), "days": int(len(daily)), "mean": round(float(df[col].mean()), 4),
            "t": round(float(daily.mean() / se), 2) if se and se > 0 else float("nan")}
