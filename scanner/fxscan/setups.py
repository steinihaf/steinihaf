"""Swing setups on completed daily bars.

Two setups, both defined so they can be replayed bar by bar in the backtest:

* pullback  - an established daily trend pulls back to its EMA20 / EMA50 area and a bar
              closes back through the previous bar's extreme in the trend direction.
* rejection - a bar wicks into a monthly / weekly / daily pivot level and closes back off
              it with a long rejection wick (the daily-chart version of LineTouchEA's touch).

`detect(pd, t)` only looks at bars 0..t, so calling it at every t is a fair replay.
"""
from __future__ import annotations

from dataclasses import dataclass, field, asdict

import numpy as np
import pandas as pd

from . import indicators as ind
from .levels import Level, build_levels
from .universe import Instrument, instrument

WARMUP = 260           # bars needed before the first signal (EMA200 + slack)
ZONE_ATR = 0.30        # a level is "touched" within this many ATRs
MERGE_ATR = 0.25       # levels closer than this merge into one
STOP_BUFFER_ATR = 0.25
MIN_RISK_ATR, MAX_RISK_ATR = 0.7, 3.0
TARGET_R = 2.0


@dataclass
class PairData:
    """Daily bars of one instrument plus everything derived from them (all causal)."""
    ins: Instrument
    dates: pd.DatetimeIndex
    o: np.ndarray
    h: np.ndarray
    l: np.ndarray
    c: np.ndarray
    ema20: np.ndarray = field(repr=False, default=None)
    ema50: np.ndarray = field(repr=False, default=None)
    ema100: np.ndarray = field(repr=False, default=None)
    ema200: np.ndarray = field(repr=False, default=None)
    atr: np.ndarray = field(repr=False, default=None)
    rsi: np.ndarray = field(repr=False, default=None)
    adx: np.ndarray = field(repr=False, default=None)
    week_id: np.ndarray = field(repr=False, default=None)
    month_id: np.ndarray = field(repr=False, default=None)
    strength_diff: np.ndarray = field(repr=False, default=None)   # base - quote, NaN if n/a

    @classmethod
    def from_frame(cls, symbol: str, df: pd.DataFrame) -> "PairData":
        o, h, l, c = (df[k].to_numpy(dtype=float) for k in ("open", "high", "low", "close"))
        iso = df.index.isocalendar()
        pd_ = cls(instrument(symbol), df.index, o, h, l, c)
        pd_.ema20, pd_.ema50 = ind.ema(c, 20), ind.ema(c, 50)
        pd_.ema100, pd_.ema200 = ind.ema(c, 100), ind.ema(c, 200)
        pd_.atr, pd_.rsi, pd_.adx = ind.atr(h, l, c), ind.rsi(c), ind.adx(h, l, c)
        pd_.week_id = (iso["year"].to_numpy(dtype=int) * 100 + iso["week"].to_numpy(dtype=int))
        pd_.month_id = df.index.year.to_numpy() * 100 + df.index.month.to_numpy()
        pd_.strength_diff = np.full(len(c), np.nan)
        return pd_

    def __len__(self) -> int:
        return len(self.c)

    def levels_at(self, t: int) -> list[Level]:
        s = slice(0, t + 1)
        return build_levels(self.h[s], self.l[s], self.week_id[s], self.month_id[s],
                            merge_distance=MERGE_ATR * self.atr[t])


@dataclass
class Setup:
    symbol: str
    date: str               # date of the signal bar (the last completed daily bar)
    kind: str               # "pullback" | "rejection"
    direction: int          # +1 long, -1 short
    entry: float            # reference entry = close of the signal bar
    stop: float
    target: float
    risk_pips: float
    atr_pips: float
    score: int
    trend: str              # "up" | "down" | "none" (daily)
    weekly_aligned: bool
    strength_diff: float | None
    level: float | None     # the level the setup leans on, if any
    level_grade: str | None
    level_sources: str | None
    room_r: float | None    # distance to the nearest opposing level, in R (None = open air)
    adx: float
    rsi: float
    reasons: list[str] = field(default_factory=list)
    cautions: list[str] = field(default_factory=list)
    nearby_levels: list[float] = field(default_factory=list)
    h4_state: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)

    @property
    def side(self) -> str:
        return "long" if self.direction > 0 else "short"


