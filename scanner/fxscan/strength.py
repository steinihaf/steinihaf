"""Currency strength: how each of the 8 currencies has moved against the other seven."""
from __future__ import annotations

import numpy as np
import pandas as pd

from .universe import CURRENCIES, instrument


def strength_panel(closes: pd.DataFrame, atrs: pd.DataFrame, lookback: int = 20) -> pd.DataFrame:
    """Per-date strength of each currency.

    closes / atrs: date-indexed frames with one column per FX pair. A pair's move over
    `lookback` days is measured in units of its own daily ATR, so quiet and volatile pairs
    weigh the same; a currency's strength is the mean signed move over the pairs it is in.
    The calculation is causal: the row for date D uses data up to D only.
    """
    move = (closes - closes.shift(lookback)) / atrs
    out = {}
    for ccy in CURRENCIES:
        parts = []
        for sym in move.columns:
            ins = instrument(sym)
            if not ins.is_fx:
                continue
            if ins.base == ccy:
                parts.append(move[sym])
            elif ins.quote == ccy:
                parts.append(-move[sym])
        if parts:
            out[ccy] = pd.concat(parts, axis=1).mean(axis=1, skipna=True)
    return pd.DataFrame(out)


def pair_differential(panel: pd.DataFrame, symbol: str) -> pd.Series:
    """Base strength minus quote strength (NaN for non-FX symbols)."""
    ins = instrument(symbol)
    if not ins.is_fx or ins.base not in panel or ins.quote not in panel:
        return pd.Series(np.nan, index=panel.index)
    return panel[ins.base] - panel[ins.quote]
