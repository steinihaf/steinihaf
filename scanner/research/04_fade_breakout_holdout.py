"""One pre-registered rule, chosen from the training years, tested once on 2023-2026.

Rule (primary): when a daily bar closes beyond the prior 100-day high/low for the first
time, trade AGAINST the break at the next open; exit at the close 10 bars later, or at a
protective stop 3 ATR away. Spread charged. Result in R (1R = 3 ATR).
Secondary cells are shown only to see whether the primary sits on a plateau.
"""
import numpy as np
import pandas as pd

from common import HOLDOUT_START, TRAIN_END, clustered, load
from fxscan.setups import WARMUP

u = load()
STOP_ATR = 3.0


def run(n_ch, hold, period):
    rows = []
    for sym, p in u.pairs.items():
        hh = pd.Series(p.h).rolling(n_ch).max().shift(1).to_numpy()
        ll = pd.Series(p.l).rolling(n_ch).min().shift(1).to_numpy()
        busy_until = -1
        for t in range(WARMUP, len(p) - hold - 1):
            dt = p.dates[t]
            if (period == "train") != (dt <= TRAIN_END) or t <= busy_until:
                continue
            up, dn = p.c[t] > hh[t], p.c[t] < ll[t]
            if not (up or dn) or p.c[t - 1] > hh[t - 1] or p.c[t - 1] < ll[t - 1]:
                continue
            d = -1 if up else 1
            a, e = p.atr[t], t + 1
            entry = p.o[e]
            if abs(entry - p.c[t]) > 0.5 * a:
                continue
            stop = entry - d * STOP_ATR * a
            exit_px = None
            for i in range(e, e + hold):
                if i > e and (p.o[i] - stop) * d <= 0:
                    exit_px = p.o[i]; break
                if (p.l[i] <= stop) if d > 0 else (p.h[i] >= stop):
                    exit_px = stop; break
            if exit_px is None:
                i = e + hold - 1
                exit_px = p.c[i]
            busy_until = i
            rows.append({"sym": sym, "date": dt, "year": dt.year,
                         "r": ((exit_px - entry) * d - p.ins.spread) / (STOP_ATR * a)})
    return pd.DataFrame(rows)


for period in ("train", "holdout"):
    print(f"\n== {period} ==   mean R per trade (t clustered by date), n")
    for n_ch in (55, 100, 150):
        cells = []
        for hold in (5, 10, 20):
            c = clustered(run(n_ch, hold, period), "r")
            cells.append(f"hold {hold}: {c['mean']:+.3f} (t {c['t']:+.1f}) n={c['n']}")
        print(f"  fade {n_ch:3d}-day break | " + " | ".join(cells))
    s = run(100, 10, period)
    print("  primary rule by year: " + "  ".join(
        f"{y}: {g.r.mean():+.3f} (n={len(g)})" for y, g in s.groupby("year")))
    print(f"  primary rule: win rate {(s.r > 0).mean():.0%}, total {s.r.sum():+.1f}R, "
          f"positive in {(s.groupby('sym').r.mean() > 0).sum()} of {s.sym.nunique()} instruments")
