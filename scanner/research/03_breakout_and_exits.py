"""Two more pre-stated checks on the TRAINING years.

A. Channel breakouts: does a close beyond the N-day high/low continue (trend following)?
B. Exits: can a different stop / target turn the scanner's existing signals positive?
   (If entries carry no directional information, no exit rule should rescue them.)
"""
import numpy as np
import pandas as pd

from common import TRAIN_END, clustered, load
from fxscan.setups import WARMUP, detect

u = load()

print("A. close beyond the prior N-day channel, follow the break; net move in ATR")
for n_ch in (20, 55, 100):
    rows = []
    for sym, p in u.pairs.items():
        hh = pd.Series(p.h).rolling(n_ch).max().shift(1).to_numpy()
        ll = pd.Series(p.l).rolling(n_ch).min().shift(1).to_numpy()
        for t in range(WARMUP, len(p) - 41):
            if p.dates[t] > TRAIN_END:
                continue
            up, dn = p.c[t] > hh[t], p.c[t] < ll[t]
            was = p.c[t - 1] > hh[t - 1] or p.c[t - 1] < ll[t - 1]
            if not (up or dn) or was:
                continue
            d = 1 if up else -1
            a, e = p.atr[t], p.o[t + 1]
            if abs(e - p.c[t]) > 0.5 * a:
                continue
            rows.append({"date": p.dates[t], **{f"h{h}": (d * (p.c[t + h] - e) - p.ins.spread) / a
                                                  for h in (5, 10, 20, 40)}})
    s = pd.DataFrame(rows)
    print(f"  {n_ch:3d}-day: " + "  ".join(
        f"hold {h}: {clustered(s, f'h{h}')['mean']:+.3f} (t {clustered(s, f'h{h}')['t']:+.1f})"
        for h in (5, 10, 20, 40)) + f"  n={len(s)}")


def simulate(p, t, d, stop_dist, target_r, max_bars, trail_atr=None):
    """R result of one trade entered at the next open. stop_dist in price units."""
    e = t + 1
    entry = p.o[e]
    stop = entry - d * stop_dist
    target = entry + d * target_r * stop_dist if target_r else None
    best = entry
    for i in range(e, min(len(p), e + max_bars)):
        o, h, l = p.o[i], p.h[i], p.l[i]
        if i > e and (o - stop) * d <= 0:
            return ((o - entry) * d - p.ins.spread) / stop_dist
        if (l <= stop) if d > 0 else (h >= stop):
            return ((stop - entry) * d - p.ins.spread) / stop_dist
        if target is not None and ((h >= target) if d > 0 else (l <= target)):
            return (target_r * stop_dist - p.ins.spread) / stop_dist
        if trail_atr:
            best = max(best, h) if d > 0 else min(best, l)
            new = best - d * trail_atr * p.atr[i]
            stop = max(stop, new) if d > 0 else min(stop, new)
    i = min(len(p), e + max_bars) - 1
    return ((p.c[i] - entry) * d - p.ins.spread) / stop_dist


sig = []
for sym, p in u.pairs.items():
    for t in range(WARMUP, len(p) - 41):
        if p.dates[t] > TRAIN_END:
            continue
        s = detect(p, t)
        if s and abs(p.o[t + 1] - p.c[t]) <= 0.5 * abs(s.entry - s.stop):
            sig.append((p, t, s))
print(f"\nB. the scanner's {len(sig)} training signals under different exits; mean R (t)")
variants = {
    "current: signal stop, 2R target, 20 bars": dict(mult=1.0, target_r=2.0, max_bars=20),
    "signal stop, 1R target": dict(mult=1.0, target_r=1.0, max_bars=20),
    "signal stop, 3R target, 40 bars": dict(mult=1.0, target_r=3.0, max_bars=40),
    "stop x1.5, 2R target": dict(mult=1.5, target_r=2.0, max_bars=30),
    "stop x2, no target, exit after 10 bars": dict(mult=2.0, target_r=None, max_bars=10),
    "signal stop, no target, 3-ATR trail, 40 bars": dict(mult=1.0, target_r=None, max_bars=40, trail=3.0),
}
for name, v in variants.items():
    for kind in ("pullback", "rejection"):
        rows = [{"date": p.dates[t],
                 "r": simulate(p, t, s.direction, abs(s.entry - s.stop) * v["mult"], v["target_r"],
                               v["max_bars"], v.get("trail"))}
                for p, t, s in sig if s.kind == kind]
        c = clustered(pd.DataFrame(rows), "r")
        print(f"  {name:46s} {kind:9s} {c['mean']:+.3f} (t {c['t']:+.1f}) n={c['n']}")
