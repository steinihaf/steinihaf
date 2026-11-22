# Rule research: what was tested and what survived

Data: Twelve Data daily bars, 28 FX pairs + gold. Rules were developed on bars up to
2022-12-31 only ("training"); 2023-01 to 2026-11 was kept aside ("holdout") and used
once, for one rule chosen in advance. Costs: the assumed spreads in `fxscan/universe.py`.
t-statistics treat each calendar day as one observation, because signals on the same day
across pairs share currencies. The mean shown is over all trades and the t-statistic is on
daily averages, so on near-zero results the two can differ in sign.

**Result: no rule tested shows a dependable edge. Nothing here should be traded as a
system.**

## 1. Do the ingredients predict direction? (`01_diagnose.py`, training years)

Forward move from the next open, in ATR, signed by the idea's direction, no costs.

| Idea | 5 bars | 10 bars | 20 bars |
|---|---|---|---|
| Daily trend direction (EMA50/200) | -0.005 (t -0.9) | -0.020 (t -1.1) | -0.059 (t -2.3) |
| 20-week side (close vs EMA100) | -0.014 (t -0.5) | -0.028 (t -1.6) | -0.066 (t -3.0) |
| 60-day momentum | -0.010 (t +0.8) | -0.033 (t -0.1) | -0.097 (t -2.3) |
| 250-day momentum | +0.004 (t +0.5) | +0.013 (t +0.5) | +0.036 (t +0.8) |
| Currency-strength differential | -0.002 (t +0.7) | -0.025 (t -0.2) | -0.050 (t -0.6) |
| Scanner pullback signals | -0.028 (t -0.1) | -0.078 (t -0.5) | -0.105 (t -0.9) |
| Scanner rejection signals | -0.062 (t -2.2) | -0.024 (t -1.9) | -0.109 (t -2.1) |
| Fade a 5-day move larger than 2 ATR | +0.063 (t +2.1) | +0.086 (t +2.1) | +0.097 (t +1.4) |

Trend, momentum and currency strength did not predict direction; if anything price
leaned the other way over 20 bars. The scanner's own signals were slightly wrong-way.
The filters inside the signals (level grade, with/against trend, room to target, ADX)
did not separate good signals from bad.

## 2. Fading large moves (`02_fade_grid.py`, training years)

Twelve lookback/threshold combinations by four holding periods, net of spread. Results
ranged from -0.11 to +0.22 ATR with almost no cell beyond t = 2 and no plateau: the
+0.06 from section 1 does not hold up once the entry is defined precisely.

## 3. Channel breakouts and exits (`03_breakout_and_exits.py`, training years)

* Following a close beyond the 20 / 55 / 100-day channel lost in every cell
  (-0.03 to -0.51 ATR net).
* The scanner's 5,264 training signals were replayed under six exit schemes (1R, 2R and
  3R targets, wider stops, time exit, 3-ATR trailing stop). Every one came out between
  -0.01R and -0.08R per trade. Exits cannot rescue entries that carry no information.

## 4. The one rule taken to the holdout (`04_fade_breakout_holdout.py`)

Since breakouts reversed in training, one rule was fixed in advance: fade the first close
beyond the 100-day channel, exit after 10 bars or at a 3-ATR stop.

| Period | Trades | Mean R | t | Win rate | Total |
|---|---|---|---|---|---|
| Training 2017-2022 | 631 | -0.005 | +0.1 | 51% | -3.1R |
| Holdout 2023-2026 | 539 | +0.008 | +0.3 | 53% | +4.5R |

Zero in both periods once traded realistically (one position per instrument, stop,
spread). Neighbouring cells (55 / 150-day, 5 / 20-bar holds) are the same story.

## What this means

* Simple price-pattern rules on daily FX bars - trend pullbacks, level rejections,
  momentum, breakouts, fading extremes - did not beat costs on this data. This matches
  what is generally reported for liquid FX pairs.
* The scanner is still useful for what it measures: which pairs are trending, where the
  monthly / weekly / daily levels are, which currencies are strong. It is a watchlist,
  not a signal service, and its score is a count of confluence, not a win probability.
* About 45 cells were examined across these scripts. With that many looks, a few values
  near t = 2 are expected by chance; none was treated as a finding.

## Not tested (would need other data)

* Carry (interest-rate differentials) - the best documented FX return source.
* Intraday behaviour around levels on a broker's own bars, which is what LineTouchEA
  trades. The MetaTrader Strategy Tester is the right tool for that.
* Event-driven rules (central-bank days, data releases) and positioning (COT).
