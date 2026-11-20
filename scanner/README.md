# fxscan — forex swing-trade scanner

Scans the 28 major and cross pairs plus gold on the daily chart, lists the instruments
that completed a swing setup on the last closed bar, and replays the same rules over
history so the setups can be judged on evidence. It reads prices only: it never sends
orders.

```
fxscan/universe.py    the 29 instruments, pip sizes, assumed spreads
fxscan/data.py        price providers: Twelve Data, OANDA, or CSV files (e.g. MetaTrader exports)
fxscan/indicators.py  EMA, ATR, RSI, ADX
fxscan/zigzag.py      ZigZag pivots (same Depth/Deviation/Backstep algorithm as LineTouchEA)
fxscan/levels.py      monthly / weekly / daily support and resistance from those pivots
fxscan/strength.py    strength of each of the 8 currencies against the other seven
fxscan/setups.py      the two setups and the 0-100 confluence score
fxscan/scan.py        scan of the last completed bar + watchlist
fxscan/backtest.py    bar-by-bar replay of the same rules
tests/                pytest suite (runs offline)
```

## Run it

Needs Python 3.10+ with `numpy`, `pandas`, `requests` (`pytest` for the tests).

```
cd scanner
python -m fxscan backtest          # replay the rules over ~10 years, writes out/backtest.md
python -m fxscan scan              # today's setups, writes out/scan.md and out/scan.json
python -m pytest -q tests
```

Prices come from one of three sources:

* **Twelve Data** (default). Needs an API key in `TWELVEDATA_API_KEY`; the free plan is
  enough. Downloads are paced to its 8 requests a minute, so a first full run takes about
  four minutes; responses are cached in `.cache/` (`--cache-minutes`).
* **OANDA**: `--provider oanda` with a practice-account personal access token in
  `OANDA_API_TOKEN` (`--oanda-account live` for a live-account token). Only the candles
  endpoint is called. This provider has been tested against recorded responses only.
* **CSV files**: `--csv-dir <folder>` with one `<SYMBOL>_D1.csv` per instrument (and
  optionally `<SYMBOL>_H4.csv`), columns `time,open,high,low,close`. This lets the scan
  run on your own broker's bars exported from MetaTrader.

Data vendors build daily bars differently (session cut-off, which quotes count as the
high and low), so wicks and opens can differ from your broker's chart. Check a setup on
your own chart before acting on it.

Other options: `--symbols EURUSD,GBPJPY`, `--years 10`, `--no-h4`, `--out <folder>`, `-v`.

## What it looks for

Everything is decided on completed daily bars.

| Setup | Rule |
|---|---|
| **pullback** | Daily trend is established (close and EMA50 on the same side of EMA200, EMA50 still moving that way). Within the last 4 bars price dipped to the EMA20, and the last bar closed through the previous bar's high (low for shorts). Skipped when price is already stretched more than 1.5 ATR from the EMA20. Stop: beyond the 5-bar extreme plus 0.25 ATR. |
| **rejection** | A bar of at least 0.7 ATR wicks into a pivot level (within 0.3 ATR) and closes back off it, with the rejection wick at least 45% of the bar. Not taken against a daily trend with ADX above 25. Stop: beyond the wick plus 0.25 ATR. |

Both use a target of 2R, and a signal is dropped when the stop would be closer than
0.7 ATR or wider than 3 ATR.

**Levels** are ZigZag pivots (depth 12, backstep 3; the newest, still-moving pivot is
skipped, as in LineTouchEA): the last 8 on the monthly and weekly charts (grade A) and on
the daily chart (grade B). Levels closer than 0.25 ATR merge.

**Currency strength** is each pair's 20-day move divided by its ATR, averaged per currency
over the seven pairs it appears in. A setup's differential is base minus quote.

**Score (0-100)** adds up confluence: 20-week trend agrees (20), currency strength
(up to 20), a level behind the trade (A 20 / B 12), room to the target (up to 15), ADX
for pullbacks (10), RSI not stretched (5), stop no wider than 1.5 ATR (10). It is a
heuristic. The backtest breaks results down by score bucket so you can see whether it
carried any information on your data; do not assume it does.

The scan also prints a **watchlist** (trending pairs sitting in the pullback zone, with
the close that would trigger them) and, for each setup, the levels near price as a
ready-made `InpManualLevels` string for LineTouchEA. With a provider that has 4-hour
bars, each setup gets a timing note on whether the H4 chart has turned.

## How the backtest replays trades

* A signal on bar *t* is entered at the open of bar *t+1*; it is skipped when that open
  is more than half the risk distance from the signal bar's close.
* If one bar contains both stop and target, the stop is taken. A gap through the stop
  exits at the open.
* Trades still open after 20 bars close at that bar's close.
* One position per instrument. The assumed spread in `universe.py` is charged once per
  trade. Swaps, commission and slippage are not modelled.
* Results are in R (multiples of initial risk) with the standard error of the average,
  split by setup, score bucket, side, year and instrument.

`detect()` only reads bars up to the signal bar; `tests/test_fxscan.py` checks that
truncating the history does not change any signal. On driftless random-walk data the
replay comes out at about zero expectancy, which is what a leak-free replay should show.

Limits worth knowing: the spreads are assumptions, positions on correlated pairs are
counted as independent trades, and one pass over one history says nothing certain about
the future.
