"""ZigZag pivots - the same Depth / Deviation / Backstep algorithm LineTouchEA uses.

Arrays are chronological (index 0 = oldest bar). The newest pivot of a ZigZag moves until
price reverses, so callers that need stable levels skip it, exactly as the EA does.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class Pivot:
    index: int
    price: float
    is_peak: bool


def zigzag(high: np.ndarray, low: np.ndarray, depth: int = 12, deviation: float = 0.0,
           backstep: int = 3) -> list[Pivot]:
    n = len(high)
    if n < depth + backstep + 3:
        return []
    hi_map = [0.0] * n
    lo_map = [0.0] * n
    last_low = last_high = 0.0
    # pass 1: candidate extremes of the rolling `depth` window
    win = np.lib.stride_tricks.sliding_window_view
    roll_lo = win(low, depth).min(axis=1).tolist()    # roll_lo[k] covers bars k..k+depth-1
    roll_hi = win(high, depth).max(axis=1).tolist()
    high, low = high.tolist(), low.tolist()           # plain floats: the loops below are scalar
    for i in range(depth - 1, n):
        val = roll_lo[i - depth + 1]
        if val == last_low:
            val = 0.0
        else:
            last_low = val
            if low[i] - val > deviation:
                val = 0.0
            else:
                for back in range(1, backstep + 1):
                    j = i - back
                    if j >= 0 and lo_map[j] != 0.0 and lo_map[j] > val:
                        lo_map[j] = 0.0
        lo_map[i] = val if (val != 0.0 and low[i] == val) else 0.0

        val = roll_hi[i - depth + 1]
        if val == last_high:
            val = 0.0
        else:
            last_high = val
            if val - high[i] > deviation:
                val = 0.0
            else:
                for back in range(1, backstep + 1):
                    j = i - back
                    if j >= 0 and hi_map[j] != 0.0 and hi_map[j] < val:
                        hi_map[j] = 0.0
        hi_map[i] = val if (val != 0.0 and high[i] == val) else 0.0

    # pass 2: keep alternating peaks and troughs, extending a leg while it makes new extremes
    pivots: list[Pivot] = []
    look = 0   # 0 = nothing yet, 1 = last pivot was a trough, -1 = last pivot was a peak
    for i in range(depth - 1, n):
        h, l = hi_map[i], lo_map[i]
        if look == 0:
            if h != 0.0:
                pivots.append(Pivot(i, h, True)); look = -1
            elif l != 0.0:
                pivots.append(Pivot(i, l, False)); look = 1
        elif look == 1:
            if l != 0.0 and l < pivots[-1].price and h == 0.0:
                pivots[-1] = Pivot(i, l, False)
            elif h != 0.0 and l == 0.0:
                pivots.append(Pivot(i, h, True)); look = -1
        else:
            if h != 0.0 and h > pivots[-1].price and l == 0.0:
                pivots[-1] = Pivot(i, h, True)
            elif l != 0.0 and h == 0.0:
                pivots.append(Pivot(i, l, False)); look = 1
    return pivots
