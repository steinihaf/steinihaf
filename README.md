# LineTouchEA — trade the lines on your chart (MetaTrader 5)

LineTouchEA is an MQL5 Expert Advisor that executes orders where price reacts at the
levels you see on the chart: the horizontal support/resistance lines, the sloped trend
lines and the value-area levels (DVAH / DPOC / DVAL, PDVAH / PDPOC / PDVAL). Every place
circled on the XAUUSD H1 chart that started this project is a wick touching one of those
lines; that touch is the EA's signal.

```
MQL5/Experts/LineTouchEA.mq5                         the Expert Advisor (single file)
MQL5/Presets/LineTouchEA_XAUUSD_H1_chart_lines.set   preset: trade the lines already on the chart
MQL5/Presets/LineTouchEA_XAUUSD_H1_builtin.set       preset: self-contained levels (for backtesting)
tools/gen_presets.py                                 regenerates the presets from the EA's inputs
tools/mqlcheck/                                      g++-based syntax check used while developing
```

## Install

1. Copy `MQL5/Experts/LineTouchEA.mq5` into `<terminal data folder>\MQL5\Experts\`.
2. Open it in MetaEditor and press **Compile** (F7). The EA needs only the standard
   `Trade\Trade.mqh` library that ships with MetaTrader 5.
3. For level source 2 (value-area buffers) the compiled `ValueAreaLevels.ex5` must be in
   `MQL5\Indicators\`. The EA declares `#property tester_indicator "ValueAreaLevels.ex5"`
   so the Strategy Tester can load it; if you do not have that indicator, delete that line
   before compiling (and keep `InpVAL_Enable` off).
