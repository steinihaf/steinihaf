"""Hypothesis from 01: daily FX moves that are large against their own ATR partly retrace.

Grid over lookback / threshold / holding period on the TRAINING years only, net of the
assumed spread, entering at the next open on the first day the condition appears.
A real effect should show as a plateau across neighbouring cells, not one good cell.
"""
import sys

import numpy as np
import pandas as pd

from common import HOLDOUT_START, TRAIN_END, clustered, load
from fxscan.setups import WARMUP

u = load()
period = sys.argv[1] if len(sys.argv) > 1 else "train"


def signals(lookback, thr):
    rows = []
    for sym, p in u.pairs.items():
        n = len(p)
        mv = np.full(n, np.nan)
        mv[lookback:] = (p.c[lookback:] - p.c[:-lookback]) / p.atr[lookback:]
        for t in range(WARMUP, n - 21):
            dt = p.dates[t]
            if (period == "train" and dt > TRAIN_END) or (period == "holdout" and dt < HOLDOUT_START):
                continue
            if np.isnan(mv[t]) or abs(mv[t]) < thr or abs(mv[t - 1]) >= thr:
                continue
            d = -np.sign(mv[t])
            a, e, cost = p.atr[t], p.o[t + 1], p.ins.spread
            if abs(e - p.c[t]) > 0.5 * a:      # gapped / bad print
                continue
            rows.append({"sym": sym, "date": dt, "year": dt.year, "fx": p.ins.is_fx,
                         **{f"h{h}": (d * (p.c[t + h] - e) - cost) / a for h in (3, 5, 10, 20)}})
    return pd.DataFrame(rows)


print(f"period: {period}   (cell = mean net move in ATR, t-stat clustered by date, n)")
print(f"{'lookback':>8} {'thr':>4} | " + " | ".join(f"{'hold ' + str(h):^24}" for h in (3, 5, 10, 20)))
keep = {}
for lb in (3, 5, 10):
    for thr in (1.5, 2.0, 2.5, 3.0):
        s = signals(lb, thr)
        keep[(lb, thr)] = s
        cells = []
        for h in (3, 5, 10, 20):
            c = clustered(s, f"h{h}")
            cells.append(f"{c['mean']:+.3f} t{c['t']:+.1f} n{c['n']:5d}")
        print(f"{lb:>8} {thr:>4} | " + " | ".join(f"{x:^24}" for x in cells))

s = keep[(5, 2.0)]
print("\nlookback 5, threshold 2.0, hold 5 - by year:")
for y, g in s.groupby("year"):
    c = clustered(g, "h5"); print(f"  {y}: {c['mean']:+.3f} t{c['t']:+.1f} n{c['n']}")
print("by instrument (hold 5): positive in", int((s.groupby('sym').h5.mean() > 0).sum()), "of", s.sym.nunique())