def daily_trend(p: PairData, t: int) -> int:
    """+1 / -1 when price, EMA50 and EMA200 agree and EMA50 is still moving that way."""
    if t < 10 or np.isnan(p.ema200[t]):
        return 0
    c, e50, e200 = p.c[t], p.ema50[t], p.ema200[t]
    if c > e200 and e50 > e200 and e50 > p.ema50[t - 10]:
        return 1
    if c < e200 and e50 < e200 and e50 < p.ema50[t - 10]:
        return -1
    return 0


def _pullback(p: PairData, t: int, d: int) -> tuple[float, float] | None:
    """Trend-pullback trigger in direction d. Returns (stop, pullback extreme) or None."""
    atr = p.atr[t]
    if d > 0:
        ext = p.l[t - 3:t + 1].min()
        touched = ext <= p.ema20[t] + 0.1 * atr
        trigger = p.c[t] > p.h[t - 1] and p.c[t] > p.o[t]
        repeat = p.c[t - 1] > p.h[t - 2] and p.c[t - 1] > p.o[t - 1]
        stretched = p.c[t] - p.ema20[t] > 1.5 * atr
        broken = p.c[t] < p.ema50[t] - 0.5 * atr
        stop = p.l[t - 4:t + 1].min() - STOP_BUFFER_ATR * atr
    else:
        ext = p.h[t - 3:t + 1].max()
        touched = ext >= p.ema20[t] - 0.1 * atr
        trigger = p.c[t] < p.l[t - 1] and p.c[t] < p.o[t]
        repeat = p.c[t - 1] < p.l[t - 2] and p.c[t - 1] < p.o[t - 1]
        stretched = p.ema20[t] - p.c[t] > 1.5 * atr
        broken = p.c[t] > p.ema50[t] + 0.5 * atr
        stop = p.h[t - 4:t + 1].max() + STOP_BUFFER_ATR * atr
    if touched and trigger and not repeat and not stretched and not broken:
        return stop, ext
    return None


def _rejection(p: PairData, t: int, levels: list[Level]) -> tuple[int, float, Level] | None:
    """Wick rejection of a level. Returns (direction, stop, level) or None."""
    atr = p.atr[t]
    o, h, l, c = p.o[t], p.h[t], p.l[t], p.c[t]
    rng = h - l
    if rng < 0.7 * atr:
        return None
    zone = ZONE_ATR * atr
    prev_close = p.c[t - 1]
    body_low, body_high = min(o, c), max(o, c)
    best = None
    for lv in levels:
        # support: yesterday closed above it, today's low reached it, close back above
        if (prev_close > lv.price and l <= lv.price + zone and c > lv.price
                and (body_low - l) >= 0.45 * rng and c >= l + 0.5 * rng):
            cand = (1, l - STOP_BUFFER_ATR * atr, lv)
        elif (prev_close < lv.price and h >= lv.price - zone and c < lv.price
              and (h - body_high) >= 0.45 * rng and c <= h - 0.5 * rng):
            cand = (-1, h + STOP_BUFFER_ATR * atr, lv)
        else:
            continue
        if best is None or (cand[2].grade, abs(cand[2].price - c)) < (best[2].grade, abs(best[2].price - c)):
            best = cand
    return best


