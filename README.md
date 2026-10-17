# LineTouchEA — trade the lines on your chart (MetaTrader 5)

LineTouchEA is an MQL5 Expert Advisor that executes orders where price reacts at the
levels you see on the chart: the horizontal support/resistance lines, the sloped
trend lines and the value-area levels (DVAH / DPOC / DVAL, PDVAH / PDPOC / PDVAL).
Every place circled on the XAUUSD H1 chart that started this project is a wick
touching one of those lines; that touch is the EA's signal.

```
MQL5/Experts/LineTouchEA.mq5                         the Expert Advisor (single file)
MQL5/Presets/LineTouchEA_XAUUSD_H1_chart_lines.set   preset: trade the lines already on the chart
MQL5/Presets/LineTouchEA_XAUUSD_H1_builtin.set       preset: self-contained levels (for backtesting)
tools/mqlcheck/                                      g++-based syntax check used while developing
```

## Install

1. Copy `MQL5/Experts/LineTouchEA.mq5` into `<terminal data folder>\MQL5\Experts\`.
2. Open it in MetaEditor and press **Compile** (F7). The EA needs only the standard
   `Trade\Trade.mqh` library that ships with MetaTrader 5.
3. For level source 2 (value-area buffers) the compiled `ValueAreaLevels.ex5` must be in
   `MQL5\Indicators\` (or a sub-folder; then set `InpVAL_IndicatorName` to the relative
   path, e.g. `MyStuff\ValueAreaLevels`).
4. Drag the EA onto the chart that shows your lines. Allow algo trading (the
   "Algo Trading" button and the EA's *Allow Algo Trading* box).

## Where the levels come from

The EA builds one list of levels on every tick (at most once per second by default)
from four optional sources and merges levels closer than `InpMergeDistancePoints`.

| # | Source | Inputs | Notes |
|---|--------|--------|-------|
| 1 | **Lines on the chart** — every `OBJ_HLINE` and `OBJ_TREND` object, drawn by hand or by an indicator | `InpObjUse*`, `InpObjIncludePrefixes`, `InpObjExcludePrefixes`, color filter | This is what reads U_MTF_SRTrend's `SR_n` lines and `Trend_H4_Up`-style trend lines, and any line you draw yourself. A trend line that is not a right ray is only used while price is between its anchors; a sloped line's value is interpolated by bar index, exactly as the chart draws it. |
| 2 | **ValueAreaLevels buffers** read through `iCustom` | `InpVAL_*` | Loads a silent instance of your `ValueAreaLevels` indicator (`InpDrawObjects=false`) and reads buffers 0..8. When this is on, the `VAL_` chart segments are skipped so nothing is counted twice. Works in the Strategy Tester. |
| 3 | **Built-in multi-timeframe ZigZag** (port of the U_MTF_SRTrend1 engine) | `InpSR_*`, `InpTL_*` | Classic ZigZag per timeframe (default MN1/W1/D1/H4/H1 on an H1 chart, like the original), S/R = the last 8 pivots per timeframe (skipping the newest), one descending and one ascending trend line per timeframe through the two most recent qualifying peaks / troughs. Can draw its lines on the chart (`InpSR_Draw`). Works in the Strategy Tester. |
| 4 | **Manual** | `InpManualLevels`, `InpManualTrendLines` | `4343.31;4272.32` and `2026.10.02 00:00|4225.0|2026.10.09 08:00|4220.5;...` |

Objects created by the EA itself (prefix `LTEA_`) are never read back as levels.

## How a trade happens

1. **Role.** A level below price (by more than the zone) is *support*, above price it is
   *resistance*. Inside the zone the last role is kept. Until price has been clearly on
   one side, the level has no role and cannot trade.
2. **Zone.** `InpTouchZonePoints` around the level (200 points = $2.00 on 2-digit gold),
   optionally widened to `ATR x InpZoneATRFraction`.
3. **Entry mode** (`InpEntryMode`):
   * **Touch** (default): the moment Bid enters the zone from the correct side the EA
     sends a market order — buy at support, sell at resistance. This is the mode that
     trades the wick touches on the chart.
   * **Confirm close**: waits for the signal bar to close. The bar must have touched the
     zone and closed back on the original side; `InpMinRejectionRatio` demands that the
     close sits in the top (support) / bottom (resistance) part of the bar. Entry at the
     next bar's open. Safer, later.
   * **Pending**: keeps a buy-limit (support) / sell-limit (resistance) order resting
     `InpPendingOffsetPoints` in front of each armed level, re-priced every bar for sloped
     lines, deleted after `InpPendingExpiryBars`.
4. **Direction mode** (`InpDirectionMode`): *Bounce* trades the reaction off the level;
   *Breakout* trades the close (or intrabar move) through the level by
   `InpBreakoutBufferPoints` — sell below support, buy above resistance (pending mode then
   uses stop orders).
5. **Arming.** After a signal the level is *used* until price has moved
   `zone + InpRearmPoints` away from it and `InpCooldownBars` bars have passed. A touch
   that could not be traded (spread, caps, filters) also marks the level used, so the EA
   never hammers a level on every tick. `InpMaxTradesPerLevel` can cap a level for good.
6. **Caps and filters.** One new trade per bar, `InpMaxOpenPositions`, one position per
   level, `InpMinEntrySpacingPoints` from existing same-direction entries, opposite-position
   policy (skip / close first / hedge), max spread, trading hours, Friday cut-off, max
   trades per day, daily loss stop (`InpMaxDailyLossPercent`, realized + floating), optional
   moving-average trend filter.

### Exits

* **Stop-loss**: beyond the level + `InpSLBufferPoints` (default), fixed points, or an ATR
  multiple. The broker's minimum stop distance is enforced. `InpMaxSLPoints` skips trades
  whose stop would be wider than you accept.
* **Take-profit**: the next level in the trade direction minus `InpTPLevelBufferPoints`
  (default; falls back to `InpTPRR` x risk when no level is at least `InpTPMinPoints`
  away), or an R multiple, or fixed points, or none.
* Optional break-even (`InpBreakEvenTriggerPoints`) and trailing stop (`InpTrailingStartPoints`).
* **Lot size**: fixed, or risk `InpRiskPercent` of balance over the stop distance using the
  symbol's tick value; normalized to the volume step; free margin is checked first.

### Worked example (defaults, gold at 2 digits)

Support line at 4100.00, price above it. Bid falls to 4102.00 (inside the $2 zone) →
market buy at the Ask. Stop = 4100.00 − $3.00 = 4097.00. The next level above is
DVAL 4130.20, so the take-profit is 4129.20. Risk 1 % of a $10,000 account = $100 over a
$5.30 stop → 0.18 lots (1 lot of XAUUSD moves $1 per point). The level is now *used*; it
re-arms once price is more than $4 away from it and 3 bars have passed.

## Dashboard and markers

The chart comment shows mode, zone, spread, ATR, whether trading is allowed, positions,
today's trade count and P/L, and the nearest levels with their role (S / R / ?), distance
in points, state (ARMED, used, cooldown, wait side, order #...) and source. Entry arrows
are drawn at every fill. All EA objects use the `LTEA_` prefix and are removed when the
EA is taken off the chart (`InpDeleteObjectsOnExit`).

## Backtesting

* The Strategy Tester has no chart objects unless you run it in visual mode and load a
  template with the lines. For repeatable tests use the
  `LineTouchEA_XAUUSD_H1_builtin.set` preset: ValueAreaLevels buffers + built-in ZigZag
  levels, chart lines off.
* Use *Every tick* or *Every tick based on real ticks*. Touch and Pending modes need
  intrabar prices; *Open prices only* makes them meaningless.
* Levels from sources 2–4 are recomputed from history, so a backtest will not reproduce
  the exact lines your live indicator drew in the past.

## Presets

* `LineTouchEA_XAUUSD_H1_chart_lines.set` — the live setup for the chart in the
  screenshot: chart lines + value-area buffers, Touch / Bounce, 1 % risk, stop beyond the
  level, take-profit at the next level.
* `LineTouchEA_XAUUSD_H1_builtin.set` — the same trading rules with self-contained levels.

Load a preset through the *Load* button of the EA's input dialog.

## Notes and limits

* Positions and pending orders are tagged with a short hash of their level in the order
  comment (`LT|a1b2c3d4`) and in memory, so the EA finds them again after a restart. If a
  broker strips order comments, per-level limits only hold while the EA stays attached.
* On netting accounts a signal against an open position is skipped by default
  (`InpOppositeMode`), because a market order in the other direction would reduce or
  reverse the position.
* The built-in ZigZag is a faithful port of the U_MTF_SRTrend1 algorithm (classic
  Depth / Deviation / Backstep ZigZag), but the original indicator effectively
  recalculated only the last ~100 bars per timeframe after its first tick; the port uses a
  configurable lookback (`InpSR_LookbackBars`), so line sets can differ slightly.
* The EA was written and reviewed without a MetaEditor at hand. It was type-checked
  with the harness in `tools/mqlcheck`, which fakes the MQL5 API with C++ headers; compile
  it in MetaEditor before use and read the Experts log on the first run.

## Inputs reference

| Group | Input | Default | Meaning |
|-------|-------|---------|---------|
| Chart lines | `InpObjUseHLines` / `InpObjUseTrendLines` | true / true | read horizontal / trend line objects |
| | `InpObjIncludePrefixes` | (empty) | only object names starting with one of these (`a;b;c`) |
| | `InpObjExcludePrefixes` | (empty) | skip names starting with one of these |
| | `InpObjSkipHidden` | false | skip objects hidden from the object list |
| | `InpObjColorFilter` + `InpObjColor1..4` | Off | only / all but the listed colors |
| | `InpTrendPriceMethod` | Bar index | how a sloped line's value is computed |
| | `InpObjTreatAllAsRays` | false | extend every trend line to the right |
| | `InpObjRescanSeconds` | 1 | how often the chart objects are re-read |
| ValueAreaLevels | `InpVAL_Enable` | false | read the indicator's buffers |
| | `InpVAL_IndicatorName` | ValueAreaLevels | indicator path under MQL5\Indicators |
| | `InpVAL_Use*` | D* and PD* on, F* off | which of the nine levels to trade |
| | `InpVAL_ProfilePeriod` … `InpVAL_ForecastSessions` | as the indicator | passed straight through to the indicator |
| | `InpVAL_ExcludeObjects` | true | skip the `VAL_` chart segments when buffers are read |
| Built-in ZigZag | `InpSR_Enable` | false | compute MTF ZigZag S/R and trend lines |
| | `InpSR_UseSRLines` / `InpSR_UseTrendLines` | true / true | use pivots / trend lines |
| | `InpSR_Timeframes` | AUTO | AUTO = original scheme by chart period, or `D1;H4;H1` |
| | `InpSR_Depth/Deviation/Backstep` | 12 / 6 / 3 | ZigZag for S/R pivots |
| | `InpTL_Depth/Deviation/Backstep` | 9 / 0 / 3 | ZigZag for trend lines |
| | `InpSR_MaxPerTF` | 8 | pivots kept per timeframe |
| | `InpSR_FilterPoints` | 0 | only pivots within N points of price |
| | `InpSR_LookbackBars` | 1000 | bars analysed per timeframe |
| | `InpSR_Draw` | true | draw the computed lines |
| Manual | `InpManualLevels` | (empty) | `price;price;...` |
| | `InpManualTrendLines` | (empty) | `t1\|p1\|t2\|p2;...` |
| Levels | `InpMergeDistancePoints` | 50 | merge levels closer than this |
| Signals | `InpSignalTF` | Current | timeframe of the signal bars |
| | `InpEntryMode` | Touch | Touch / Confirm close / Pending |
| | `InpDirectionMode` | Bounce | Bounce / Breakout |
| | `InpTradePermit` | Both | Both / Buy only / Sell only |
| | `InpTouchZonePoints` | 200 | zone around the level |
| | `InpZoneATRFraction` | 0 | widen the zone to ATR x fraction |
| | `InpATRPeriod` | 14 | ATR period |
| | `InpMinRejectionRatio` | 0.5 | Confirm mode: close position inside the bar range |
| | `InpBreakoutBufferPoints` | 100 | Breakout: distance through the level |
| | `InpRearmPoints` | 200 | re-arm distance outside the zone |
| | `InpCooldownBars` | 3 | bars between signals on one level |
| | `InpMaxTradesPerLevel` | 0 | lifetime cap per level (0 = none) |
| | `InpMaxPositionsPerLevel` | 1 | open positions per level |
| | `InpMaxOpenPositions` | 2 | open positions in total |
| | `InpMinEntrySpacingPoints` | 300 | distance from existing same-direction entries |
| | `InpOppositeMode` | Skip | Skip / Close first / Hedge |
| | `InpOneSignalPerBar` | true | at most one new trade per bar |
| Pending | `InpPendingOffsetPoints` | 20 | order price offset from the level |
| | `InpPendingExpiryBars` | 24 | order lifetime in bars (0 = GTC) |
| | `InpPendingMinDistancePoints` | 150 | do not place closer than this to price |
| | `InpPendingDeleteOrphans` | true | delete EA orders that match no level |
| Filters | `InpMaxSpreadPoints` | 350 | max spread (0 = off) |
| | `InpUseTimeFilter`, `InpStartHour`, `InpEndHour` | off, 1, 23 | trading hours, server time |
| | `InpFridayStopHour` | 0 | no new trades on Friday from this hour |
| | `InpMaxTradesPerDay` | 0 | daily trade cap |
| | `InpMaxDailyLossPercent` | 0 | daily loss stop |
| | `InpUseMAFilter`, `InpMAPeriod`, `InpMAMethod`, `InpMATF` | off, 200, EMA, Current | trend filter |
| Risk | `InpLotMode` | Risk percent | Fixed / Risk percent |
| | `InpFixedLot` / `InpRiskPercent` | 0.01 / 1.0 | |
| | `InpAllowMinLotOverRisk` | false | trade the minimum lot even if it exceeds the risk |
| | `InpSLMode` | Beyond level | Beyond level / Fixed / ATR |
| | `InpSLBufferPoints` / `InpSLFixedPoints` / `InpSLATRMult` | 300 / 800 / 1.5 | |
| | `InpMaxSLPoints` | 1500 | skip wider stops (0 = off) |
| | `InpTPMode` | Next level | Next level / R multiple / Fixed / None |
| | `InpTPRR` / `InpTPFixedPoints` | 1.5 / 1200 | |
| | `InpTPLevelBufferPoints` / `InpTPMinPoints` | 100 / 400 | next-level take-profit |
| | `InpBreakEvenTriggerPoints` / `InpBreakEvenLockPoints` | 0 / 20 | break-even |
| | `InpTrailingStartPoints` / `InpTrailingStopPoints` / `InpTrailingStepPoints` | 0 / 500 / 50 | trailing stop |
| Execution | `InpMagic` | 20261017 | magic number |
| | `InpDeviationPoints` | 50 | max slippage |
| | `InpTradeComment` | LT | comment prefix |
| Display | `InpShowDashboard`, `InpDashboardLevels` | true, 12 | chart comment |
| | `InpDrawMarkers` | true | entry arrows |
| | `InpDeleteObjectsOnExit` | true | remove `LTEA_` objects on removal |
| | `InpAlerts`, `InpPushNotifications` | false | notifications |
| | `InpLogLevel` | Normal | Errors / Normal / Verbose |