4. Drag the EA onto the chart that shows your lines and allow algo trading (the
   "Algo Trading" button and the EA's *Allow Algo Trading* box).
5. Load a preset with the *Load* button of the input dialog. For a first week, set
   `InpTradeMode` to *Signal only*: the EA then draws arrows and alerts instead of sending
   orders (algo trading may stay disabled), never touches existing orders, and the
   dashboard shows why signals were skipped.

## Where the levels come from

The EA builds one list of levels on every tick (at most once per second by default) from
four optional sources and merges levels closer than `InpMergeDistancePoints`.

| # | Source | Inputs | Notes |
|---|--------|--------|-------|
| 1 | **Lines on the chart** — every `OBJ_HLINE` and `OBJ_TREND` object, drawn by hand or by an indicator | `InpObjUse*`, `InpObjIncludePrefixes`, `InpObjExcludePrefixes`, color filter | Reads U_MTF_SRTrend's `SR_n` lines and `Trend_H4_Up`-style trend lines, and any line you draw yourself. A trend line that is not a right ray is only used while price is between its anchors; a sloped line's value is interpolated by bar index, exactly as the chart draws it. Grade A. |
| 2 | **ValueAreaLevels buffers** read through `iCustom` | `InpVAL_*` | Loads a silent instance of your `ValueAreaLevels` indicator (`InpDrawObjects=false`) and reads buffers 0..8. When this is on, the `VAL_` chart segments are skipped so nothing is counted twice. PDVAH/PDPOC/PDVAL are grade A; the developing and forecast levels are grade C and the developing ones are targets only for the first `InpVAL_DevelopingMinBars` bars of a session. Works in the Strategy Tester. |
| 3 | **Built-in multi-timeframe ZigZag** (port of the U_MTF_SRTrend1 engine) | `InpSR_*`, `InpTL_*` | Classic ZigZag per timeframe (default MN1/W1/D1/H4/H1 on an H1 chart, like the original), S/R = the last 8 pivots per timeframe (skipping the newest), one descending and one ascending trend line per timeframe through the two most recent qualifying peaks / troughs. MN1/W1/D1 pivots are grade A, H4 is B, H1 and faster are C; D1/H4 trend lines are B. Can draw its lines (`InpSR_Draw`). Works in the Strategy Tester. |
| 4 | **Manual** | `InpManualLevels`, `InpManualTrendLines` | `4343.31;4272.32` and `2026.10.02 00:00|4225.0|2026.10.09 08:00|4220.5;...`. Grade A. |

Objects created by the EA itself (prefix `LTEA_`) are never read back as levels. Sloped
lines are ignored when they are over-extended (`InpTL_MaxExtensionRatio` x their anchor
span) or steeper than `InpTL_MaxSlopeATR` x ATR per bar. Levels whose grade is below
`InpMinEntryGrade` (default B) are **targets only**: they can be a take-profit but never
an entry. When levels merge, the cluster takes the best grade.

## How a trade happens

1. **Role.** Roles come from completed bar closes only. A level is *support* while
   closes stay above it and *resistance* while they stay below. It flips after
   `InpRoleConfirmBars` consecutive closes beyond the level by more than the break buffer
   (`max(InpBreakoutBufferPoints, ATR x InpBreakoutBufferATRFraction)`); a flip starts the
   cooldown. A level that flips `InpChopMaxFlips` times inside `InpChopWindowBars` bars is
   disabled until the window passes (chop filter).
2. **Zone.** `max(InpTouchZonePoints, ATR x InpZoneATRFraction)` around the level
   (defaults: 300 points = $3.00 on 2-digit gold, or a quarter of the H1 ATR).
3. **Entry mode** (`InpEntryMode`):
   * **Touch** (default): price must arrive from the role's side, enter the zone and then
     turn away from the level by `InpTouchRetreatPercent` of the zone (30 % by default;
     0 = trade the first tick in the zone). A touch that pierced the level by more than
     `InpMaxPenetrationATR` x ATR is not a touch. Market order at Ask / Bid.
   * **Confirm close**: the signal bar must have touched the zone, not pierced deeper than
     the penetration limit, and closed back on the original side with the close in the
     top (support) / bottom (resistance) `InpMinRejectionRatio` of its range. Entry at the
     next bar's open, skipped if that open is farther than `InpMaxEntryDistanceATR` x ATR
     from the level.
   * **Pending**: keeps a buy-limit (support) / sell-limit (resistance) order resting
     `InpPendingOffsetPoints` in front of each armed level while price is between
     `InpPendingMinDistancePoints` and `InpPendingMaxDistanceATR` x ATR away, re-priced
     every bar for sloped lines, deleted after `InpPendingExpiryBars`, when the role flips,
     or when a position cap or the opposite-position policy would be violated by a fill.
     Resting orders count against `InpMaxOpenPositions` and the entry spacing, and an
     order that expires or is deleted by hand marks its level *used*, so it is not placed
     again until the level has re-armed.
4. **Direction mode** (`InpDirectionMode`): *Bounce* trades the reaction off the level;
   *Breakout* trades the move through the level by the break buffer (sell below support,
   buy above resistance; pending mode then uses stop orders).
5. **Arming.** After a signal (or a role flip) the level is *used* until price has moved
   `zone + max(InpRearmPoints, ATR x InpRearmATRFraction)` away from it and
   `InpCooldownBars` bars have passed. A touch that could not be traded (spread, caps,
   filters) also marks the level used, so the EA never hammers a level on every tick.
   `InpMaxTradesPerLevel` caps a level for good; `InpMaxLossesPerLevelDay` (default 1)
   disables a level for the rest of the day after it produced a losing trade at that price.
6. **Caps and filters.** One new trade per bar, `InpMaxOpenPositions`, one position per
   level, `InpMinEntrySpacingPoints` from existing same-direction entries,
   opposite-position policy (skip / close first / hedge), max spread in points and as a
   percentage of the stop distance, trading hours, a rollover block around server
   midnight, Friday cut-off, max trades per day, daily loss stop (realized + floating),
   loss-streak stop, an impulse filter for bounces (skip when the last three bars moved
   more than `InpMaxImpulseATR` x ATR or the touching bar's range exceeds
   `InpMaxBarRangeATR` x ATR), an ADX regime filter (when H4 ADX is above
   `InpADXThreshold`, only trades in the trend direction) and an optional moving-average
   filter. The dashboard shows the reason of the last skipped signal.

### Exits

* **Stop-loss**: beyond the level by `max(InpSLBufferPoints, ATR x InpSLBufferATRFraction)`
  (default), fixed points, or an ATR multiple; never closer than `InpMinSLPoints`, never
  wider than `InpMaxSLPoints` (the trade is skipped instead). The broker's minimum stop
  distance is enforced.
* **Take-profit**: the next level in the trade direction minus `InpTPLevelBufferPoints`
  (default). The target must be at least `InpTPMinPoints` away and pay at least
  `InpTPMinRR` x the risk, otherwise the trade is skipped (`InpTPLowRRAction` can use the
  R-multiple target instead); a next-level target farther than `InpTPMaxRR` x risk is
  capped. Other modes: R multiple, fixed points, none.
* Optional break-even (`InpBreakEvenTriggerPoints`) and trailing stop (`InpTrailingStartPoints`).
* **Lot size**: fixed, or risk `InpRiskPercent` of balance over the stop distance using the
  symbol's tick value; normalized to the volume step; free margin is checked first.

### Worked example (defaults, gold at 2 digits, H1 ATR = $16)

Support line at 4100.00, price has been closing above it. Bid falls to 4102.00 (inside the
$4 zone), reaches 4100.60 and turns up to 4101.80: that is a retreat of $1.20, the required
30 % of the zone, so the EA buys at the Ask. Stop = 4100.00 − max($5, 0.5 x ATR) = 4092.00.
The next level above is DVAL 4130.20, so the take-profit is 4128.70; it pays 2.7 R, above
the 1.2 R minimum. Risk 0.5 % of a $10,000 account = $50 over a $10.00 stop → 0.05 lots
(1 lot of XAUUSD moves $1 per point). The level is now *used*; it re-arms once price is more
than $16 away from it and 3 bars have passed.

## Dashboard and markers

The chart comment shows mode, zone, spread, ATR, whether trading is allowed, the last
skipped signal and why, positions, today's trade count and P/L, and the nearest levels with
role (S / R / ?), grade (A / B / C), distance in points, state (ARMED, touching, used,
cooldown, chop, lost today, target only, wait side, order #...) and source. Entry arrows are
drawn at every fill. All EA objects use the `LTEA_` prefix and are removed when the EA is
taken off the chart (`InpDeleteObjectsOnExit`).

Level state (role, cooldown, trade and flip counts, with the level's price) is saved to
`MQL5\Files\LineTouchEA_<symbol>_<magic>.txt` and restored after a restart for levels that
are still at that price (`InpPersistState`; not in the tester; records older than seven days
are dropped). A level whose price jumps by more than the zone (a new session's value-area
line, a dragged line, an indicator name that now holds another pivot) starts over with a
clean state.

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
  screenshot: chart lines + value-area buffers, Touch / Bounce, 0.5 % risk, stop beyond the
  level, take-profit at the next level.
* `LineTouchEA_XAUUSD_H1_builtin.set` — the same trading rules with self-contained levels.

`python3 tools/gen_presets.py` rebuilds both files from the EA's input list after you
change the inputs.

## Notes and limits

* Positions and pending orders are tagged with a short hash of their level in the order
  comment (`LT|a1b2c3d4`) and in memory, so the EA finds them again after a restart. If a
  broker strips order comments, per-level limits only hold while the EA stays attached.
* On netting accounts a signal against an open position is skipped by default
  (`InpOppositeMode`), because a market order in the other direction would reduce or
  reverse the position.
* Run one instance per symbol, or give each instance its own `InpMagic`; two instances
  with the same magic on the same symbol would manage each other's orders.
* The built-in ZigZag is a faithful port of the U_MTF_SRTrend1 algorithm (classic
  Depth / Deviation / Backstep ZigZag), but the original indicator effectively
  recalculated only the last ~100 bars per timeframe after its first tick; the port uses a
  configurable lookback (`InpSR_LookbackBars`), so line sets can differ slightly.
* The EA was written and reviewed without a MetaEditor at hand. It was type-checked with
  the harness in `tools/mqlcheck`, which fakes the MQL5 API with C++ headers; compile it in
  MetaEditor before use and read the Experts log on the first run.

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
| ValueAreaLevels | `InpVAL_Enable` | false | read the indicator's buffers (presets: on) |
| | `InpVAL_IndicatorName` | ValueAreaLevels | indicator path under MQL5\Indicators |
| | `InpVAL_Use*` | D* and PD* on, F* off | which of the nine levels to use |
| | `InpVAL_ProfilePeriod` … `InpVAL_ForecastSessions` | as the indicator | passed straight through to the indicator |
| | `InpVAL_DevelopingMinBars` | 6 | developing levels are targets only for the first N bars of a session |
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
| Trend line validity | `InpTL_MaxExtensionRatio` | 2.0 | ignore a sloped line extended more than N x its anchor span (0 = off) |
| | `InpTL_MaxSlopeATR` | 0.4 | ignore a line steeper than N x ATR per bar (0 = off) |
| Manual | `InpManualLevels` | (empty) | `price;price;...` |
| | `InpManualTrendLines` | (empty) | `t1\|p1\|t2\|p2;...` |
| Levels | `InpMergeDistancePoints` | 100 | merge levels closer than this |
| | `InpMinEntryGrade` | B | lowest grade allowed for entries; lower grades are targets only |
| Signals | `InpSignalTF` | Current | timeframe of the signal bars |
| | `InpEntryMode` | Touch | Touch / Confirm close / Pending |
| | `InpDirectionMode` | Bounce | Bounce / Breakout |
| | `InpTradePermit` | Both | Both / Buy only / Sell only |
| | `InpTouchZonePoints` / `InpZoneATRFraction` | 300 / 0.25 | zone = max(points, ATR x fraction) |
| | `InpATRPeriod` | 14 | ATR period |
| | `InpTouchRetreatPercent` | 30 | Touch: wait until price turns away by N % of the zone |
| | `InpMaxPenetrationATR` | 0.5 | ignore touches that pierced the level by more than N x ATR |
| | `InpMinRejectionRatio` | 0.6 | Confirm: close position inside the bar range |
| | `InpMaxEntryDistanceATR` | 0.5 | Confirm: skip when the entry is farther from the level |
| | `InpBreakoutBufferPoints` / `InpBreakoutBufferATRFraction` | 200 / 0.15 | break buffer = max(points, ATR x fraction) |
| | `InpRoleConfirmBars` | 2 | closes beyond the buffer needed to flip a role |
| | `InpChopWindowBars` / `InpChopMaxFlips` | 24 / 2 | chop filter |
| | `InpRearmPoints` / `InpRearmATRFraction` | 800 / 0.75 | re-arm distance = max(points, ATR x fraction) |
| | `InpCooldownBars` | 3 | bars between signals on one level |
| | `InpMaxTradesPerLevel` | 0 | lifetime cap per level (0 = none) |
| | `InpMaxLossesPerLevelDay` | 1 | losing trades per level per day before it is disabled |
| | `InpMaxPositionsPerLevel` | 1 | open positions per level |
| | `InpMaxOpenPositions` | 2 | open positions in total |
| | `InpMinEntrySpacingPoints` | 300 | distance from existing same-direction entries |
| | `InpOppositeMode` | Skip | Skip / Close first / Hedge |
| | `InpOneSignalPerBar` | true | at most one new trade per bar |
| Pending | `InpPendingOffsetPoints` | 20 | order price offset from the level |
| | `InpPendingExpiryBars` | 6 | order lifetime in bars (0 = GTC) |
| | `InpPendingMinDistancePoints` | 150 | do not place closer than this to price |
| | `InpPendingMaxDistanceATR` | 1.5 | do not place farther than N x ATR from price |
| | `InpPendingDeleteOrphans` | true | delete EA orders that match no level |
| Filters | `InpMaxSpreadPoints` | 60 | max spread (0 = off) |
| | `InpMaxSpreadPercentOfSL` | 8 | max spread as % of the stop distance (0 = off) |
| | `InpRolloverSkipMinutes` | 20 | no entries within N minutes of server midnight |
| | `InpUseTimeFilter`, `InpStartHour`, `InpEndHour` | off, 1, 23 | trading hours, server time |
| | `InpFridayStopHour` | 0 | no new trades on Friday from this hour |
| | `InpMaxTradesPerDay` | 0 | daily trade cap |
| | `InpMaxDailyLossPercent` | 2.0 | daily loss stop (realized + floating) |
| | `InpMaxConsecutiveLosses` | 3 | loss-streak stop for the day |
| | `InpMaxImpulseATR` / `InpMaxBarRangeATR` | 1.5 / 2.0 | bounce impulse filters |
| | `InpUseADXFilter`, `InpADXTF`, `InpADXPeriod`, `InpADXThreshold` | on, H4, 14, 30 | ADX regime filter |
| | `InpUseMAFilter`, `InpMAPeriod`, `InpMAMethod`, `InpMATF` | off, 200, EMA, Current | moving-average filter |
| Risk | `InpLotMode` | Risk percent | Fixed / Risk percent |
| | `InpFixedLot` / `InpRiskPercent` | 0.01 / 0.5 | |
| | `InpAllowMinLotOverRisk` | false | trade the minimum lot even if it exceeds the risk |
| | `InpSLMode` | Beyond level | Beyond level / Fixed / ATR |
| | `InpSLBufferPoints` / `InpSLBufferATRFraction` | 500 / 0.5 | stop buffer beyond the level |
| | `InpSLFixedPoints` / `InpSLATRMult` | 800 / 1.5 | |
| | `InpMinSLPoints` / `InpMaxSLPoints` | 300 / 3000 | stop distance limits (max 0 = off) |
| | `InpTPMode` | Next level | Next level / R multiple / Fixed / None |
| | `InpTPRR` / `InpTPFixedPoints` | 1.5 / 1200 | |
| | `InpTPLevelBufferPoints` / `InpTPMinPoints` | 150 / 400 | next-level take-profit |
| | `InpTPMinRR` / `InpTPLowRRAction` / `InpTPMaxRR` | 1.2 / Skip / 3.0 | next-level reward rules |
| | `InpBreakEvenTriggerPoints` / `InpBreakEvenLockPoints` | 0 / 20 | break-even |
| | `InpTrailingStartPoints` / `InpTrailingStopPoints` / `InpTrailingStepPoints` | 0 / 500 / 50 | trailing stop |
| Execution | `InpTradeMode` | Live | Live / Signal only |
| | `InpMagic` | 20261017 | magic number |
| | `InpDeviationPoints` | 50 | max slippage |
| | `InpTradeComment` | LT | comment prefix |
| Display | `InpShowDashboard`, `InpDashboardLevels` | true, 12 | chart comment |
| | `InpDrawMarkers` | true | entry arrows |
| | `InpDeleteObjectsOnExit` | true | remove `LTEA_` objects on removal |
| | `InpPersistState` | true | save level state to a file |
| | `InpAlerts`, `InpPushNotifications` | false | notifications |
| | `InpLogLevel` | Normal | Errors / Normal / Verbose |