def detect(p: PairData, t: int) -> Setup | None:
    """The setup, if any, completed by daily bar t (uses bars 0..t only)."""
    if t < WARMUP or t >= len(p) or np.isnan(p.atr[t]) or np.isnan(p.adx[t]) or p.atr[t] <= 0:
        return None
    atr, c = p.atr[t], p.c[t]
    trend = daily_trend(p, t)
    kind = direction = stop = level = None
    levels: list[Level] | None = None

    if trend != 0:
        pb = _pullback(p, t, trend)
        if pb:
            kind, direction, stop = "pullback", trend, pb[0]
            levels = p.levels_at(t)
            ext = pb[1]
            near = [lv for lv in levels if abs(lv.price - ext) <= 0.5 * atr]
            if near:
                level = min(near, key=lambda lv: (lv.grade, abs(lv.price - ext)))
    if kind is None:
        # cheap pre-check before building levels: a long wick on a decent-sized bar
        rng = p.h[t] - p.l[t]
        lo_w = min(p.o[t], c) - p.l[t]
        hi_w = p.h[t] - max(p.o[t], c)
        if rng >= 0.7 * atr and max(lo_w, hi_w) >= 0.45 * rng:
            levels = p.levels_at(t)
            rj = _rejection(p, t, levels)
            if rj and not (rj[0] == -trend and p.adx[t] > 25):   # do not fade a strong trend
                kind, direction, stop, level = "rejection", rj[0], rj[1], rj[2]
    if kind is None:
        return None

    risk = (c - stop) * direction
    if not (MIN_RISK_ATR * atr <= risk <= MAX_RISK_ATR * atr):
        return None
    target = c + direction * TARGET_R * risk

    # room: nearest level in the way of the target (ignoring the level we lean on)
    ahead = [lv.price for lv in levels
             if (lv.price - c) * direction > 0.15 * atr and (level is None or lv is not level)]
    room_r = min(((lv - c) * direction / risk for lv in ahead), default=None)

    weekly = (c - p.ema100[t]) * direction > 0 and (p.ema100[t] - p.ema100[t - 20]) * direction > 0
    sd = p.strength_diff[t]
    sd_dir = None if np.isnan(sd) else float(sd * direction)

    score, reasons, cautions = _score(kind, direction, trend, weekly, sd_dir, level, room_r,
                                      p.adx[t], p.rsi[t], risk / atr)
    pip = p.ins.pip
    return Setup(
        symbol=p.ins.symbol, date=str(p.dates[t].date()), kind=kind, direction=direction,
        entry=round(c, p.ins.digits), stop=round(stop, p.ins.digits),
        target=round(target, p.ins.digits), risk_pips=round(risk / pip, 1),
        atr_pips=round(atr / pip, 1), score=score,
        trend={1: "up", -1: "down", 0: "none"}[trend], weekly_aligned=bool(weekly),
        strength_diff=None if sd_dir is None else round(sd_dir, 2),
        level=None if level is None else round(level.price, p.ins.digits),
        level_grade=None if level is None else level.grade,
        level_sources=None if level is None else "+".join(level.sources),
        room_r=None if room_r is None else round(room_r, 2),
        adx=round(float(p.adx[t]), 1), rsi=round(float(p.rsi[t]), 1),
        reasons=reasons, cautions=cautions,
        nearby_levels=[round(lv.price, p.ins.digits) for lv in levels
                       if abs(lv.price - c) <= 6 * atr],
    )


def _score(kind, direction, trend, weekly, sd_dir, level, room_r, adx, rsi, risk_atr):
    """Heuristic 0-100 confluence score. The backtest reports whether it carried information."""
    score, reasons, cautions = 0, [], []
    side = "long" if direction > 0 else "short"
    if kind == "pullback":
        reasons.append(f"daily {'up' if trend > 0 else 'down'}trend pulled back to the EMA20/50 area and turned")
    else:
        reasons.append(f"rejection wick off {'support' if direction > 0 else 'resistance'}")
    if weekly:
        score += 20; reasons.append("20-week trend agrees")
    else:
        cautions.append("20-week trend does not agree")
    if sd_dir is not None:
        if sd_dir >= 2.0:
            score += 20; reasons.append(f"currency strength strongly favours the {side} ({sd_dir:+.1f})")
        elif sd_dir >= 0.75:
            score += 12; reasons.append(f"currency strength favours the {side} ({sd_dir:+.1f})")
        elif sd_dir <= -0.75:
            cautions.append(f"currency strength is against the {side} ({sd_dir:+.1f})")
        else:
            score += 5
    if level is not None:
        score += 20 if level.grade == "A" else 12
        reasons.append(f"leans on a grade {level.grade} level ({'+'.join(level.sources)})")
    if room_r is None or room_r >= TARGET_R:
        score += 15; reasons.append("no level in the way before the 2R target")
    elif room_r >= 1.0:
        score += 7; cautions.append(f"a level sits {room_r:.1f}R away, before the target")
    else:
        cautions.append(f"a level sits only {room_r:.1f}R away")
    if kind == "pullback":
        if adx >= 20:
            score += 10; reasons.append(f"ADX {adx:.0f}: the trend has momentum")
        else:
            cautions.append(f"ADX {adx:.0f}: weak trend")
    else:
        score += 5
    if (direction > 0 and rsi < 70) or (direction < 0 and rsi > 30):
        score += 5
    else:
        cautions.append(f"RSI {rsi:.0f} is stretched")
    if risk_atr <= 1.5:
        score += 10
    else:
        cautions.append(f"wide stop ({risk_atr:.1f} ATR)")
    return min(score, 100), reasons, cautions
