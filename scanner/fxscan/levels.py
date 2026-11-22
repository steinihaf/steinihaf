"""Multi-timeframe support / resistance levels from ZigZag pivots (LineTouchEA scheme)."""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .zigzag import zigzag

GRADE_RANK = {"A": 0, "B": 1}


@dataclass(frozen=True)
class Level:
    price: float
    grade: str        # "A" = monthly / weekly pivot, "B" = daily pivot
    sources: tuple    # timeframes that contributed, e.g. ("W1", "D1")


def aggregate(keys: np.ndarray, high: np.ndarray, low: np.ndarray):
    """Collapse consecutive bars sharing a key (week / month id) into higher-timeframe bars."""
    starts = np.flatnonzero(np.concatenate(([True], keys[1:] != keys[:-1])))
    return np.maximum.reduceat(high, starts), np.minimum.reduceat(low, starts)


def _pivot_prices(high, low, depth, backstep, max_per_tf):
    piv = zigzag(high, low, depth=depth, backstep=backstep)
    # newest first, skipping the newest pivot (it still moves)
    return [p.price for p in reversed(piv[:-1])][:max_per_tf]


def build_levels(high: np.ndarray, low: np.ndarray, week_id: np.ndarray, month_id: np.ndarray,
                 merge_distance: float, depth: int = 12, backstep: int = 3,
                 max_per_tf: int = 8, d1_lookback: int = 500) -> list[Level]:
    """Levels known at the last bar of the arrays passed in (pass arrays cut at `t`)."""
    raw: list[tuple[float, str, str]] = []
    mh, ml = aggregate(month_id, high, low)
    raw += [(p, "A", "MN1") for p in _pivot_prices(mh, ml, depth, backstep, max_per_tf)]
    wh, wl = aggregate(week_id, high, low)
    raw += [(p, "A", "W1") for p in _pivot_prices(wh, wl, depth, backstep, max_per_tf)]
    raw += [(p, "B", "D1") for p in _pivot_prices(high[-d1_lookback:], low[-d1_lookback:],
                                                  depth, backstep, max_per_tf)]
    if not raw:
        return []
    raw.sort(key=lambda r: r[0])
    clusters: list[list[tuple[float, str, str]]] = [[raw[0]]]
    for item in raw[1:]:
        if item[0] - clusters[-1][-1][0] <= merge_distance:
            clusters[-1].append(item)
        else:
            clusters.append([item])
    out = []
    for c in clusters:
        best = min(c, key=lambda r: GRADE_RANK[r[1]])[1]
        # the cluster sits at the mean of its best-grade members
        top = [r[0] for r in c if r[1] == best]
        srcs = tuple(dict.fromkeys(r[2] for r in c))
        out.append(Level(float(np.mean(top)), best, srcs))
    return out
