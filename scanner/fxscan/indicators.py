"""Causal indicators on numpy arrays (value at i uses bars 0..i only)."""
from __future__ import annotations

import numpy as np


def ema(x: np.ndarray, period: int) -> np.ndarray:
    out = np.full(len(x), np.nan)
    if len(x) < period:
        return out
    k = 2.0 / (period + 1)
    out[period - 1] = x[:period].mean()
    for i in range(period, len(x)):
        out[i] = out[i - 1] + k * (x[i] - out[i - 1])
    return out


def _wilder(x: np.ndarray, period: int, start: int) -> np.ndarray:
    """Wilder smoothing of x[start:], seeded with a simple average."""
    out = np.full(len(x), np.nan)
    if len(x) < start + period:
        return out
    out[start + period - 1] = x[start:start + period].mean()
    for i in range(start + period, len(x)):
        out[i] = (out[i - 1] * (period - 1) + x[i]) / period
    return out


def true_range(high, low, close) -> np.ndarray:
    prev = np.concatenate(([close[0]], close[:-1]))
    return np.maximum(high - low, np.maximum(np.abs(high - prev), np.abs(low - prev)))


def atr(high, low, close, period: int = 14) -> np.ndarray:
    return _wilder(true_range(high, low, close), period, 1)


def rsi(close: np.ndarray, period: int = 14) -> np.ndarray:
    d = np.diff(close, prepend=close[0])
    up = _wilder(np.where(d > 0, d, 0.0), period, 1)
    dn = _wilder(np.where(d < 0, -d, 0.0), period, 1)
    with np.errstate(divide="ignore", invalid="ignore"):
        out = 100.0 - 100.0 / (1.0 + up / dn)
    out[(dn == 0) & ~np.isnan(up)] = 100.0
    return out


def adx(high, low, close, period: int = 14) -> np.ndarray:
    up = np.diff(high, prepend=high[0])
    dn = -np.diff(low, prepend=low[0])
    plus = np.where((up > dn) & (up > 0), up, 0.0)
    minus = np.where((dn > up) & (dn > 0), dn, 0.0)
    tr = _wilder(true_range(high, low, close), period, 1)
    with np.errstate(divide="ignore", invalid="ignore"):
        pdi = 100.0 * _wilder(plus, period, 1) / tr
        mdi = 100.0 * _wilder(minus, period, 1) / tr
        dx = 100.0 * np.abs(pdi - mdi) / (pdi + mdi)
    dx = np.where(np.isnan(dx) & ~np.isnan(tr), 0.0, dx)
    return _wilder(np.nan_to_num(dx), period, 2 * period - 1 if len(dx) > 2 * period else 1)
