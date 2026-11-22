"""Bar-by-bar replay of the scanner's own `detect` on daily history.

Rules of the replay (kept deliberately conservative):
* a signal on bar t is entered at the open of bar t+1; stop and target stay where the
  signal put them, and the trade is skipped if the open is more than half the risk
  distance away from the signal bar's close;
* if a bar's range contains both the stop and the target, the stop is taken;
* a gap through the stop exits at the open (worse than the stop);
* trades still open after `max_bars` bars are closed at that bar's close;
* one position per instrument; the instrument's assumed spread is charged once per trade;
* swaps, commissions and slippage beyond the spread are not modelled.
Results are in R (multiples of the initial risk), so no position sizing is assumed.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict

import numpy as np
import pandas as pd

from .setups import PairData, WARMUP, detect

MAX_ENTRY_GAP = 0.5   # skip a signal when the next open is further than this many R from its close


@dataclass
class Trade:
    symbol: str
    kind: str
    direction: int
    score: int
    signal_date: str
    entry_date: str
    exit_date: str
    entry: float
    exit: float
    r: float
    bars: int
    outcome: str    # "target" | "stop" | "time"

    def to_dict(self):
        return asdict(self)


def backtest_pair(p: PairData, start: int = WARMUP, max_bars: int = 20) -> list[Trade]:
    trades: list[Trade] = []
    n = len(p)
    t = start
    while t < n - 1:
        s = detect(p, t)
        if s is None:
            t += 1
            continue
        d, stop, target = s.direction, s.stop, s.target
        e = t + 1
        entry = p.o[e]
        risk = (entry - stop) * d
        signal_risk = (p.c[t] - stop) * d
        # An open far from the signal close changes the trade (and in daily FX data is often
        # a bad print): such signals are skipped, as a trader looking at the gap would.
        if (risk <= 0 or (target - entry) * d <= 0
                or abs(entry - p.c[t]) > MAX_ENTRY_GAP * signal_risk):
            t += 1
            continue
        exit_price = outcome = None
        i = e
        while i < n:
            o, h, l = p.o[i], p.h[i], p.l[i]
            if i > e and (o - stop) * d <= 0:            # gapped through the stop
                exit_price, outcome = o, "stop"
            elif (l <= stop) if d > 0 else (h >= stop):
                exit_price, outcome = stop, "stop"
            elif (h >= target) if d > 0 else (l <= target):
                exit_price, outcome = target, "target"
            elif i - e + 1 >= max_bars:
                exit_price, outcome = p.c[i], "time"
            if outcome:
                break
            i += 1
        if outcome is None:        # still open at the end of history: not counted
            break
        r = ((exit_price - entry) * d - p.ins.spread) / risk
        trades.append(Trade(p.ins.symbol, s.kind, d, s.score, s.date, str(p.dates[e].date()),
                            str(p.dates[i].date()), float(entry), float(exit_price),
                            round(float(r), 3), i - e + 1, outcome))
        t = i + 1 if i > t else t + 1
    return trades


def summarize(rs) -> dict:
    rs = np.asarray(list(rs), dtype=float)
    if len(rs) == 0:
        return {"trades": 0}
    wins, losses = rs[rs > 0], rs[rs <= 0]
    equity = np.cumsum(rs)
    dd = float((np.maximum.accumulate(np.concatenate(([0.0], equity)))[1:] - equity).max())
    # standard error of the mean: is the average distinguishable from zero?
    se = float(rs.std(ddof=1) / np.sqrt(len(rs))) if len(rs) > 1 else float("nan")
    return {
        "trades": int(len(rs)),
        "win_rate": round(float(len(wins) / len(rs)), 3),
        "avg_r": round(float(rs.mean()), 3),
        "avg_r_se": round(se, 3),
        "total_r": round(float(rs.sum()), 1),
        "profit_factor": round(float(wins.sum() / -losses.sum()), 2) if losses.sum() < 0 else None,
        "max_drawdown_r": round(dd, 1),
    }


def run(pairs: dict[str, PairData], max_bars: int = 20, log=None) -> dict:
    trades: list[Trade] = []
    for sym, p in pairs.items():
        tr = backtest_pair(p, max_bars=max_bars)
        trades += tr
        if log:
            log(f"{sym}: {len(tr)} trades")
    trades.sort(key=lambda t: (t.exit_date, t.symbol))
    df = pd.DataFrame([t.to_dict() for t in trades])
    out = {"overall": summarize(df["r"]) if len(df) else {"trades": 0}, "trades": trades}
    if len(df):
        df["year"] = df["exit_date"].str[:4]
        df["bucket"] = pd.cut(df["score"], [-1, 39, 59, 100], labels=["0-39", "40-59", "60-100"])
        df["side"] = np.where(df["direction"] > 0, "long", "short")
        for key in ("kind", "bucket", "year", "side", "symbol"):
            out["by_" + key] = {str(k): summarize(g["r"]) for k, g in df.groupby(key, observed=True)}
        out["by_kind_bucket"] = {f"{k} / {b}": summarize(g["r"])
                                 for (k, b), g in df.groupby(["kind", "bucket"], observed=True)}
        out["period"] = [df["entry_date"].min(), df["exit_date"].max()]
    return out
