"""Does any ingredient of the scanner's rules predict direction? (training period only)

For every daily bar of every instrument: the forward move over 5 / 10 / 20 bars from the
next open, in units of that bar's ATR, signed by a candidate direction. No stops, no
targets, no costs - this isolates whether the entry idea has information at all.
"""
import numpy as np
import pandas as pd

from common import TRAIN_END, clustered, load
from fxscan.setups import WARMUP, daily_trend, detect

u = load()
rows = []
for sym, p in u.pairs.items():
    n = len(p)
    for t in range(WARMUP, n - 21):
        if p.dates[t] > TRAIN_END or np.isnan(p.atr[t]):
            continue
        a = p.atr[t]
        e = p.o[t + 1]
        s = detect(p, t)
        mom60 = np.sign(p.c[t] - p.c[t - 60])
        mom250 = np.sign(p.c[t] - p.c[t - 250])
        rows.append({
            "sym": sym, "date": p.dates[t],
            "f5": (p.c[t + 5] - e) / a, "f10": (p.c[t + 10] - e) / a, "f20": (p.c[t + 20] - e) / a,
            "trend": daily_trend(p, t), "sd": p.strength_diff[t],
            "wk": np.sign(p.c[t] - p.ema100[t]), "mom60": mom60, "mom250": mom250,
            "rsi": p.rsi[t], "adx": p.adx[t],
            "ret5": (p.c[t] - p.c[t - 5]) / a,
            "kind": s.kind if s else "", "dir": s.direction if s else 0,
            "score": s.score if s else -1, "room": (s.room_r if s and s.room_r is not None else 9) if s else np.nan,
            "grade": (s.level_grade or "-") if s else "",
        })
d = pd.DataFrame(rows)
d.to_pickle("/tmp/claude-0/-home-user-steinihaf/b0264438-61eb-56fe-9d03-c20ebc8a89e8/scratchpad/diag.pkl")
print("bars", len(d), d.date.min().date(), d.date.max().date())


def show(name, sub, sign):
    out = []
    for h in ("f5", "f10", "f20"):
        x = sub.assign(v=sub[h] * sign)
        c = clustered(x, "v")
        out.append(f"{h}: {c['mean']:+.3f} (t {c['t']:+.1f})")
    print(f"{name:42s} n={len(sub):6d}  " + "  ".join(out))


print("\n-- unconditional directional ideas (all bars), forward move in ATR")
show("daily trend direction", d[d.trend != 0], d[d.trend != 0].trend)
show("20-week side (close vs EMA100)", d, d.wk)
show("60-day momentum sign", d, d.mom60)
show("250-day momentum sign", d, d.mom250)
fx = d.dropna(subset=["sd"])
show("strength diff sign (20d)", fx, np.sign(fx.sd))
show("strength diff |sd|>2", fx[fx.sd.abs() > 2], np.sign(fx[fx.sd.abs() > 2].sd))
show("FADE 5-day move > 2 ATR", d[d.ret5.abs() > 2], -np.sign(d[d.ret5.abs() > 2].ret5))
show("FADE rsi<30 / >70", d[(d.rsi < 30) | (d.rsi > 70)], np.where(d[(d.rsi < 30) | (d.rsi > 70)].rsi < 30, 1, -1))
t_ = d[d.trend != 0]
dip = t_[(t_.ret5 * t_.trend) < -1.5]
show("trend + 5-day dip >1.5 ATR against", dip, dip.trend)

print("\n-- the scanner's own signals")
s = d[d.kind != ""]
for k in ("pullback", "rejection"):
    show(k, s[s.kind == k], s[s.kind == k].dir)
r = s[s.kind == "rejection"]
show("rejection grade A", r[r.grade == "A"], r[r.grade == "A"].dir)
show("rejection grade B", r[r.grade == "B"], r[r.grade == "B"].dir)
show("rejection with trend", r[r.dir == r.trend], r[r.dir == r.trend].dir)
show("rejection against trend", r[r.dir == -r.trend], r[r.dir == -r.trend].dir)
show("rejection no trend", r[r.trend == 0], r[r.trend == 0].dir)
show("rejection wk agrees", r[r.dir == r.wk], r[r.dir == r.wk].dir)
show("rejection wk disagrees", r[r.dir != r.wk], r[r.dir != r.wk].dir)
show("rejection room>=2R", r[r.room >= 2], r[r.room >= 2].dir)
show("rejection room<1R", r[r.room < 1], r[r.room < 1].dir)
pb = s[s.kind == "pullback"]
show("pullback adx>=25", pb[pb.adx >= 25], pb[pb.adx >= 25].dir)
show("pullback adx<20", pb[pb.adx < 20], pb[pb.adx < 20].dir)
show("FADE all signals", s, -s.dir)
