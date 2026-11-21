"""Load the universe and scan the last completed daily bar of every instrument."""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
import pandas as pd

from . import indicators as ind
from .data import DataError
from .setups import PairData, Setup, daily_trend, detect, WARMUP
from .strength import pair_differential, strength_panel
from .universe import ALL_SYMBOLS


@dataclass
class Universe:
    pairs: dict[str, PairData]
    strength: pd.DataFrame            # per-date currency strength
    errors: dict[str, str] = field(default_factory=dict)

    @property
    def last_date(self) -> pd.Timestamp:
        return max(p.dates[-1] for p in self.pairs.values())


def load_universe(provider, symbols=None, years: int = 10, log=None) -> Universe:
    symbols = list(symbols or ALL_SYMBOLS)
    pairs, errors = {}, {}
    for sym in symbols:
        try:
            df = provider.daily(sym, years=years)
            if len(df) < WARMUP + 20:
                raise DataError(f"only {len(df)} daily bars")
            pairs[sym] = PairData.from_frame(sym, df)
            if log:
                log(f"{sym}: {len(df)} bars to {df.index[-1].date()}")
        except Exception as exc:
            errors[sym] = str(exc)
            if log:
                log(f"{sym}: FAILED - {exc}")
    if not pairs:
        raise DataError("no instrument could be loaded: " + "; ".join(f"{k}: {v}" for k, v in errors.items()))
    fx = {s: p for s, p in pairs.items() if p.ins.is_fx}
    if fx:
        closes = pd.DataFrame({s: pd.Series(p.c, index=p.dates) for s, p in fx.items()}).sort_index()
        atrs = pd.DataFrame({s: pd.Series(p.atr, index=p.dates) for s, p in fx.items()}).sort_index()
        closes, atrs = closes.ffill(limit=3), atrs.ffill(limit=3)
        panel = strength_panel(closes, atrs)
        for s, p in fx.items():
            p.strength_diff = pair_differential(panel, s).reindex(p.dates).to_numpy(dtype=float)
    else:
        panel = pd.DataFrame()
    return Universe(pairs, panel, errors)


def h4_state(provider, symbol: str, direction: int) -> str | None:
    """Has the 4-hour chart turned in the trade direction? (timing note, not scored)"""
    try:
        df = provider.h4(symbol)
    except Exception:
        return None
    if len(df) < 60:
        return None
    c = df["close"].to_numpy(dtype=float)
    e20, e50 = ind.ema(c, 20), ind.ema(c, 50)
    above20 = (c[-1] - e20[-1]) * direction > 0
    stacked = (e20[-1] - e50[-1]) * direction > 0
    if above20 and stacked:
        return "aligned"
    if above20:
        return "turning"
    return "not yet"


def scan(universe: Universe, provider=None, max_age_days: int = 4) -> tuple[list[Setup], list[dict], list[str]]:
    """Setups on each instrument's last completed bar, a watchlist, and data warnings."""
    setups, watch, warnings = [], [], []
    newest = universe.last_date
    for sym, p in universe.pairs.items():
        t = len(p) - 1
        age = (newest - p.dates[t]).days
        if age > max_age_days:
            warnings.append(f"{sym}: last bar is {p.dates[t].date()}, {age} days behind - skipped")
            continue
        s = detect(p, t)
        if s:
            if provider is not None:
                s.h4_state = h4_state(provider, sym, s.direction)
            setups.append(s)
            continue
        d = daily_trend(p, t)
        if d != 0 and not np.isnan(p.atr[t]):
            atr = p.atr[t]
            ext = p.l[t - 3:t + 1].min() if d > 0 else p.h[t - 3:t + 1].max()
            in_zone = (ext - p.ema20[t]) * d <= 0.1 * atr
            intact = (p.c[t] - p.ema50[t]) * d > -0.5 * atr
            if in_zone and intact:
                trig = p.h[t] if d > 0 else p.l[t]
                watch.append({
                    "symbol": sym, "direction": d, "trend": "up" if d > 0 else "down",
                    "close": round(float(p.c[t]), p.ins.digits),
                    "trigger": round(float(trig), p.ins.digits),
                    "strength_diff": None if np.isnan(p.strength_diff[t])
                    else round(float(p.strength_diff[t] * d), 2),
                    "note": f"in the pullback zone; a daily close {'above' if d > 0 else 'below'} "
                            f"{trig:.{p.ins.digits}f} would trigger",
                })
    for sym, err in universe.errors.items():
        warnings.append(f"{sym}: no data ({err})")
    setups.sort(key=lambda s: -s.score)
    watch.sort(key=lambda w: -(w["strength_diff"] or 0))
    return setups, watch, warnings
