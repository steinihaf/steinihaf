//+------------------------------------------------------------------+
//|                                                       MSB_EA.mq5 |
//| Multi-Session Breakout Expert Advisor.                           |
//|                                                                  |
//| Four sessions in one EA: ASIA, LONDON, NEW YORK and SYDNEY.      |
//| Each session works like the Asian Session Breakout EA (ASB_EA):  |
//| the session forms a high/low range; after it ends, the first     |
//| candle that closes outside that range is its breakout.           |
//|                                                                  |
//| Every session has its OWN block of settings: on/off, hours (in   |
//| Icelandic or broker server time), signal timeframe, entry style, |
//| risk % per trade, stop loss, take profit, break-even, trailing,  |
//| quality checks, OBV filter, Value Area filter and USDX filter    |
//| (dollar index alone, or confirmed by EURUSD and/or one more      |
//| symbol) - and its own magic number (InpMagic + 0/1/2/3 for Asia  |
//| / London / New York / Sydney), so the sessions never mix up      |
//| their ranges or trades.                                          |
//|                                                                  |
//| WICK-BREAK ENTRY (optional, off by default): a candle's wick     |
//| breaks a session level (the break candle); the NEXT candle must   |
//| push past that wick by a set % of the break candle's body.        |
//| Module A enters during that candle, the moment price gets there;  |
//| Module B waits for it to CLOSE there. The stop goes beyond the    |
//| confirming candle's own wick. See "Wick-break entry" inputs.      |
//|                                                                  |
//| CANDLE EXITS (optional, off by default): close a trade after a    |
//| set number of candles, and/or when a candle against the trade     |
//| closes with a body bigger than the candle before it.              |
//|                                                                  |
//| ONE FILE: needs no include folder and no indicator files.        |
//| NEW AND UNTESTED: Strategy Tester and demo first.                |
//+------------------------------------------------------------------+
#property copyright "Stein"
#property version   "1.12"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enums                                                             |
//+------------------------------------------------------------------+
enum ASB_EA_ENTRYMODE
  {
   EntryRetestLimit   = 0,   // Wait for a retest: real limit order at the level
   EntryBreakoutClose = 1    // Enter at market the moment the candle closes beyond the range
  };

enum ASB_EA_TIMEMODE
  {
   TimeIcelandic = 0,   // Session times are Icelandic time (GMT)
   TimeServer    = 1    // Session times are broker server time
  };

enum ASB_EA_TRAILMODE
  {
   TrailNone      = 0,   // No trailing stop
   TrailPips      = 1,   // Trail behind price by a fixed pip distance
   TrailStructure = 2    // Trail behind the last confirmed swing high/low
  };

enum ASB_VA_VOLTYPE
  {
   ASB_VOL_TICK = 0,   // Tick volume
   ASB_VOL_REAL = 1    // Real volume (falls back to tick when empty)
  };

enum ENUM_OBV_MODE
  {
   OBV_VS_EMA = 0,   // OBV above its EMA for buys, below it for sells
   OBV_SLOPE  = 1,   // OBV rising for buys, falling for sells
   OBV_BOTH   = 2    // Both of the above
  };

enum ENUM_VA_MODE
  {
   VA_CONFLUENCE = 0,   // Confluence: the broken range edge must sit near a Value Area level
   VA_BOTH       = 1,   // Both confluence and direction
   VA_DIRECTION  = 2    // Direction: buy only above the dividing line, sell only below it
  };

enum ENUM_VA_LINE
  {
   VA_LINE_EDGES = 0,   // Buy above VAH, sell below VAL
   VA_LINE_POC   = 1    // POC divides buys from sells
  };

enum ENUM_VA_SOURCE
  {
   VA_DEVELOPING   = 0,   // Developing levels (the current profile period so far)
   VA_PREV_SESSION = 1    // Previous profile period's levels
  };

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group "=== General (all sessions) ==="
input int    InpManualServerOffsetHours = 3;             // Server-GMT offset, used in TESTER only (Icelandic time mode)
input int    InpPipPoints        = 10;                   // Points per pip (10 = XAUUSD standard)
input bool   InpUseMinLot        = true;                 // Risk too small for the smallest lot: true = trade the smallest lot, false = skip
input int    InpSlippagePoints   = 20;                   // Max slippage for market orders (points)
input ulong  InpMagic            = 20261120;             // Magic number: Asia +0, London +1, New York +2, Sydney +3

input group "=== Wick-break entry (all sessions; candles of each session's signal timeframe) ==="
input bool   InpWB_UseA          = false;                // Module A on/off: enter DURING the next candle, when price passes the break candle's wick by A%
input double InpWB_PctA          = 0;                    // Module A: extra % of the break candle's body beyond its wick (0 = enter the instant the wick is passed)
input bool   InpWB_UseB          = false;                // Module B on/off: enter when the next candle CLOSES past the break candle's wick by B%
input double InpWB_PctB          = 15;                   // Module B: % of the break candle's body that the close must pass its wick by
input double InpWB_SLBufferPips  = 0;                    // Wick-break: stop this many pips beyond the confirming candle's wick (0 = exactly on the wick)
input double InpWB_MinSLPips     = 0;                    // Wick-break: smallest stop distance allowed (pips); 0 = no minimum of your own
input bool   InpWB_KeepNormalEntry = false;              // Wick-break: false = replaces the normal breakout entry while A or B is on, true = both run

input group "=== Candle exits (all sessions; candles of each session's signal timeframe) ==="
input bool   InpEX_UseBars       = false;                // Exit after N candles on/off
input int    InpEX_Bars          = 5;                    // Exit after this many candles have closed since the entry (the entry candle counts as 1)
input bool   InpEX_UseOpposite   = false;                // Exit on an opposite candle on/off
input double InpEX_OppositePct   = 100;                  // Opposite candle: its body must exceed this % of the previous candle's body (100 = bigger than it)
input bool   InpEX_WickBreakOnly = true;                 // Candle exits apply to: true = wick-break trades only, false = every trade of this EA

input group "=============== ASIA SESSION ==============="
input bool                InpAS_Use              = true;           // Asia: trade this session's breakout
input ASB_EA_TIMEMODE     InpAS_TimeMode         = TimeServer;     // Asia: session start/end below are in
input string              InpAS_Start            = "02:00";        // Asia: session start (HH:MM)
input string              InpAS_End              = "10:00";        // Asia: session end (HH:MM)
input double              InpAS_BreakoutHours    = 0;              // Asia: hours after the session to look for its breakout (0 = until it starts again)
input ENUM_TIMEFRAMES     InpAS_SignalTF         = PERIOD_M15;     // Asia: signal timeframe (breakout closes)
input ASB_EA_ENTRYMODE    InpAS_EntryMode        = EntryBreakoutClose; // Asia: how a breakout is entered
input double              InpAS_RiskPercent      = 0.5;            // Asia: risk per trade, % of balance (0 = use the fixed lot)
input double              InpAS_FixedLots        = 0.01;           // Asia: fixed lot, used when the risk % is 0
input int                 InpAS_MaxSpreadPoints  = 50;             // Asia: max spread allowed to enter (points)
input group "--- Asia: exits ---"
input double              InpAS_SLPips           = 1100;           // Asia: stop loss (pips)
input double              InpAS_TPPips           = 1062;           // Asia: take profit (pips)
input bool                InpAS_UseBE            = true;           // Asia: break-even on/off
input double              InpAS_BETriggerPips    = 152;            // Asia: break-even trigger (pips in profit)
input double              InpAS_BELockPips       = 16.4;           // Asia: break-even lock-in (pips)
input ASB_EA_TRAILMODE    InpAS_TrailMode        = TrailPips;      // Asia: trailing stop style
input double              InpAS_TrailStartPips   = 265;            // Asia: pip-trail starts after (pips)
input double              InpAS_TrailDistPips    = 206;            // Asia: pip-trail distance (pips)
input ENUM_TIMEFRAMES     InpAS_StructTF         = PERIOD_M15;     // Asia: structure trail: swing timeframe
input int                 InpAS_SwingBars        = 2;              // Asia: structure trail: swing size (bars each side)
input double              InpAS_StructBufferPips = 5;              // Asia: structure trail: buffer beyond the swing (pips)
input bool                InpAS_CloseAtWindowEnd = false;          // Asia: close positions / delete pendings when the breakout window ends
input group "--- Asia: quality checks ---"
input bool                InpAS_UseQualityFilter = false;          // Asia: block new entries while the session is AVOID
input bool                InpAS_OnlyTradeOK      = false;          // Asia: also block on CAUTION (not just AVOID)
input double              InpAS_WideRangeMult    = 1.5;            // Asia: wide range: bigger than this x average
input int                 InpAS_AvgRangeDays     = 20;             // Asia: average-range lookback (days)
input bool                InpAS_UseNarrowCheck   = true;           // Asia: narrow-range check on/off
input double              InpAS_NarrowMult       = 0.5;            // Asia: narrow range: smaller than this x average
input double              InpAS_BigCandleATRMult = 2.0;            // Asia: big breakout candle: bigger than this x ATR
input int                 InpAS_ATRPeriod        = 18;             // Asia: ATR period (signal timeframe)
input ENUM_TIMEFRAMES     InpAS_TrendTF          = PERIOD_MN1;     // Asia: higher timeframe for the trend check
input int                 InpAS_TrendMAPeriod    = 200;            // Asia: trend EMA period
input bool                InpAS_UseNews          = true;           // Asia: news check on/off (live/demo only, off in tester)
input int                 InpAS_NewsMinutes      = 60;             // Asia: avoid when high-impact news within (minutes)
input string              InpAS_RolloverStart    = "23:55";        // Asia: rollover window start (SERVER time)
input string              InpAS_RolloverEnd      = "00:05";        // Asia: rollover window end (SERVER time)
input group "--- Asia: OBV filter ---"
input bool                InpAS_UseOBV           = true;           // Asia: OBV filter on/off
input ENUM_TIMEFRAMES     InpAS_OBVTF            = PERIOD_D1;      // Asia: OBV timeframe
input int                 InpAS_OBVMaPeriod      = 20;             // Asia: OBV: EMA period applied to OBV
input ENUM_OBV_MODE       InpAS_OBVMode          = OBV_VS_EMA;     // Asia: OBV: how it is judged
input int                 InpAS_OBVSlopeBars     = 3;              // Asia: OBV slope mode: bars back for the comparison
input ENUM_APPLIED_VOLUME InpAS_OBVVolume        = VOLUME_TICK;    // Asia: OBV: volume used (tick is normal for FX/metals)
input group "--- Asia: Value Area filter ---"
input bool                InpAS_UseVA            = false;          // Asia: Value Area filter on/off
input ENUM_VA_MODE        InpAS_VAMode           = VA_DIRECTION;   // Asia: Value Area: how it is judged
input ENUM_VA_LINE        InpAS_VALine           = VA_LINE_POC;    // Asia: Value Area direction mode: dividing line
input ENUM_TIMEFRAMES     InpAS_VAProfileTF      = PERIOD_D1;      // Asia: Value Area: profile timeframe (one profile = one bar of it)
input ENUM_TIMEFRAMES     InpAS_VASourceTF       = PERIOD_CURRENT; // Asia: Value Area: bars the profile is built from (Current = Auto)
input double              InpAS_VAPercent        = 70.0;           // Asia: Value Area: percent of volume inside the area
input ASB_VA_VOLTYPE      InpAS_VAVolumeType     = ASB_VOL_TICK;   // Asia: Value Area: volume type
input int                 InpAS_VABinPoints      = 0;              // Asia: Value Area: row height in points (0 = Auto)
input ENUM_VA_SOURCE      InpAS_VASource         = VA_PREV_SESSION; // Asia: Value Area: which levels to use
input double              InpAS_VATolPips        = 20;             // Asia: Value Area confluence mode: tolerance (pips)
input group "--- Asia: USDX filter ---"
input bool                InpAS_UseUSDX          = false;          // Asia: USDX filter on/off
input string              InpAS_USDXSymbol       = "";             // Asia: USDX: broker dollar-index symbol (blank = built from the major pairs)
input bool                InpAS_USDXUseEUR       = false;          // Asia: USDX: EURUSD must agree too (EURUSD falling = dollar rising)
input string              InpAS_USDXExtraSymbol  = "";             // Asia: USDX: one more symbol that must agree too (blank = none)
input bool                InpAS_USDXExtraInverse = false;          // Asia: USDX: that extra symbol moves false = with the dollar, true = against it
input ENUM_TIMEFRAMES     InpAS_USDXTF           = PERIOD_H1;      // Asia: USDX: EMA timeframe
input int                 InpAS_USDXFast         = 10;             // Asia: USDX: fast EMA period
input int                 InpAS_USDXSlow         = 30;             // Asia: USDX: slow EMA period
input bool                InpAS_USDXInvert       = false;          // Asia: USDX: dollar rising allows false = sells only, true = buys only

input group "=============== LONDON SESSION ==============="
input bool                InpLN_Use              = true;           // London: trade this session's breakout
input ASB_EA_TIMEMODE     InpLN_TimeMode         = TimeServer;     // London: session start/end below are in
input string              InpLN_Start            = "10:00";        // London: session start (HH:MM)
input string              InpLN_End              = "18:00";        // London: session end (HH:MM)
input double              InpLN_BreakoutHours    = 0;              // London: hours after the session to look for its breakout (0 = until it starts again)
input ENUM_TIMEFRAMES     InpLN_SignalTF         = PERIOD_M15;     // London: signal timeframe (breakout closes)
input ASB_EA_ENTRYMODE    InpLN_EntryMode        = EntryBreakoutClose; // London: how a breakout is entered
input double              InpLN_RiskPercent      = 0.5;            // London: risk per trade, % of balance (0 = use the fixed lot)
input double              InpLN_FixedLots        = 0.01;           // London: fixed lot, used when the risk % is 0
input int                 InpLN_MaxSpreadPoints  = 50;             // London: max spread allowed to enter (points)
input group "--- London: exits ---"
input double              InpLN_SLPips           = 1100;           // London: stop loss (pips)
input double              InpLN_TPPips           = 1062;           // London: take profit (pips)
input bool                InpLN_UseBE            = true;           // London: break-even on/off
input double              InpLN_BETriggerPips    = 152;            // London: break-even trigger (pips in profit)
input double              InpLN_BELockPips       = 16.4;           // London: break-even lock-in (pips)
input ASB_EA_TRAILMODE    InpLN_TrailMode        = TrailPips;      // London: trailing stop style
input double              InpLN_TrailStartPips   = 265;            // London: pip-trail starts after (pips)
input double              InpLN_TrailDistPips    = 206;            // London: pip-trail distance (pips)
input ENUM_TIMEFRAMES     InpLN_StructTF         = PERIOD_M15;     // London: structure trail: swing timeframe
input int                 InpLN_SwingBars        = 2;              // London: structure trail: swing size (bars each side)
input double              InpLN_StructBufferPips = 5;              // London: structure trail: buffer beyond the swing (pips)
input bool                InpLN_CloseAtWindowEnd = false;          // London: close positions / delete pendings when the breakout window ends
input group "--- London: quality checks ---"
input bool                InpLN_UseQualityFilter = false;          // London: block new entries while the session is AVOID
input bool                InpLN_OnlyTradeOK      = false;          // London: also block on CAUTION (not just AVOID)
input double              InpLN_WideRangeMult    = 1.5;            // London: wide range: bigger than this x average
input int                 InpLN_AvgRangeDays     = 20;             // London: average-range lookback (days)
input bool                InpLN_UseNarrowCheck   = true;           // London: narrow-range check on/off
input double              InpLN_NarrowMult       = 0.5;            // London: narrow range: smaller than this x average
input double              InpLN_BigCandleATRMult = 2.0;            // London: big breakout candle: bigger than this x ATR
input int                 InpLN_ATRPeriod        = 18;             // London: ATR period (signal timeframe)
input ENUM_TIMEFRAMES     InpLN_TrendTF          = PERIOD_MN1;     // London: higher timeframe for the trend check
input int                 InpLN_TrendMAPeriod    = 200;            // London: trend EMA period
input bool                InpLN_UseNews          = true;           // London: news check on/off (live/demo only, off in tester)
input int                 InpLN_NewsMinutes      = 60;             // London: avoid when high-impact news within (minutes)
input string              InpLN_RolloverStart    = "23:55";        // London: rollover window start (SERVER time)
input string              InpLN_RolloverEnd      = "00:05";        // London: rollover window end (SERVER time)
input group "--- London: OBV filter ---"
input bool                InpLN_UseOBV           = true;           // London: OBV filter on/off
input ENUM_TIMEFRAMES     InpLN_OBVTF            = PERIOD_D1;      // London: OBV timeframe
input int                 InpLN_OBVMaPeriod      = 20;             // London: OBV: EMA period applied to OBV
input ENUM_OBV_MODE       InpLN_OBVMode          = OBV_VS_EMA;     // London: OBV: how it is judged
input int                 InpLN_OBVSlopeBars     = 3;              // London: OBV slope mode: bars back for the comparison
input ENUM_APPLIED_VOLUME InpLN_OBVVolume        = VOLUME_TICK;    // London: OBV: volume used (tick is normal for FX/metals)
input group "--- London: Value Area filter ---"
input bool                InpLN_UseVA            = false;          // London: Value Area filter on/off
input ENUM_VA_MODE        InpLN_VAMode           = VA_DIRECTION;   // London: Value Area: how it is judged
input ENUM_VA_LINE        InpLN_VALine           = VA_LINE_POC;    // London: Value Area direction mode: dividing line
input ENUM_TIMEFRAMES     InpLN_VAProfileTF      = PERIOD_D1;      // London: Value Area: profile timeframe (one profile = one bar of it)
input ENUM_TIMEFRAMES     InpLN_VASourceTF       = PERIOD_CURRENT; // London: Value Area: bars the profile is built from (Current = Auto)
input double              InpLN_VAPercent        = 70.0;           // London: Value Area: percent of volume inside the area
input ASB_VA_VOLTYPE      InpLN_VAVolumeType     = ASB_VOL_TICK;   // London: Value Area: volume type
input int                 InpLN_VABinPoints      = 0;              // London: Value Area: row height in points (0 = Auto)
input ENUM_VA_SOURCE      InpLN_VASource         = VA_PREV_SESSION; // London: Value Area: which levels to use
input double              InpLN_VATolPips        = 20;             // London: Value Area confluence mode: tolerance (pips)
input group "--- London: USDX filter ---"
input bool                InpLN_UseUSDX          = false;          // London: USDX filter on/off
input string              InpLN_USDXSymbol       = "";             // London: USDX: broker dollar-index symbol (blank = built from the major pairs)
input bool                InpLN_USDXUseEUR       = false;          // London: USDX: EURUSD must agree too (EURUSD falling = dollar rising)
input string              InpLN_USDXExtraSymbol  = "";             // London: USDX: one more symbol that must agree too (blank = none)
input bool                InpLN_USDXExtraInverse = false;          // London: USDX: that extra symbol moves false = with the dollar, true = against it
input ENUM_TIMEFRAMES     InpLN_USDXTF           = PERIOD_H1;      // London: USDX: EMA timeframe
input int                 InpLN_USDXFast         = 10;             // London: USDX: fast EMA period
input int                 InpLN_USDXSlow         = 30;             // London: USDX: slow EMA period
input bool                InpLN_USDXInvert       = false;          // London: USDX: dollar rising allows false = sells only, true = buys only

input group "=============== NEW YORK SESSION ==============="
input bool                InpNY_Use              = true;           // New York: trade this session's breakout
input ASB_EA_TIMEMODE     InpNY_TimeMode         = TimeServer;     // New York: session start/end below are in
input string              InpNY_Start            = "15:00";        // New York: session start (HH:MM)
input string              InpNY_End              = "23:00";        // New York: session end (HH:MM)
input double              InpNY_BreakoutHours    = 0;              // New York: hours after the session to look for its breakout (0 = until it starts again)
input ENUM_TIMEFRAMES     InpNY_SignalTF         = PERIOD_M15;     // New York: signal timeframe (breakout closes)
input ASB_EA_ENTRYMODE    InpNY_EntryMode        = EntryBreakoutClose; // New York: how a breakout is entered
input double              InpNY_RiskPercent      = 0.5;            // New York: risk per trade, % of balance (0 = use the fixed lot)
input double              InpNY_FixedLots        = 0.01;           // New York: fixed lot, used when the risk % is 0
input int                 InpNY_MaxSpreadPoints  = 50;             // New York: max spread allowed to enter (points)
input group "--- New York: exits ---"
input double              InpNY_SLPips           = 1100;           // New York: stop loss (pips)
input double              InpNY_TPPips           = 1062;           // New York: take profit (pips)
input bool                InpNY_UseBE            = true;           // New York: break-even on/off
input double              InpNY_BETriggerPips    = 152;            // New York: break-even trigger (pips in profit)
input double              InpNY_BELockPips       = 16.4;           // New York: break-even lock-in (pips)
input ASB_EA_TRAILMODE    InpNY_TrailMode        = TrailPips;      // New York: trailing stop style
input double              InpNY_TrailStartPips   = 265;            // New York: pip-trail starts after (pips)
input double              InpNY_TrailDistPips    = 206;            // New York: pip-trail distance (pips)
input ENUM_TIMEFRAMES     InpNY_StructTF         = PERIOD_M15;     // New York: structure trail: swing timeframe
input int                 InpNY_SwingBars        = 2;              // New York: structure trail: swing size (bars each side)
input double              InpNY_StructBufferPips = 5;              // New York: structure trail: buffer beyond the swing (pips)
input bool                InpNY_CloseAtWindowEnd = false;          // New York: close positions / delete pendings when the breakout window ends
input group "--- New York: quality checks ---"
input bool                InpNY_UseQualityFilter = false;          // New York: block new entries while the session is AVOID
input bool                InpNY_OnlyTradeOK      = false;          // New York: also block on CAUTION (not just AVOID)
input double              InpNY_WideRangeMult    = 1.5;            // New York: wide range: bigger than this x average
input int                 InpNY_AvgRangeDays     = 20;             // New York: average-range lookback (days)
input bool                InpNY_UseNarrowCheck   = true;           // New York: narrow-range check on/off
input double              InpNY_NarrowMult       = 0.5;            // New York: narrow range: smaller than this x average
input double              InpNY_BigCandleATRMult = 2.0;            // New York: big breakout candle: bigger than this x ATR
input int                 InpNY_ATRPeriod        = 18;             // New York: ATR period (signal timeframe)
input ENUM_TIMEFRAMES     InpNY_TrendTF          = PERIOD_MN1;     // New York: higher timeframe for the trend check
input int                 InpNY_TrendMAPeriod    = 200;            // New York: trend EMA period
input bool                InpNY_UseNews          = true;           // New York: news check on/off (live/demo only, off in tester)
input int                 InpNY_NewsMinutes      = 60;             // New York: avoid when high-impact news within (minutes)
input string              InpNY_RolloverStart    = "23:55";        // New York: rollover window start (SERVER time)
input string              InpNY_RolloverEnd      = "00:05";        // New York: rollover window end (SERVER time)
input group "--- New York: OBV filter ---"
input bool                InpNY_UseOBV           = true;           // New York: OBV filter on/off
input ENUM_TIMEFRAMES     InpNY_OBVTF            = PERIOD_D1;      // New York: OBV timeframe
input int                 InpNY_OBVMaPeriod      = 20;             // New York: OBV: EMA period applied to OBV
input ENUM_OBV_MODE       InpNY_OBVMode          = OBV_VS_EMA;     // New York: OBV: how it is judged
input int                 InpNY_OBVSlopeBars     = 3;              // New York: OBV slope mode: bars back for the comparison
input ENUM_APPLIED_VOLUME InpNY_OBVVolume        = VOLUME_TICK;    // New York: OBV: volume used (tick is normal for FX/metals)
input group "--- New York: Value Area filter ---"
input bool                InpNY_UseVA            = false;          // New York: Value Area filter on/off
input ENUM_VA_MODE        InpNY_VAMode           = VA_DIRECTION;   // New York: Value Area: how it is judged
input ENUM_VA_LINE        InpNY_VALine           = VA_LINE_POC;    // New York: Value Area direction mode: dividing line
input ENUM_TIMEFRAMES     InpNY_VAProfileTF      = PERIOD_D1;      // New York: Value Area: profile timeframe (one profile = one bar of it)
input ENUM_TIMEFRAMES     InpNY_VASourceTF       = PERIOD_CURRENT; // New York: Value Area: bars the profile is built from (Current = Auto)
input double              InpNY_VAPercent        = 70.0;           // New York: Value Area: percent of volume inside the area
input ASB_VA_VOLTYPE      InpNY_VAVolumeType     = ASB_VOL_TICK;   // New York: Value Area: volume type
input int                 InpNY_VABinPoints      = 0;              // New York: Value Area: row height in points (0 = Auto)
input ENUM_VA_SOURCE      InpNY_VASource         = VA_PREV_SESSION; // New York: Value Area: which levels to use
input double              InpNY_VATolPips        = 20;             // New York: Value Area confluence mode: tolerance (pips)
input group "--- New York: USDX filter ---"
input bool                InpNY_UseUSDX          = false;          // New York: USDX filter on/off
input string              InpNY_USDXSymbol       = "";             // New York: USDX: broker dollar-index symbol (blank = built from the major pairs)
input bool                InpNY_USDXUseEUR       = false;          // New York: USDX: EURUSD must agree too (EURUSD falling = dollar rising)
input string              InpNY_USDXExtraSymbol  = "";             // New York: USDX: one more symbol that must agree too (blank = none)
input bool                InpNY_USDXExtraInverse = false;          // New York: USDX: that extra symbol moves false = with the dollar, true = against it
input ENUM_TIMEFRAMES     InpNY_USDXTF           = PERIOD_H1;      // New York: USDX: EMA timeframe
input int                 InpNY_USDXFast         = 10;             // New York: USDX: fast EMA period
input int                 InpNY_USDXSlow         = 30;             // New York: USDX: slow EMA period
input bool                InpNY_USDXInvert       = false;          // New York: USDX: dollar rising allows false = sells only, true = buys only

input group "=============== SYDNEY SESSION ==============="
input bool                InpSY_Use              = true;           // Sydney: trade this session's breakout
input ASB_EA_TIMEMODE     InpSY_TimeMode         = TimeServer;     // Sydney: session start/end below are in
input string              InpSY_Start            = "00:00";        // Sydney: session start (HH:MM)
input string              InpSY_End              = "08:00";        // Sydney: session end (HH:MM)
input double              InpSY_BreakoutHours    = 0;              // Sydney: hours after the session to look for its breakout (0 = until it starts again)
input ENUM_TIMEFRAMES     InpSY_SignalTF         = PERIOD_M15;     // Sydney: signal timeframe (breakout closes)
input ASB_EA_ENTRYMODE    InpSY_EntryMode        = EntryBreakoutClose; // Sydney: how a breakout is entered
input double              InpSY_RiskPercent      = 0.5;            // Sydney: risk per trade, % of balance (0 = use the fixed lot)
input double              InpSY_FixedLots        = 0.01;           // Sydney: fixed lot, used when the risk % is 0
input int                 InpSY_MaxSpreadPoints  = 50;             // Sydney: max spread allowed to enter (points)
input group "--- Sydney: exits ---"
input double              InpSY_SLPips           = 1100;           // Sydney: stop loss (pips)
input double              InpSY_TPPips           = 1062;           // Sydney: take profit (pips)
input bool                InpSY_UseBE            = true;           // Sydney: break-even on/off
input double              InpSY_BETriggerPips    = 152;            // Sydney: break-even trigger (pips in profit)
input double              InpSY_BELockPips       = 16.4;           // Sydney: break-even lock-in (pips)
input ASB_EA_TRAILMODE    InpSY_TrailMode        = TrailPips;      // Sydney: trailing stop style
input double              InpSY_TrailStartPips   = 265;            // Sydney: pip-trail starts after (pips)
input double              InpSY_TrailDistPips    = 206;            // Sydney: pip-trail distance (pips)
input ENUM_TIMEFRAMES     InpSY_StructTF         = PERIOD_M15;     // Sydney: structure trail: swing timeframe
input int                 InpSY_SwingBars        = 2;              // Sydney: structure trail: swing size (bars each side)
input double              InpSY_StructBufferPips = 5;              // Sydney: structure trail: buffer beyond the swing (pips)
input bool                InpSY_CloseAtWindowEnd = false;          // Sydney: close positions / delete pendings when the breakout window ends
input group "--- Sydney: quality checks ---"
input bool                InpSY_UseQualityFilter = false;          // Sydney: block new entries while the session is AVOID
input bool                InpSY_OnlyTradeOK      = false;          // Sydney: also block on CAUTION (not just AVOID)
input double              InpSY_WideRangeMult    = 1.5;            // Sydney: wide range: bigger than this x average
input int                 InpSY_AvgRangeDays     = 20;             // Sydney: average-range lookback (days)
input bool                InpSY_UseNarrowCheck   = true;           // Sydney: narrow-range check on/off
input double              InpSY_NarrowMult       = 0.5;            // Sydney: narrow range: smaller than this x average
input double              InpSY_BigCandleATRMult = 2.0;            // Sydney: big breakout candle: bigger than this x ATR
input int                 InpSY_ATRPeriod        = 18;             // Sydney: ATR period (signal timeframe)
input ENUM_TIMEFRAMES     InpSY_TrendTF          = PERIOD_MN1;     // Sydney: higher timeframe for the trend check
input int                 InpSY_TrendMAPeriod    = 200;            // Sydney: trend EMA period
input bool                InpSY_UseNews          = true;           // Sydney: news check on/off (live/demo only, off in tester)
input int                 InpSY_NewsMinutes      = 60;             // Sydney: avoid when high-impact news within (minutes)
input string              InpSY_RolloverStart    = "23:55";        // Sydney: rollover window start (SERVER time)
input string              InpSY_RolloverEnd      = "00:05";        // Sydney: rollover window end (SERVER time)
input group "--- Sydney: OBV filter ---"
input bool                InpSY_UseOBV           = true;           // Sydney: OBV filter on/off
input ENUM_TIMEFRAMES     InpSY_OBVTF            = PERIOD_D1;      // Sydney: OBV timeframe
input int                 InpSY_OBVMaPeriod      = 20;             // Sydney: OBV: EMA period applied to OBV
input ENUM_OBV_MODE       InpSY_OBVMode          = OBV_VS_EMA;     // Sydney: OBV: how it is judged
input int                 InpSY_OBVSlopeBars     = 3;              // Sydney: OBV slope mode: bars back for the comparison
input ENUM_APPLIED_VOLUME InpSY_OBVVolume        = VOLUME_TICK;    // Sydney: OBV: volume used (tick is normal for FX/metals)
input group "--- Sydney: Value Area filter ---"
input bool                InpSY_UseVA            = false;          // Sydney: Value Area filter on/off
input ENUM_VA_MODE        InpSY_VAMode           = VA_DIRECTION;   // Sydney: Value Area: how it is judged
input ENUM_VA_LINE        InpSY_VALine           = VA_LINE_POC;    // Sydney: Value Area direction mode: dividing line
input ENUM_TIMEFRAMES     InpSY_VAProfileTF      = PERIOD_D1;      // Sydney: Value Area: profile timeframe (one profile = one bar of it)
input ENUM_TIMEFRAMES     InpSY_VASourceTF       = PERIOD_CURRENT; // Sydney: Value Area: bars the profile is built from (Current = Auto)
input double              InpSY_VAPercent        = 70.0;           // Sydney: Value Area: percent of volume inside the area
input ASB_VA_VOLTYPE      InpSY_VAVolumeType     = ASB_VOL_TICK;   // Sydney: Value Area: volume type
input int                 InpSY_VABinPoints      = 0;              // Sydney: Value Area: row height in points (0 = Auto)
input ENUM_VA_SOURCE      InpSY_VASource         = VA_PREV_SESSION; // Sydney: Value Area: which levels to use
input double              InpSY_VATolPips        = 20;             // Sydney: Value Area confluence mode: tolerance (pips)
input group "--- Sydney: USDX filter ---"
input bool                InpSY_UseUSDX          = false;          // Sydney: USDX filter on/off
input string              InpSY_USDXSymbol       = "";             // Sydney: USDX: broker dollar-index symbol (blank = built from the major pairs)
input bool                InpSY_USDXUseEUR       = false;          // Sydney: USDX: EURUSD must agree too (EURUSD falling = dollar rising)
input string              InpSY_USDXExtraSymbol  = "";             // Sydney: USDX: one more symbol that must agree too (blank = none)
input bool                InpSY_USDXExtraInverse = false;          // Sydney: USDX: that extra symbol moves false = with the dollar, true = against it
input ENUM_TIMEFRAMES     InpSY_USDXTF           = PERIOD_H1;      // Sydney: USDX: EMA timeframe
input int                 InpSY_USDXFast         = 10;             // Sydney: USDX: fast EMA period
input int                 InpSY_USDXSlow         = 30;             // Sydney: USDX: slow EMA period
input bool                InpSY_USDXInvert       = false;          // Sydney: USDX: dollar rising allows false = sells only, true = buys only
//+------------------------------------------------------------------+
//| ASB CORE - built into this file (used to be the ClaudeEAs include |
//| files). Plain helper code, no trading in here.                    |
//+------------------------------------------------------------------+
// One "day" = one cycle of one session: from the moment the session starts
// until the moment it starts again 24 hours later.
struct ASBDay
  {
   datetime start;       // the session starts (start of the cycle)
   datetime sess_end;    // the session ends - breakouts count from here
   datetime day_end;     // the breakout window closes
   double   high;        // session range high
   double   low;         // session range low
   bool     has_range;   // the session has at least one bar
   bool     failed;      // the first breakout later closed back inside the range
  };

struct ASBEvent
  {
   int      day_idx;      // index into the days array
   int      dir;          // +1 = bull breakout, -1 = bear breakout
   datetime time;         // open time of the breakout candle
   datetime entry_time;   // its close time
   double   entry;        // its close price
   double   range_hi;
   double   range_lo;
   datetime day_end;
  };

struct ASBQuality
  {
   bool wide_range;
   bool narrow_range;
   bool both_broken;
   bool failed_bo;
   bool big_candle;
   bool spread_high;
   bool trend_conflict;
   bool news_near;
   bool rollover;
  };

#define ASB_ST_NONE   0
#define ASB_ST_BULL   1
#define ASB_ST_BEAR   2
#define ASB_ST_BOTH   3
#define ASB_ST_FAILED 4

//+------------------------------------------------------------------+
//| "HH:MM" -> minutes since midnight. -1 = not a valid time.         |
//+------------------------------------------------------------------+
int ASB_ParseHHMM(const string text)
  {
   string parts[];
   if(StringSplit(text, ':', parts) != 2)
      return -1;
   StringTrimLeft(parts[0]);  StringTrimRight(parts[0]);
   StringTrimLeft(parts[1]);  StringTrimRight(parts[1]);
   int len_h = StringLen(parts[0]);
   int len_m = StringLen(parts[1]);
   if(len_h < 1 || len_h > 2 || len_m < 1 || len_m > 2)
      return -1;
   for(int i = 0; i < len_h; i++)
     {
      int ch = StringGetCharacter(parts[0], i);
      if(ch < '0' || ch > '9') return -1;
     }
   for(int i = 0; i < len_m; i++)
     {
      int ch = StringGetCharacter(parts[1], i);
      if(ch < '0' || ch > '9') return -1;
     }
   int hh = (int)StringToInteger(parts[0]);
   int mm = (int)StringToInteger(parts[1]);
   if(hh > 23 || mm > 59)
      return -1;
   return hh * 60 + mm;
  }

double ASB_PipSize(const double point, const int pip_points)
  {
   return point * pip_points;
  }

double ASB_ToPips(const double price_distance, const double pip)
  {
   if(pip <= 0.0)
      return 0.0;
   return price_distance / pip;
  }

//+------------------------------------------------------------------+
//| Server time minus GMT, in seconds. The tester has no real GMT     |
//| clock, so there the manual input is used.                         |
//+------------------------------------------------------------------+
int ASB_ServerOffsetSec(const bool tester, const int manual_hours)
  {
   if(tester)
      return manual_hours * 3600;
   double diff = (double)(TimeTradeServer() - TimeGMT());
   return (int)MathRound(diff / 1800.0) * 1800;      // brokers sit on whole or half hours
  }

//+------------------------------------------------------------------+
//| Icelandic (GMT) minutes-of-day -> server minutes-of-day.          |
//+------------------------------------------------------------------+
int ASB_ISMinToServerMin(const int minutes, const int offset_sec)
  {
   int m = (minutes + offset_sec / 60) % 1440;
   if(m < 0)
      m += 1440;
   return m;
  }

datetime ASB_DayStart(const datetime t)
  {
   return (datetime)(t - (t % 86400));
  }

int ASB_MinOfDay(const datetime t)
  {
   return (int)((t % 86400) / 60);
  }

//+------------------------------------------------------------------+
//| Is minute m inside the window [start, end)? The window may run    |
//| over midnight (start later than end).                             |
//+------------------------------------------------------------------+
bool ASB_InWindow(const int m, const int start, const int end)
  {
   if(start == end)
      return false;
   if(start < end)
      return (m >= start && m < end);
   return (m >= start || m < end);
  }

//+------------------------------------------------------------------+
//| Start of the session cycle a moment belongs to: the latest moment |
//| at or before t whose clock time is the session's start time.      |
//+------------------------------------------------------------------+
datetime ASB_CycleStart(const datetime t, const int sess_start_min)
  {
   long since = ((long)t - (long)sess_start_min * 60) % 86400;
   if(since < 0)
      since += 86400;
   return (datetime)((long)t - since);
  }

//+------------------------------------------------------------------+
//| One entry per session cycle, with the high/low of the session     |
//| (every bar that OPENS while the session is running). Bars must be |
//| oldest first. Returns the number of cycles.                       |
//+------------------------------------------------------------------+
int ASB_BuildDays(const MqlRates &sig[], const int got, const int sess_start_min, const int sess_len_sec,
                  const int window_sec, ASBDay &days[])
  {
   ArrayResize(days, 0);
   int nd = 0;
   for(int i = 0; i < got; i++)
     {
      datetime cs = ASB_CycleStart(sig[i].time, sess_start_min);
      if(nd == 0 || days[nd - 1].start != cs)
        {
         ArrayResize(days, nd + 1, 64);
         days[nd].start     = cs;
         days[nd].sess_end  = cs + sess_len_sec;
         days[nd].day_end   = cs + sess_len_sec + window_sec;
         days[nd].high      = 0.0;
         days[nd].low       = 0.0;
         days[nd].has_range = false;
         days[nd].failed    = false;
         nd++;
        }
      if(sig[i].time >= days[nd - 1].sess_end)
         continue;                         // the session is over - not part of the range
      if(!days[nd - 1].has_range)
        {
         days[nd - 1].high      = sig[i].high;
         days[nd - 1].low       = sig[i].low;
         days[nd - 1].has_range = true;
        }
      else
        {
         if(sig[i].high > days[nd - 1].high) days[nd - 1].high = sig[i].high;
         if(sig[i].low  < days[nd - 1].low)  days[nd - 1].low  = sig[i].low;
        }
     }
   return nd;
  }

//+------------------------------------------------------------------+
//| Breakouts: once the session has ended (and while its breakout     |
//| window is open), the first candle that CLOSES above the range is  |
//| the bull event, the first that closes below it is the bear event  |
//| - at most one of each per cycle. Also marks a cycle "failed" when |
//| a candle closes back inside the range after its first breakout.   |
//+------------------------------------------------------------------+
void ASB_DetectEvents(const MqlRates &sig[], const int got, ASBDay &days[], const int nd, const int tf_sec,
                      const int sess_start_min, ASBEvent &events[])
  {
   ArrayResize(events, 0);
   if(nd <= 0)
      return;
   int  ne = 0;
   int  d = 0;
   int  cur = -1;
   bool bull = false, bear = false;
   int  first_dir = 0;
   for(int i = 0; i < got; i++)
     {
      datetime cs = ASB_CycleStart(sig[i].time, sess_start_min);
      while(d < nd - 1 && days[d].start < cs)
         d++;
      if(days[d].start != cs)
         continue;
      if(d != cur)
        {
         cur = d;
         bull = false;
         bear = false;
         first_dir = 0;
        }
      if(!days[d].has_range)
         continue;
      if(sig[i].time < days[d].sess_end || sig[i].time >= days[d].day_end)
         continue;                         // still inside the session, or the window has closed

      double c = sig[i].close;
      if(first_dir > 0 && c < days[d].high) days[d].failed = true;
      if(first_dir < 0 && c > days[d].low)  days[d].failed = true;

      int dir = 0;
      if(c > days[d].high && !bull)
         dir = +1;
      else if(c < days[d].low && !bear)
         dir = -1;
      if(dir == 0)
         continue;

      ArrayResize(events, ne + 1, 32);
      events[ne].day_idx    = d;
      events[ne].dir        = dir;
      events[ne].time       = sig[i].time;
      events[ne].entry_time = sig[i].time + tf_sec;
      events[ne].entry      = c;
      events[ne].range_hi   = days[d].high;
      events[ne].range_lo   = days[d].low;
      events[ne].day_end    = days[d].day_end;
      ne++;
      if(dir > 0) bull = true; else bear = true;
      if(first_dir == 0) first_dir = dir;
     }
  }

//+------------------------------------------------------------------+
//| What has happened on one day so far. first_dir = direction of the |
//| day's earliest breakout (0 = none).                               |
//+------------------------------------------------------------------+
int ASB_DayStatus(const ASBEvent &events[], const int n, const int day_idx, const bool failed, int &first_dir)
  {
   first_dir = 0;
   bool has_bull = false, has_bear = false;
   datetime first_time = 0;
   for(int i = 0; i < n; i++)
     {
      if(events[i].day_idx != day_idx)
         continue;
      if(events[i].dir > 0) has_bull = true; else has_bear = true;
      if(first_dir == 0 || events[i].time < first_time)
        {
         first_dir  = events[i].dir;
         first_time = events[i].time;
        }
     }
   if(has_bull && has_bear) return ASB_ST_BOTH;
   if(first_dir == 0)       return ASB_ST_NONE;
   if(failed)               return ASB_ST_FAILED;
   return (first_dir > 0) ? ASB_ST_BULL : ASB_ST_BEAR;
  }

//+------------------------------------------------------------------+
//| Average true range of the `period` bars ending at bar b.          |
//| 0 = not enough bars.                                              |
//+------------------------------------------------------------------+
double ASB_ATRAt(const MqlRates &r[], const int n, const int b, const int period)
  {
   if(period < 1 || b >= n || b - period < 0)
      return 0.0;
   double sum = 0.0;
   for(int i = b - period + 1; i <= b; i++)
     {
      double tr = r[i].high - r[i].low;
      double up = MathAbs(r[i].high - r[i - 1].close);
      double dn = MathAbs(r[i].low  - r[i - 1].close);
      if(up > tr) tr = up;
      if(dn > tr) tr = dn;
      sum += tr;
     }
   return sum / period;
  }

//+------------------------------------------------------------------+
//| Swing lows (dir > 0, for a long's stop) or swing highs (dir < 0), |
//| oldest first. A swing is a bar whose low/high beats `swing` bars  |
//| on each side; it only counts from the moment the last of those    |
//| right-hand bars has closed (ctime). Returns how many were found.  |
//+------------------------------------------------------------------+
int ASB_BuildSwings(const MqlRates &r[], const int n, const int tf_sec, const int swing, const int dir,
                    double &level[], datetime &ctime[])
  {
   ArrayResize(level, 0);
   ArrayResize(ctime, 0);
   int found = 0;
   if(swing < 1)
      return 0;
   for(int i = swing; i < n - swing; i++)
     {
      bool ok = true;
      for(int k = 1; k <= swing && ok; k++)
        {
         if(dir > 0)
           {
            if(r[i - k].low <= r[i].low || r[i + k].low <= r[i].low) ok = false;
           }
         else
           {
            if(r[i - k].high >= r[i].high || r[i + k].high >= r[i].high) ok = false;
           }
        }
      if(!ok)
         continue;
      ArrayResize(level, found + 1, 32);
      ArrayResize(ctime, found + 1, 32);
      level[found] = (dir > 0) ? r[i].low : r[i].high;
      ctime[found] = r[i + swing].time + tf_sec;
      found++;
     }
   return found;
  }

//+------------------------------------------------------------------+
//| Quality                                                           |
//+------------------------------------------------------------------+
void ASB_QualityInit(ASBQuality &q)
  {
   q.wide_range     = false;
   q.narrow_range   = false;
   q.both_broken    = false;
   q.failed_bo      = false;
   q.big_candle     = false;
   q.spread_high    = false;
   q.trend_conflict = false;
   q.news_near      = false;
   q.rollover       = false;
  }

void ASB_AddReason(string &list, const string reason)
  {
   if(list != "")
      list += ", ";
   list += reason;
  }

//+------------------------------------------------------------------+
//| 0 = AVOID, 1 = CAUTION, 2 = TRADE OK. `why` lists the reasons.    |
//| AVOID: both sides broken, failed breakout, narrow range, spread   |
//| too high, news near. CAUTION: wide range, big breakout candle,    |
//| trend conflict, rollover.                                         |
//+------------------------------------------------------------------+
int ASB_QualityStatus(const ASBQuality &q, string &why)
  {
   why = "";
   bool avoid = false, caution = false;
   if(q.both_broken)    { avoid = true;   ASB_AddReason(why, "both sides broken"); }
   if(q.failed_bo)      { avoid = true;   ASB_AddReason(why, "failed breakout"); }
   if(q.narrow_range)   { avoid = true;   ASB_AddReason(why, "narrow range"); }
   if(q.spread_high)    { avoid = true;   ASB_AddReason(why, "spread too high"); }
   if(q.news_near)      { avoid = true;   ASB_AddReason(why, "news near"); }
   if(q.wide_range)     { caution = true; ASB_AddReason(why, "wide range"); }
   if(q.big_candle)     { caution = true; ASB_AddReason(why, "big breakout candle"); }
   if(q.trend_conflict) { caution = true; ASB_AddReason(why, "trend conflict"); }
   if(q.rollover)       { caution = true; ASB_AddReason(why, "rollover"); }
   if(avoid)   return 0;
   if(caution) return 1;
   return 2;
  }

//+------------------------------------------------------------------+
//| Minutes to (or since) the nearest HIGH-impact calendar event for  |
//| one currency within +/- `minutes`. -1 = none.                     |
//+------------------------------------------------------------------+
int ASB_NewsMinutesFor(const string currency, const int minutes)
  {
   if(currency == "")
      return -1;
   datetime now = TimeTradeServer();
   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, now - minutes * 60, now + minutes * 60, NULL, currency);
   int best = -1;
   for(int i = 0; i < total; i++)
     {
      MqlCalendarEvent info;
      if(!CalendarEventById(values[i].event_id, info))
         continue;
      if(info.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      int away = (int)(MathAbs((double)(values[i].time - now)) / 60.0);
      if(best < 0 || away < best)
         best = away;
     }
   return best;
  }

//+------------------------------------------------------------------+
//| Same, for the two currencies of the chart symbol. The economic    |
//| calendar does not exist in the Strategy Tester: always -1 there.  |
//+------------------------------------------------------------------+
int ASB_MinutesToHighImpactNews(const int minutes)
  {
   if((bool)MQLInfoInteger(MQL_TESTER) || minutes <= 0)
      return -1;
   string profit = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   string base   = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   int a = ASB_NewsMinutesFor(profit, minutes);
   int b = (base != profit) ? ASB_NewsMinutesFor(base, minutes) : -1;
   if(a < 0) return b;
   if(b < 0) return a;
   return (a < b) ? a : b;
  }

//+------------------------------------------------------------------+
//| Exits. Each returns a NEW stop price only when it is a real       |
//| improvement on cur_sl (a stop never moves backwards); 0 = leave   |
//| the stop where it is.                                             |
//+------------------------------------------------------------------+
bool ASB_StopImproves(const int dir, const double cand, const double cur_sl)
  {
   if(cur_sl == 0.0)
      return true;
   return ((cand - cur_sl) * dir > 0.0);
  }

// Break-even: once the trade has been trigger_pips in profit, the stop goes
// to the entry price plus lock_pips.
double ASB_EA_BECand(const int dir, const double entry, const double best_fav_pips,
                     const double trigger_pips, const double lock_pips, const double pip, const double cur_sl)
  {
   if(best_fav_pips < trigger_pips)
      return 0.0;
   double cand = entry + dir * lock_pips * pip;
   return ASB_StopImproves(dir, cand, cur_sl) ? cand : 0.0;
  }

// Pip trail: once the trade has been start_pips in profit, the stop follows
// the best price reached, dist_pips behind it.
double ASB_EA_TrailPipsCand(const int dir, const double entry, const double best,
                            const double start_pips, const double dist_pips, const double pip, const double cur_sl)
  {
   if((best - entry) * dir < start_pips * pip)
      return 0.0;
   double cand = best - dir * dist_pips * pip;
   return ASB_StopImproves(dir, cand, cur_sl) ? cand : 0.0;
  }

// Structure trail: the stop sits buffer_pips beyond the last confirmed swing,
// as long as that is still on the safe side of the last closed price.
double ASB_EA_TrailStructCand(const int dir, const double swing, const double buffer_pips, const double pip,
                              const double cur_sl, const double close_price)
  {
   double cand = swing - dir * buffer_pips * pip;
   if((close_price - cand) * dir <= 0.0)
      return 0.0;
   return ASB_StopImproves(dir, cand, cur_sl) ? cand : 0.0;
  }

//+------------------------------------------------------------------+
//| Filters                                                           |
//+------------------------------------------------------------------+
bool CRTOBV_PassEma(const double obv, const double ema, const int dir)
  {
   return (dir > 0) ? (obv > ema) : (obv < ema);
  }

bool CRTOBV_PassSlope(const double obv_now, const double obv_past, const int dir)
  {
   return (dir > 0) ? (obv_now > obv_past) : (obv_now < obv_past);
  }

bool CRTVA_PassDirection(const ENUM_VA_LINE line, const double vah, const double poc, const double val,
                         const double price, const int dir)
  {
   if(line == VA_LINE_POC)
      return (dir > 0) ? (price > poc) : (price < poc);
   return (dir > 0) ? (price > vah) : (price < val);
  }

bool CRTVA_PassConfluence(const double vah, const double poc, const double val, const double level, const double tol)
  {
   return (MathAbs(level - vah) <= tol || MathAbs(level - poc) <= tol || MathAbs(level - val) <= tol);
  }

//+------------------------------------------------------------------+
//| Which direction the dollar index allows on this (xxxUSD) symbol:  |
//| fast EMA above slow = dollar rising = sells only (-1); below =    |
//| dollar falling = buys only (+1). `invert` swaps the two.          |
//+------------------------------------------------------------------+
int ASB_EA_UsdxAllowedDir(const double ema_fast, const double ema_slow, const bool invert)
  {
   int dir = 0;
   if(ema_fast > ema_slow) dir = -1;
   if(ema_fast < ema_slow) dir = +1;
   return invert ? -dir : dir;
  }

//+------------------------------------------------------------------+
//| Every enabled filter must agree before an entry is allowed.       |
//+------------------------------------------------------------------+
bool ASB_EA_FiltersPass(const int dir, const int qstat, const bool use_quality, const bool only_ok,
                        const bool use_obv, const bool obv_pass, const bool use_va, const bool va_pass,
                        const bool use_usdx, const int usdx_allowed)
  {
   if(use_quality)
     {
      if(qstat == 0) return false;
      if(only_ok && qstat != 2) return false;
     }
   if(use_obv && !obv_pass) return false;
   if(use_va && !va_pass)   return false;
   if(use_usdx && usdx_allowed != dir) return false;
   return true;
  }
//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
CTrade trade;

double g_pip        = 0.1;
int    g_offset     = 0;      // server minus GMT, seconds
datetime g_last_m1  = 0;

// USDX. Per session the dollar index is either ONE broker dollar-index
// symbol (plain EMA handles), or the standard ICE dollar-index formula
// worked out from the six pairs:
// 50.14348112 x EURUSD^-0.576 x USDJPY^0.136 x GBPUSD^-0.119
//             x USDCAD^0.091  x USDSEK^0.042 x USDCHF^0.036
#define ASB_USDX_PAIRS 6
const string ASB_USDX_CORE[ASB_USDX_PAIRS]   = {"EURUSD", "USDJPY", "GBPUSD", "USDCAD", "USDSEK", "USDCHF"};
const double ASB_USDX_WEIGHT[ASB_USDX_PAIRS] = {-0.576, 0.136, -0.119, 0.091, 0.042, 0.036};
string g_usdx_pair[ASB_USDX_PAIRS];      // this broker's name for each pair ("" = not offered or not needed)

//+------------------------------------------------------------------+
//| One session: its settings (copied from its own block of inputs)   |
//| and everything the EA remembers about it while running.           |
//+------------------------------------------------------------------+
#define MSB_SESSIONS 4
struct MSBSession
  {
   // --- settings ---
   string           name;            // "Asia", "London", ... used in the log
   string           tag;             // short name used in order comments
   bool             use;
   ASB_EA_TIMEMODE  time_mode;       // this session's start/end are Icelandic time or server time
   string           start_txt;
   string           end_txt;
   double           breakout_hours;
   ENUM_TIMEFRAMES  sig_tf;
   ASB_EA_ENTRYMODE entry_mode;
   double           risk_pct;
   double           fixed_lots;
   int              max_spread;
   double           sl_pips;
   double           tp_pips;
   bool             use_be;
   double           be_trigger;
   double           be_lock;
   ASB_EA_TRAILMODE trail_mode;
   double           trail_start;
   double           trail_dist;
   ENUM_TIMEFRAMES  struct_tf;
   int              swing_bars;
   double           struct_buffer;
   bool             close_at_window_end;
   bool             use_quality;
   bool             only_ok;
   double           wide_mult;
   int              avg_range_days;
   bool             use_narrow;
   double           narrow_mult;
   double           big_candle_mult;
   int              atr_period;
   ENUM_TIMEFRAMES  trend_tf;
   int              trend_ma_period;
   bool             use_news;
   int              news_minutes;
   string           roll_start_txt;
   string           roll_end_txt;
   bool             use_obv;
   ENUM_TIMEFRAMES  obv_tf;
   int              obv_ma;
   ENUM_OBV_MODE    obv_mode;
   int              obv_slope;
   ENUM_APPLIED_VOLUME obv_volume;
   bool             use_va;
   ENUM_VA_MODE     va_mode;
   ENUM_VA_LINE     va_line;
   ENUM_TIMEFRAMES  va_profile_tf;   // one profile = one bar of this timeframe
   ENUM_TIMEFRAMES  va_source_tf;    // bars the profile is built from (Current = Auto)
   double           va_percent;      // share of the volume inside the value area
   ASB_VA_VOLTYPE   va_volume_type;
   int              va_bin_points;   // row height in points (0 = Auto)
   ENUM_VA_SOURCE   va_source;
   double           va_tol;
   bool             use_usdx;
   string           usdx_symbol_txt;    // broker dollar-index symbol as typed (blank = built from the pairs)
   bool             usdx_use_eur;       // EURUSD must agree as well
   string           usdx_extra_txt;     // one more symbol that must agree, as typed (blank = none)
   bool             usdx_extra_inverse; // that symbol moves against the dollar
   ENUM_TIMEFRAMES  usdx_tf;
   int              usdx_fast;
   int              usdx_slow;
   bool             usdx_invert;
   // --- worked out from the settings ---
   int              start_min;       // session start, server minutes-of-day
   int              len_sec;         // session length, seconds
   int              window_sec;      // breakout window after the session, seconds
   long             magic;           // magic number of this session's trades
   int              roll_start;      // rollover window, server minutes-of-day
   int              roll_end;
   bool             usdx_broker;     // true = the index is one broker symbol, false = the six-pair formula
   string           usdx_symbol;     // broker dollar-index symbol in use
   string           usdx_extra_symbol; // the extra symbol in use ("" = none)
   // --- running state ---
   datetime         last_sig_bar;    // last signal bar this session has processed
   datetime         track_start;     // the session cycle the two flags below belong to
   bool             rescanned;
   bool             bull_done;
   bool             bear_done;
   int              last_qstat;      // last quality line printed, to avoid repeating it
   string           last_why;
   bool             minlot_noted;    // the "smallest lot used" note has been printed
   int              obv_handle;
   int              obv_ema_handle;
   int              trend_ma;        // trend EMA handle for this session's quality check
   int              usdx_fast_h;     // EMA handles on the broker dollar-index symbol
   int              usdx_slow_h;
   int              usdx_eur_fast_h; // EMA handles on EURUSD
   int              usdx_eur_slow_h;
   int              usdx_extra_fast_h; // EMA handles on the extra symbol
   int              usdx_extra_slow_h;
   datetime         va_cache_period; // profile period the remembered levels below belong to
   double           va_cache_vah;    // (previous-period levels stay the same for a whole period,
   double           va_cache_poc;    //  so they are worked out once and remembered)
   double           va_cache_val;
   // --- wick-break module A: what it is waiting for during the candle forming now ---
   datetime         wb_bar;          // open time of the candle the triggers below belong to (0 = not armed)
   double           wb_trig_up;      // buy when the bid reaches this (0 = no buy armed)
   double           wb_trig_dn;      // sell when the bid reaches this (0 = no sell armed)
   int              wb_q_up;         // quality status worked out for each direction when it was armed
   int              wb_q_dn;
   string           wb_why_up;
   string           wb_why_dn;
   double           wb_range_hi;     // the session range and window the armed setup belongs to
   double           wb_range_lo;
   datetime         wb_day_end;
   int              wb_day_idx;
   datetime         usdx_cache_bar;  // last closed bar the two EMAs below were worked out for
   double           usdx_cache_ef;
   double           usdx_cache_es;
  };
MSBSession g_s[MSB_SESSIONS];

//+------------------------------------------------------------------+
//| Copy every session's block of inputs into its slot.               |
//+------------------------------------------------------------------+
void ASB_EA_LoadInputs()
  {
   g_s[0].name = "Asia";
   g_s[0].tag  = "AS";
   g_s[0].use                     = InpAS_Use;
   g_s[0].time_mode               = InpAS_TimeMode;
   g_s[0].start_txt               = InpAS_Start;
   g_s[0].end_txt                 = InpAS_End;
   g_s[0].breakout_hours          = InpAS_BreakoutHours;
   g_s[0].sig_tf                  = InpAS_SignalTF;
   g_s[0].entry_mode              = InpAS_EntryMode;
   g_s[0].risk_pct                = InpAS_RiskPercent;
   g_s[0].fixed_lots              = InpAS_FixedLots;
   g_s[0].max_spread              = InpAS_MaxSpreadPoints;
   g_s[0].sl_pips                 = InpAS_SLPips;
   g_s[0].tp_pips                 = InpAS_TPPips;
   g_s[0].use_be                  = InpAS_UseBE;
   g_s[0].be_trigger              = InpAS_BETriggerPips;
   g_s[0].be_lock                 = InpAS_BELockPips;
   g_s[0].trail_mode              = InpAS_TrailMode;
   g_s[0].trail_start             = InpAS_TrailStartPips;
   g_s[0].trail_dist              = InpAS_TrailDistPips;
   g_s[0].struct_tf               = InpAS_StructTF;
   g_s[0].swing_bars              = InpAS_SwingBars;
   g_s[0].struct_buffer           = InpAS_StructBufferPips;
   g_s[0].close_at_window_end     = InpAS_CloseAtWindowEnd;
   g_s[0].use_quality             = InpAS_UseQualityFilter;
   g_s[0].only_ok                 = InpAS_OnlyTradeOK;
   g_s[0].wide_mult               = InpAS_WideRangeMult;
   g_s[0].avg_range_days          = InpAS_AvgRangeDays;
   g_s[0].use_narrow              = InpAS_UseNarrowCheck;
   g_s[0].narrow_mult             = InpAS_NarrowMult;
   g_s[0].big_candle_mult         = InpAS_BigCandleATRMult;
   g_s[0].atr_period              = InpAS_ATRPeriod;
   g_s[0].trend_tf                = InpAS_TrendTF;
   g_s[0].trend_ma_period         = InpAS_TrendMAPeriod;
   g_s[0].use_news                = InpAS_UseNews;
   g_s[0].news_minutes            = InpAS_NewsMinutes;
   g_s[0].roll_start_txt          = InpAS_RolloverStart;
   g_s[0].roll_end_txt            = InpAS_RolloverEnd;
   g_s[0].use_obv                 = InpAS_UseOBV;
   g_s[0].obv_tf                  = InpAS_OBVTF;
   g_s[0].obv_ma                  = InpAS_OBVMaPeriod;
   g_s[0].obv_mode                = InpAS_OBVMode;
   g_s[0].obv_slope               = InpAS_OBVSlopeBars;
   g_s[0].obv_volume              = InpAS_OBVVolume;
   g_s[0].use_va                  = InpAS_UseVA;
   g_s[0].va_mode                 = InpAS_VAMode;
   g_s[0].va_line                 = InpAS_VALine;
   g_s[0].va_profile_tf           = InpAS_VAProfileTF;
   g_s[0].va_source_tf            = InpAS_VASourceTF;
   g_s[0].va_percent              = InpAS_VAPercent;
   g_s[0].va_volume_type          = InpAS_VAVolumeType;
   g_s[0].va_bin_points           = InpAS_VABinPoints;
   g_s[0].va_source               = InpAS_VASource;
   g_s[0].va_tol                  = InpAS_VATolPips;
   g_s[0].use_usdx                = InpAS_UseUSDX;
   g_s[0].usdx_symbol_txt         = InpAS_USDXSymbol;
   g_s[0].usdx_use_eur            = InpAS_USDXUseEUR;
   g_s[0].usdx_extra_txt          = InpAS_USDXExtraSymbol;
   g_s[0].usdx_extra_inverse      = InpAS_USDXExtraInverse;
   g_s[0].usdx_tf                 = InpAS_USDXTF;
   g_s[0].usdx_fast               = InpAS_USDXFast;
   g_s[0].usdx_slow               = InpAS_USDXSlow;
   g_s[0].usdx_invert             = InpAS_USDXInvert;

   g_s[1].name = "London";
   g_s[1].tag  = "LDN";
   g_s[1].use                     = InpLN_Use;
   g_s[1].time_mode               = InpLN_TimeMode;
   g_s[1].start_txt               = InpLN_Start;
   g_s[1].end_txt                 = InpLN_End;
   g_s[1].breakout_hours          = InpLN_BreakoutHours;
   g_s[1].sig_tf                  = InpLN_SignalTF;
   g_s[1].entry_mode              = InpLN_EntryMode;
   g_s[1].risk_pct                = InpLN_RiskPercent;
   g_s[1].fixed_lots              = InpLN_FixedLots;
   g_s[1].max_spread              = InpLN_MaxSpreadPoints;
   g_s[1].sl_pips                 = InpLN_SLPips;
   g_s[1].tp_pips                 = InpLN_TPPips;
   g_s[1].use_be                  = InpLN_UseBE;
   g_s[1].be_trigger              = InpLN_BETriggerPips;
   g_s[1].be_lock                 = InpLN_BELockPips;
   g_s[1].trail_mode              = InpLN_TrailMode;
   g_s[1].trail_start             = InpLN_TrailStartPips;
   g_s[1].trail_dist              = InpLN_TrailDistPips;
   g_s[1].struct_tf               = InpLN_StructTF;
   g_s[1].swing_bars              = InpLN_SwingBars;
   g_s[1].struct_buffer           = InpLN_StructBufferPips;
   g_s[1].close_at_window_end     = InpLN_CloseAtWindowEnd;
   g_s[1].use_quality             = InpLN_UseQualityFilter;
   g_s[1].only_ok                 = InpLN_OnlyTradeOK;
   g_s[1].wide_mult               = InpLN_WideRangeMult;
   g_s[1].avg_range_days          = InpLN_AvgRangeDays;
   g_s[1].use_narrow              = InpLN_UseNarrowCheck;
   g_s[1].narrow_mult             = InpLN_NarrowMult;
   g_s[1].big_candle_mult         = InpLN_BigCandleATRMult;
   g_s[1].atr_period              = InpLN_ATRPeriod;
   g_s[1].trend_tf                = InpLN_TrendTF;
   g_s[1].trend_ma_period         = InpLN_TrendMAPeriod;
   g_s[1].use_news                = InpLN_UseNews;
   g_s[1].news_minutes            = InpLN_NewsMinutes;
   g_s[1].roll_start_txt          = InpLN_RolloverStart;
   g_s[1].roll_end_txt            = InpLN_RolloverEnd;
   g_s[1].use_obv                 = InpLN_UseOBV;
   g_s[1].obv_tf                  = InpLN_OBVTF;
   g_s[1].obv_ma                  = InpLN_OBVMaPeriod;
   g_s[1].obv_mode                = InpLN_OBVMode;
   g_s[1].obv_slope               = InpLN_OBVSlopeBars;
   g_s[1].obv_volume              = InpLN_OBVVolume;
   g_s[1].use_va                  = InpLN_UseVA;
   g_s[1].va_mode                 = InpLN_VAMode;
   g_s[1].va_line                 = InpLN_VALine;
   g_s[1].va_profile_tf           = InpLN_VAProfileTF;
   g_s[1].va_source_tf            = InpLN_VASourceTF;
   g_s[1].va_percent              = InpLN_VAPercent;
   g_s[1].va_volume_type          = InpLN_VAVolumeType;
   g_s[1].va_bin_points           = InpLN_VABinPoints;
   g_s[1].va_source               = InpLN_VASource;
   g_s[1].va_tol                  = InpLN_VATolPips;
   g_s[1].use_usdx                = InpLN_UseUSDX;
   g_s[1].usdx_symbol_txt         = InpLN_USDXSymbol;
   g_s[1].usdx_use_eur            = InpLN_USDXUseEUR;
   g_s[1].usdx_extra_txt          = InpLN_USDXExtraSymbol;
   g_s[1].usdx_extra_inverse      = InpLN_USDXExtraInverse;
   g_s[1].usdx_tf                 = InpLN_USDXTF;
   g_s[1].usdx_fast               = InpLN_USDXFast;
   g_s[1].usdx_slow               = InpLN_USDXSlow;
   g_s[1].usdx_invert             = InpLN_USDXInvert;

   g_s[2].name = "New York";
   g_s[2].tag  = "NY";
   g_s[2].use                     = InpNY_Use;
   g_s[2].time_mode               = InpNY_TimeMode;
   g_s[2].start_txt               = InpNY_Start;
   g_s[2].end_txt                 = InpNY_End;
   g_s[2].breakout_hours          = InpNY_BreakoutHours;
   g_s[2].sig_tf                  = InpNY_SignalTF;
   g_s[2].entry_mode              = InpNY_EntryMode;
   g_s[2].risk_pct                = InpNY_RiskPercent;
   g_s[2].fixed_lots              = InpNY_FixedLots;
   g_s[2].max_spread              = InpNY_MaxSpreadPoints;
   g_s[2].sl_pips                 = InpNY_SLPips;
   g_s[2].tp_pips                 = InpNY_TPPips;
   g_s[2].use_be                  = InpNY_UseBE;
   g_s[2].be_trigger              = InpNY_BETriggerPips;
   g_s[2].be_lock                 = InpNY_BELockPips;
   g_s[2].trail_mode              = InpNY_TrailMode;
   g_s[2].trail_start             = InpNY_TrailStartPips;
   g_s[2].trail_dist              = InpNY_TrailDistPips;
   g_s[2].struct_tf               = InpNY_StructTF;
   g_s[2].swing_bars              = InpNY_SwingBars;
   g_s[2].struct_buffer           = InpNY_StructBufferPips;
   g_s[2].close_at_window_end     = InpNY_CloseAtWindowEnd;
   g_s[2].use_quality             = InpNY_UseQualityFilter;
   g_s[2].only_ok                 = InpNY_OnlyTradeOK;
   g_s[2].wide_mult               = InpNY_WideRangeMult;
   g_s[2].avg_range_days          = InpNY_AvgRangeDays;
   g_s[2].use_narrow              = InpNY_UseNarrowCheck;
   g_s[2].narrow_mult             = InpNY_NarrowMult;
   g_s[2].big_candle_mult         = InpNY_BigCandleATRMult;
   g_s[2].atr_period              = InpNY_ATRPeriod;
   g_s[2].trend_tf                = InpNY_TrendTF;
   g_s[2].trend_ma_period         = InpNY_TrendMAPeriod;
   g_s[2].use_news                = InpNY_UseNews;
   g_s[2].news_minutes            = InpNY_NewsMinutes;
   g_s[2].roll_start_txt          = InpNY_RolloverStart;
   g_s[2].roll_end_txt            = InpNY_RolloverEnd;
   g_s[2].use_obv                 = InpNY_UseOBV;
   g_s[2].obv_tf                  = InpNY_OBVTF;
   g_s[2].obv_ma                  = InpNY_OBVMaPeriod;
   g_s[2].obv_mode                = InpNY_OBVMode;
   g_s[2].obv_slope               = InpNY_OBVSlopeBars;
   g_s[2].obv_volume              = InpNY_OBVVolume;
   g_s[2].use_va                  = InpNY_UseVA;
   g_s[2].va_mode                 = InpNY_VAMode;
   g_s[2].va_line                 = InpNY_VALine;
   g_s[2].va_profile_tf           = InpNY_VAProfileTF;
   g_s[2].va_source_tf            = InpNY_VASourceTF;
   g_s[2].va_percent              = InpNY_VAPercent;
   g_s[2].va_volume_type          = InpNY_VAVolumeType;
   g_s[2].va_bin_points           = InpNY_VABinPoints;
   g_s[2].va_source               = InpNY_VASource;
   g_s[2].va_tol                  = InpNY_VATolPips;
   g_s[2].use_usdx                = InpNY_UseUSDX;
   g_s[2].usdx_symbol_txt         = InpNY_USDXSymbol;
   g_s[2].usdx_use_eur            = InpNY_USDXUseEUR;
   g_s[2].usdx_extra_txt          = InpNY_USDXExtraSymbol;
   g_s[2].usdx_extra_inverse      = InpNY_USDXExtraInverse;
   g_s[2].usdx_tf                 = InpNY_USDXTF;
   g_s[2].usdx_fast               = InpNY_USDXFast;
   g_s[2].usdx_slow               = InpNY_USDXSlow;
   g_s[2].usdx_invert             = InpNY_USDXInvert;

   g_s[3].name = "Sydney";
   g_s[3].tag  = "SYD";
   g_s[3].use                     = InpSY_Use;
   g_s[3].time_mode               = InpSY_TimeMode;
   g_s[3].start_txt               = InpSY_Start;
   g_s[3].end_txt                 = InpSY_End;
   g_s[3].breakout_hours          = InpSY_BreakoutHours;
   g_s[3].sig_tf                  = InpSY_SignalTF;
   g_s[3].entry_mode              = InpSY_EntryMode;
   g_s[3].risk_pct                = InpSY_RiskPercent;
   g_s[3].fixed_lots              = InpSY_FixedLots;
   g_s[3].max_spread              = InpSY_MaxSpreadPoints;
   g_s[3].sl_pips                 = InpSY_SLPips;
   g_s[3].tp_pips                 = InpSY_TPPips;
   g_s[3].use_be                  = InpSY_UseBE;
   g_s[3].be_trigger              = InpSY_BETriggerPips;
   g_s[3].be_lock                 = InpSY_BELockPips;
   g_s[3].trail_mode              = InpSY_TrailMode;
   g_s[3].trail_start             = InpSY_TrailStartPips;
   g_s[3].trail_dist              = InpSY_TrailDistPips;
   g_s[3].struct_tf               = InpSY_StructTF;
   g_s[3].swing_bars              = InpSY_SwingBars;
   g_s[3].struct_buffer           = InpSY_StructBufferPips;
   g_s[3].close_at_window_end     = InpSY_CloseAtWindowEnd;
   g_s[3].use_quality             = InpSY_UseQualityFilter;
   g_s[3].only_ok                 = InpSY_OnlyTradeOK;
   g_s[3].wide_mult               = InpSY_WideRangeMult;
   g_s[3].avg_range_days          = InpSY_AvgRangeDays;
   g_s[3].use_narrow              = InpSY_UseNarrowCheck;
   g_s[3].narrow_mult             = InpSY_NarrowMult;
   g_s[3].big_candle_mult         = InpSY_BigCandleATRMult;
   g_s[3].atr_period              = InpSY_ATRPeriod;
   g_s[3].trend_tf                = InpSY_TrendTF;
   g_s[3].trend_ma_period         = InpSY_TrendMAPeriod;
   g_s[3].use_news                = InpSY_UseNews;
   g_s[3].news_minutes            = InpSY_NewsMinutes;
   g_s[3].roll_start_txt          = InpSY_RolloverStart;
   g_s[3].roll_end_txt            = InpSY_RolloverEnd;
   g_s[3].use_obv                 = InpSY_UseOBV;
   g_s[3].obv_tf                  = InpSY_OBVTF;
   g_s[3].obv_ma                  = InpSY_OBVMaPeriod;
   g_s[3].obv_mode                = InpSY_OBVMode;
   g_s[3].obv_slope               = InpSY_OBVSlopeBars;
   g_s[3].obv_volume              = InpSY_OBVVolume;
   g_s[3].use_va                  = InpSY_UseVA;
   g_s[3].va_mode                 = InpSY_VAMode;
   g_s[3].va_line                 = InpSY_VALine;
   g_s[3].va_profile_tf           = InpSY_VAProfileTF;
   g_s[3].va_source_tf            = InpSY_VASourceTF;
   g_s[3].va_percent              = InpSY_VAPercent;
   g_s[3].va_volume_type          = InpSY_VAVolumeType;
   g_s[3].va_bin_points           = InpSY_VABinPoints;
   g_s[3].va_source               = InpSY_VASource;
   g_s[3].va_tol                  = InpSY_VATolPips;
   g_s[3].use_usdx                = InpSY_UseUSDX;
   g_s[3].usdx_symbol_txt         = InpSY_USDXSymbol;
   g_s[3].usdx_use_eur            = InpSY_USDXUseEUR;
   g_s[3].usdx_extra_txt          = InpSY_USDXExtraSymbol;
   g_s[3].usdx_extra_inverse      = InpSY_USDXExtraInverse;
   g_s[3].usdx_tf                 = InpSY_USDXTF;
   g_s[3].usdx_fast               = InpSY_USDXFast;
   g_s[3].usdx_slow               = InpSY_USDXSlow;
   g_s[3].usdx_invert             = InpSY_USDXInvert;
  }

//+------------------------------------------------------------------+
//| Which session a magic number belongs to. -1 = not this EA's.      |
//+------------------------------------------------------------------+
int ASB_EA_SessionOfMagic(const long magic)
  {
   for(int k = 0; k < MSB_SESSIONS; k++)
      if(magic == g_s[k].magic)
         return k;
   return -1;
  }

//+------------------------------------------------------------------+
//| Minutes-of-day -> "HH:MM", for the log.                           |
//+------------------------------------------------------------------+
string ASB_EA_HHMM(const int minutes)
  {
   return StringFormat("%02d:%02d", minutes / 60, minutes % 60);
  }

//+------------------------------------------------------------------+
//| Check one session's settings and work out its hours. Sets its     |
//| running state back to "nothing done yet". false = a bad input.    |
//+------------------------------------------------------------------+
bool ASB_EA_SetupSession(const int k)
  {
   g_s[k].magic          = (long)InpMagic + k;
   g_s[k].last_sig_bar   = 0;
   g_s[k].track_start    = 0;
   g_s[k].rescanned      = false;
   g_s[k].bull_done      = false;
   g_s[k].bear_done      = false;
   g_s[k].last_qstat     = -1;
   g_s[k].last_why       = "";
   g_s[k].minlot_noted   = false;
   g_s[k].obv_handle     = INVALID_HANDLE;
   g_s[k].obv_ema_handle = INVALID_HANDLE;
   g_s[k].trend_ma       = INVALID_HANDLE;
   g_s[k].usdx_fast_h    = INVALID_HANDLE;
   g_s[k].usdx_slow_h    = INVALID_HANDLE;
   g_s[k].usdx_eur_fast_h   = INVALID_HANDLE;
   g_s[k].usdx_eur_slow_h   = INVALID_HANDLE;
   g_s[k].usdx_extra_fast_h = INVALID_HANDLE;
   g_s[k].usdx_extra_slow_h = INVALID_HANDLE;
   g_s[k].usdx_broker       = false;
   g_s[k].usdx_symbol       = "";
   g_s[k].usdx_extra_symbol = "";
   g_s[k].roll_start     = 1435;
   g_s[k].roll_end       = 5;
   g_s[k].va_cache_period = 0;
   g_s[k].va_cache_vah   = 0.0;
   g_s[k].va_cache_poc   = 0.0;
   g_s[k].va_cache_val   = 0.0;
   g_s[k].usdx_cache_bar = 0;
   g_s[k].usdx_cache_ef  = 0.0;
   g_s[k].usdx_cache_es  = 0.0;
   g_s[k].start_min      = 0;
   g_s[k].len_sec        = 0;
   g_s[k].window_sec     = 0;

   string name = g_s[k].name;
   int s1 = ASB_ParseHHMM(g_s[k].start_txt);
   int s2 = ASB_ParseHHMM(g_s[k].end_txt);
   if(s1 < 0 || s2 < 0)
     {
      PrintFormat("MSB EA: a %s session time is not valid. Please use HH:MM, for example 10:00.", name);
      return false;
     }
   if(s1 == s2)
     {
      PrintFormat("MSB EA: the %s session starts and ends at the same time - the session would be empty.", name);
      return false;
     }
   if(g_s[k].time_mode == TimeIcelandic)
     {
      s1 = ASB_ISMinToServerMin(s1, g_offset);
      s2 = ASB_ISMinToServerMin(s2, g_offset);
     }
   g_s[k].start_min = s1;
   g_s[k].len_sec   = ((s2 - s1 + 1440) % 1440) * 60;

   // The breakout window can never run into the same session's next start.
   int longest = 86400 - g_s[k].len_sec;
   int window  = (g_s[k].breakout_hours > 0.0) ? (int)MathRound(g_s[k].breakout_hours * 3600.0) : longest;
   if(window > longest)
      window = longest;
   g_s[k].window_sec = window;

   if(!g_s[k].use)
     {
      PrintFormat("MSB EA: %s session is switched OFF (trades it already has open are still managed).", name);
      return true;
     }

   // The rest only matters for a session that is switched on.
   int tf_sec = PeriodSeconds(g_s[k].sig_tf);
   if(tf_sec <= 0 || tf_sec >= 86400)
     {
      PrintFormat("MSB EA: %s signal timeframe must be shorter than one day.", name);
      return false;
     }
   if(g_s[k].breakout_hours < 0)
     {
      PrintFormat("MSB EA: %s breakout hours must be zero or more.", name);
      return false;
     }
   if(g_s[k].sl_pips <= 0 || g_s[k].tp_pips <= 0)
     {
      PrintFormat("MSB EA: %s stop loss and take profit pips must both be greater than zero.", name);
      return false;
     }
   if(g_s[k].risk_pct < 0 || g_s[k].risk_pct > 100)
     {
      PrintFormat("MSB EA: %s risk per trade must be between 0 and 100 percent.", name);
      return false;
     }
   if(g_s[k].fixed_lots <= 0)
     {
      PrintFormat("MSB EA: %s fixed lot must be greater than zero.", name);
      return false;
     }
   if(g_s[k].max_spread < 0)
     {
      PrintFormat("MSB EA: %s max spread must be zero or more.", name);
      return false;
     }
   g_s[k].roll_start = ASB_ParseHHMM(g_s[k].roll_start_txt);
   g_s[k].roll_end   = ASB_ParseHHMM(g_s[k].roll_end_txt);
   if(g_s[k].roll_start < 0 || g_s[k].roll_end < 0)
     {
      PrintFormat("MSB EA: a %s rollover time is not valid. Please use HH:MM, for example 23:55.", name);
      return false;
     }
   if(g_s[k].avg_range_days < 1 || g_s[k].atr_period < 1 || g_s[k].trend_ma_period < 1)
     {
      PrintFormat("MSB EA: %s quality checks need the average-range days, the ATR period and the trend EMA period to be at least 1.", name);
      return false;
     }
   if(g_s[k].wide_mult <= 0 || g_s[k].narrow_mult <= 0 || g_s[k].big_candle_mult <= 0 || g_s[k].news_minutes < 0)
     {
      PrintFormat("MSB EA: %s quality checks need multipliers above zero and news minutes of zero or more.", name);
      return false;
     }
   if(g_s[k].swing_bars < 1)
     {
      PrintFormat("MSB EA: %s swing size must be at least 1 bar.", name);
      return false;
     }
   if(g_s[k].use_obv && g_s[k].obv_ma <= 0)
     {
      PrintFormat("MSB EA: %s OBV filter needs an EMA period greater than zero.", name);
      return false;
     }
   if(g_s[k].use_va && g_s[k].va_tol < 0)
     {
      PrintFormat("MSB EA: %s Value Area tolerance must be zero or more.", name);
      return false;
     }
   if(g_s[k].use_va && (g_s[k].va_percent < 1.0 || g_s[k].va_percent > 100.0))
     {
      PrintFormat("MSB EA: %s Value Area percent must be between 1 and 100.", name);
      return false;
     }
   if(g_s[k].use_va && g_s[k].va_bin_points < 0)
     {
      PrintFormat("MSB EA: %s Value Area row height must be zero (Auto) or more.", name);
      return false;
     }
   if(g_s[k].use_va &&
      PeriodSeconds(ASB_EA_VASourceTF(g_s[k].va_profile_tf, g_s[k].va_source_tf)) >= PeriodSeconds(g_s[k].va_profile_tf))
     {
      PrintFormat("MSB EA: %s Value Area needs its source timeframe to be smaller than its profile timeframe (for example M5 bars inside a D1 profile).", name);
      return false;
     }
   if(g_s[k].use_usdx && (g_s[k].usdx_fast < 1 || g_s[k].usdx_slow < 1 || g_s[k].usdx_fast >= g_s[k].usdx_slow))
     {
      PrintFormat("MSB EA: %s USDX filter needs 1 <= fast EMA < slow EMA.", name);
      return false;
     }

   string lot_txt = (g_s[k].risk_pct > 0.0) ? StringFormat("risk %.2f%% of balance", g_s[k].risk_pct)
                                            : StringFormat("fixed lot %.2f", g_s[k].fixed_lots);
   PrintFormat("MSB EA: %s ON - session %s-%s server time%s, breakout looked for during the %.1f hours after it. TF=%s SL=%.0fp TP=%.0fp, %s. Quality gate=%s. Filters: OBV=%s VA=%s USDX=%s. Magic=%I64d.",
               name, ASB_EA_HHMM(s1), ASB_EA_HHMM(s2),
               (g_s[k].time_mode == TimeIcelandic ? StringFormat(" (typed as %s-%s Icelandic time)", g_s[k].start_txt, g_s[k].end_txt) : ""),
               window / 3600.0, EnumToString(g_s[k].sig_tf),
               g_s[k].sl_pips, g_s[k].tp_pips, lot_txt, (g_s[k].use_quality ? "on" : "off"),
               (g_s[k].use_obv ? "on" : "off"), (g_s[k].use_va ? "on" : "off"), (g_s[k].use_usdx ? "on" : "off"),
               g_s[k].magic);
   if(g_s[k].use_va)
     {
      ENUM_TIMEFRAMES bars_tf = ASB_EA_VASourceTF(g_s[k].va_profile_tf, g_s[k].va_source_tf);
      PrintFormat("MSB EA: %s Value Area - profile timeframe %s, built from %s bars, %.0f%% of the volume.",
                  name, EnumToString(g_s[k].va_profile_tf), EnumToString(bars_tf), g_s[k].va_percent);
      // Ask for the profile's bars once now, so they are already loading
      // (or, in the tester, loaded) before the first breakout needs them.
      MqlRates va_warm[];
      CopyRates(_Symbol, bars_tf, 0, 10, va_warm);
      iTime(_Symbol, g_s[k].va_profile_tf, 1);
     }
   return true;
  }

//+------------------------------------------------------------------+
//| One indicator buffer value at a given shift. false = not ready.   |
//+------------------------------------------------------------------+
bool ASB_EA_ReadBuf(const int handle, const int idx, const int shift, double &out)
  {
   out = 0.0;
   if(handle == INVALID_HANDLE)
      return false;
   double tmp[1];
   if(CopyBuffer(handle, idx, shift, 1, tmp) != 1)
      return false;
   out = tmp[0];
   return true;
  }

//+------------------------------------------------------------------+
//| Clamp a lot size to the symbol's volume min/step/max, same rule   |
//| as CRT_Sweep_AutoBest_EA_MT5.mq5's NormalizeVolume.                |
//+------------------------------------------------------------------+
double ASB_EA_NormalizeVolume(const double volume)
  {
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;

   double v = MathMax(minVol, MathMin(maxVol, volume));
   v = MathFloor((v / step) + 0.0000001) * step;

   int digits = 0;
   double s = step;
   while(s < 1.0 && digits < 8) { s *= 10.0; digits++; }
   v = NormalizeDouble(v, digits);

   if(v < minVol) v = minVol;
   return v;
  }

//+------------------------------------------------------------------+
//| Lot size for one trade of session k whose stop is sl_dist (in     |
//| price) away from the entry.                                       |
//|  - risk % above 0: the lot that loses that share of the account   |
//|    BALANCE if the stop loss is hit, rounded DOWN to the broker's  |
//|    lot step                                                       |
//|  - risk % = 0: the fixed lot                                      |
//| ok = false means no trade should be sent.                         |
//+------------------------------------------------------------------+
double ASB_EA_LotsFor(const int k, const double sl_dist, bool &ok)
  {
   ok = true;
   if(g_s[k].risk_pct <= 0.0)
      return ASB_EA_NormalizeVolume(g_s[k].fixed_lots);

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * g_s[k].risk_pct / 100.0;

   // What one whole lot loses over the stop distance, in account money.
   double loss_per_lot = 0.0;
   double price  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double profit = 0.0;
   if(price - sl_dist > 0.0 && OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, price, price - sl_dist, profit) && profit < 0.0)
      loss_per_lot = -profit;
   else
     {
      double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tick_value <= 0.0)
         tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_size > 0.0)
         loss_per_lot = sl_dist / tick_size * tick_value;
     }
   if(loss_per_lot <= 0.0 || risk_money <= 0.0)
     {
      PrintFormat("MSB EA: %s lot size cannot be worked out (balance %.2f, loss per lot %.2f).",
                  g_s[k].name, balance, loss_per_lot);
      ok = false;
      return 0.0;
     }

   double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double raw = risk_money / loss_per_lot;
   if(raw < min_vol)
     {
      if(!InpUseMinLot)
        {
         PrintFormat("MSB EA: %s risk %.2f%% (%.2f) is too small for the smallest lot %.2f, which would risk %.2f - trade skipped (InpUseMinLot is off).",
                     g_s[k].name, g_s[k].risk_pct, risk_money, min_vol, min_vol * loss_per_lot);
         ok = false;
         return 0.0;
        }
      if(!g_s[k].minlot_noted)
        {
         PrintFormat("MSB EA: %s note - risk %.2f%% (%.2f) is too small for the smallest lot %.2f; the smallest lot is used and risks %.2f per trade.",
                     g_s[k].name, g_s[k].risk_pct, risk_money, min_vol, min_vol * loss_per_lot);
         g_s[k].minlot_noted = true;
        }
      return ASB_EA_NormalizeVolume(min_vol);
     }
   return ASB_EA_NormalizeVolume(raw);      // rounds DOWN to the lot step, capped at the broker's largest lot
  }

//+------------------------------------------------------------------+
//| VALUE AREA                                                        |
//+------------------------------------------------------------------+
//| Timeframe the built-in volume profile is built from.              |
//| "Current" in the input means Auto: small enough for a fine        |
//| profile, large enough to stay fast.                               |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES ASB_EA_VASourceTF(const ENUM_TIMEFRAMES profile_tf, const ENUM_TIMEFRAMES source_tf)
  {
   if(source_tf != PERIOD_CURRENT)
      return source_tf;
   int psec = PeriodSeconds(profile_tf);
   if(psec <= 4 * 3600)  return PERIOD_M1;
   if(psec <= 86400)     return PERIOD_M5;
   if(psec <= 7 * 86400) return PERIOD_M30;
   return PERIOD_H1;
  }

//+------------------------------------------------------------------+
//| Built-in engine: volume profile of one stretch of time, then the  |
//| classic value area on it.                                         |
//|  - every source bar spreads its volume evenly over the price rows |
//|    between its low and its high                                   |
//|  - POC = the row with the most volume                             |
//|  - the value area grows out from the POC, each step taking the    |
//|    heavier pair of rows (above or below), until it holds          |
//|    `percent` of all the volume. VAH/VAL are its two edges.        |
//| false = no usable data for that stretch yet.                      |
//+------------------------------------------------------------------+
bool ASB_EA_BuildValueArea(const ENUM_TIMEFRAMES bars_tf, const double percent, const ASB_VA_VOLTYPE vol_type, const int bin_points,
                           const datetime from, const datetime to, double &vah, double &poc, double &val)
  {
   vah = 0.0; poc = 0.0; val = 0.0;
   if(to < from)
      return false;

   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, bars_tf, from, to, r);
   if(n <= 0)
      return false;

   double lo = r[0].low, hi = r[0].high;
   double real_sum = 0.0;
   for(int i = 0; i < n; i++)
     {
      if(r[i].low  < lo) lo = r[i].low;
      if(r[i].high > hi) hi = r[i].high;
      real_sum += (double)r[i].real_volume;
     }
   // Real volume is empty on most FX/metal feeds - use tick volume then.
   bool use_real = (vol_type == ASB_VOL_REAL && real_sum > 0.0);

   // Row height. Auto aims for about 300 rows across the session's range;
   // a fixed size that would need a huge number of rows is widened so one
   // bad input can never freeze a backtest.
   double range_pts = (hi - lo) / _Point;
   double bin_pts = (bin_points > 0) ? (double)bin_points : MathMax(1.0, MathCeil(range_pts / 300.0));
   if(range_pts / bin_pts > 5000.0)
      bin_pts = MathCeil(range_pts / 5000.0);
   double bin = bin_pts * _Point;
   if(bin <= 0.0)
      return false;

   double base = MathFloor(lo / bin) * bin;
   int rows = (int)MathFloor((hi - base) / bin + 0.0000001) + 1;
   if(rows < 1)
      rows = 1;

   double vol[];
   ArrayResize(vol, rows);
   ArrayInitialize(vol, 0.0);
   double total = 0.0;
   for(int i = 0; i < n; i++)
     {
      double v = use_real ? (double)r[i].real_volume : (double)r[i].tick_volume;
      if(v <= 0.0)
         continue;
      int b0 = (int)MathFloor((r[i].low  - base) / bin + 0.0000001);
      int b1 = (int)MathFloor((r[i].high - base) / bin + 0.0000001);
      if(b0 < 0) b0 = 0;
      if(b1 > rows - 1) b1 = rows - 1;
      if(b1 < b0) b1 = b0;
      double share = v / (double)(b1 - b0 + 1);
      for(int b = b0; b <= b1; b++)
         vol[b] += share;
      total += v;
     }
   if(total <= 0.0)
      return false;

   // POC: the heaviest row. Several neighbouring rows often tie exactly
   // (they were filled by the same bars), so take the middle of that run.
   int p = 0;
   for(int b = 1; b < rows; b++)
      if(vol[b] > vol[p]) p = b;
   int q = p;
   while(q + 1 < rows && vol[q + 1] >= vol[p] * 0.999999999)
      q++;
   int poc_row = (p + q) / 2;

   int lo_row = poc_row, hi_row = poc_row;
   double acc = vol[poc_row];
   double target = total * percent / 100.0;
   while(acc < target && (lo_row > 0 || hi_row < rows - 1))
     {
      int n_up = (int)MathMin(2, rows - 1 - hi_row);
      int n_dn = (int)MathMin(2, lo_row);
      double up = 0.0, dn = 0.0;
      for(int k = 1; k <= n_up; k++) up += vol[hi_row + k];
      for(int k = 1; k <= n_dn; k++) dn += vol[lo_row - k];
      bool take_up = (n_dn == 0) || (n_up > 0 && up >= dn);
      if(take_up) { acc += up; hi_row += n_up; }
      else        { acc += dn; lo_row -= n_dn; }
     }

   // Middle of the POC row, kept inside the session's own high/low (a row
   // can stick out past them when the rows are tall).
   poc = NormalizeDouble(MathMax(lo, MathMin(hi, base + (poc_row + 0.5) * bin)), _Digits);
   vah = NormalizeDouble(MathMin(hi, base + (hi_row + 1) * bin), _Digits);
   val = NormalizeDouble(MathMax(lo, base + lo_row * bin), _Digits);
   return (vah >= poc && poc >= val && val > 0.0);
  }

//+------------------------------------------------------------------+
//| The Value Area levels session k's filter asked for, on that       |
//| session's OWN profile timeframe:                                  |
//|  - previous: the whole last finished bar of the profile timeframe |
//|    (e.g. yesterday for D1), worked out once and remembered        |
//|  - developing: the current profile bar so far, CLOSED source bars |
//|    only (no look-ahead)                                           |
//+------------------------------------------------------------------+
bool ASB_EA_BuiltInValueArea(const int k, double &vah, double &poc, double &val)
  {
   ENUM_TIMEFRAMES profile_tf = g_s[k].va_profile_tf;
   ENUM_TIMEFRAMES bars_tf    = ASB_EA_VASourceTF(profile_tf, g_s[k].va_source_tf);

   datetime period = iTime(_Symbol, profile_tf, 0);
   if(period == 0)
      return false;

   if(g_s[k].va_source == VA_PREV_SESSION)
     {
      if(g_s[k].va_cache_period == period)
        {
         vah = g_s[k].va_cache_vah; poc = g_s[k].va_cache_poc; val = g_s[k].va_cache_val;
         return true;
        }
      datetime prev = iTime(_Symbol, profile_tf, 1);
      if(prev == 0 || prev >= period)
         return false;
      if(!ASB_EA_BuildValueArea(bars_tf, g_s[k].va_percent, g_s[k].va_volume_type, g_s[k].va_bin_points,
                                prev, period - 1, vah, poc, val))
         return false;
      g_s[k].va_cache_period = period;
      g_s[k].va_cache_vah = vah; g_s[k].va_cache_poc = poc; g_s[k].va_cache_val = val;
      PrintFormat("MSB EA: %s Value Area of the %s bar that began %s: VAH=%s POC=%s VAL=%s.",
                  g_s[k].name, EnumToString(profile_tf), TimeToString(prev, TIME_DATE | TIME_MINUTES),
                  DoubleToString(vah, _Digits), DoubleToString(poc, _Digits), DoubleToString(val, _Digits));
      return true;
     }

   // A source bar that opened at T is closed once T + its length has passed.
   datetime last_closed = TimeCurrent() - PeriodSeconds(bars_tf);
   return ASB_EA_BuildValueArea(bars_tf, g_s[k].va_percent, g_s[k].va_volume_type, g_s[k].va_bin_points,
                                period, last_closed, vah, poc, val);
  }

//+------------------------------------------------------------------+
//| This broker's own name for a plain pair such as "EURUSD" (brokers |
//| add things: "EURUSD.a", "EURUSDm", "mEURUSD"). Also puts it in    |
//| Market Watch, which is what makes its history available - in the  |
//| Strategy Tester too. "" = the broker does not offer it.           |
//+------------------------------------------------------------------+
string ASB_EA_FindSymbol(const string core)
  {
   // Same ending as the chart symbol first (XAUUSDm -> EURUSDm), so the
   // pairs come from the same account type as the symbol being traded.
   if(StringLen(_Symbol) > 6)
     {
      string same = core + StringSubstr(_Symbol, 6);
      if(SymbolSelect(same, true))
         return same;
     }
   if(SymbolSelect(core, true))
      return core;

   // Otherwise the shortest broker symbol whose name contains the pair.
   string best = "";
   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
     {
      string name = SymbolName(i, false);
      if(StringFind(name, core) < 0)
         continue;
      if(best == "" || StringLen(name) < StringLen(best))
         best = name;
     }
   if(best != "" && SymbolSelect(best, true))
      return best;
   return "";
  }

//+------------------------------------------------------------------+
//| Set the USDX filter up for every session that uses it. Each       |
//| session chooses for itself:                                       |
//|  - the dollar index: its broker symbol, or (blank) the index      |
//|    built from the major pairs                                     |
//|  - whether EURUSD must agree as well                              |
//|  - one more symbol of the user's choice that must agree as well   |
//| false = it cannot run at this broker.                             |
//+------------------------------------------------------------------+
bool ASB_EA_UsdxInit()
  {
   bool need_pairs = false, need_eur = false;
   for(int k = 0; k < MSB_SESSIONS; k++)
     {
      if(!g_s[k].use || !g_s[k].use_usdx)
         continue;
      string want = g_s[k].usdx_symbol_txt;
      StringTrimLeft(want);
      StringTrimRight(want);
      if(want != "")
        {
         if(SymbolSelect(want, true))
           {
            g_s[k].usdx_fast_h = iMA(want, g_s[k].usdx_tf, g_s[k].usdx_fast, 0, MODE_EMA, PRICE_CLOSE);
            g_s[k].usdx_slow_h = iMA(want, g_s[k].usdx_tf, g_s[k].usdx_slow, 0, MODE_EMA, PRICE_CLOSE);
            if(g_s[k].usdx_fast_h != INVALID_HANDLE && g_s[k].usdx_slow_h != INVALID_HANDLE)
              {
               g_s[k].usdx_broker = true;
               g_s[k].usdx_symbol = want;
              }
            else
              {
               if(g_s[k].usdx_fast_h != INVALID_HANDLE) { IndicatorRelease(g_s[k].usdx_fast_h); g_s[k].usdx_fast_h = INVALID_HANDLE; }
               if(g_s[k].usdx_slow_h != INVALID_HANDLE) { IndicatorRelease(g_s[k].usdx_slow_h); g_s[k].usdx_slow_h = INVALID_HANDLE; }
              }
           }
         if(!g_s[k].usdx_broker)
            PrintFormat("MSB EA: %s USDX symbol '%s' cannot be used at this broker - its dollar index is built from the major pairs instead.",
                        g_s[k].name, want);
        }
      if(!g_s[k].usdx_broker) need_pairs = true;
      if(g_s[k].usdx_use_eur) need_eur = true;
     }

   for(int i = 0; i < ASB_USDX_PAIRS; i++)
      g_usdx_pair[i] = "";
   string used = "", missing = "";
   if(need_pairs)
     {
      for(int i = 0; i < ASB_USDX_PAIRS; i++)
        {
         g_usdx_pair[i] = ASB_EA_FindSymbol(ASB_USDX_CORE[i]);
         if(g_usdx_pair[i] != "")
            used += (used == "" ? "" : ", ") + g_usdx_pair[i];
         else
            missing += (missing == "" ? "" : ", ") + ASB_USDX_CORE[i];
        }
      // EURUSD, USDJPY and GBPUSD carry 83% of the index - without them it is
      // not a dollar index any more. The other three are used when offered.
      if(g_usdx_pair[0] == "" || g_usdx_pair[1] == "" || g_usdx_pair[2] == "")
        {
         PrintFormat("MSB EA: USDX filter cannot run - this broker does not offer %s. Type the broker's own dollar-index symbol into the session's USDX symbol setting, or switch that USDX filter off.", missing);
         return false;
        }
      if(missing != "")
         PrintFormat("MSB EA: USDX note - %s is not offered by this broker and is left out of the built dollar index.", missing);
     }
   else if(need_eur)
      g_usdx_pair[0] = ASB_EA_FindSymbol(ASB_USDX_CORE[0]);
   if(need_eur && g_usdx_pair[0] == "")
     {
      Print("MSB EA: USDX filter cannot run - EURUSD is not offered by this broker. Switch the 'EURUSD must agree too' setting off.");
      return false;
     }

   for(int k = 0; k < MSB_SESSIONS; k++)
     {
      if(!g_s[k].use || !g_s[k].use_usdx)
         continue;
      string what = "";
      if(g_s[k].usdx_broker)
         what = "broker symbol " + g_s[k].usdx_symbol;
      else
        {
         what = "built from " + used;
         // Ask for each pair's bars once now, so the history is already
         // loading (or, in the tester, loaded) before a breakout needs it.
         for(int i = 0; i < ASB_USDX_PAIRS; i++)
           {
            if(g_usdx_pair[i] == "")
               continue;
            MqlRates warm[];
            CopyRates(g_usdx_pair[i], g_s[k].usdx_tf, 0, 10, warm);
           }
        }

      if(g_s[k].usdx_use_eur)
        {
         g_s[k].usdx_eur_fast_h = iMA(g_usdx_pair[0], g_s[k].usdx_tf, g_s[k].usdx_fast, 0, MODE_EMA, PRICE_CLOSE);
         g_s[k].usdx_eur_slow_h = iMA(g_usdx_pair[0], g_s[k].usdx_tf, g_s[k].usdx_slow, 0, MODE_EMA, PRICE_CLOSE);
         if(g_s[k].usdx_eur_fast_h == INVALID_HANDLE || g_s[k].usdx_eur_slow_h == INVALID_HANDLE)
           {
            PrintFormat("MSB EA: %s USDX filter - EMA on %s failed, error %d.", g_s[k].name, g_usdx_pair[0], GetLastError());
            return false;
           }
         what += ", and " + g_usdx_pair[0] + " must agree";
        }

      string extra = g_s[k].usdx_extra_txt;
      StringTrimLeft(extra);
      StringTrimRight(extra);
      if(extra != "")
        {
         if(!SymbolSelect(extra, true))
           {
            PrintFormat("MSB EA: %s USDX filter - the extra symbol '%s' does not exist at this broker. Correct it or leave that setting blank.",
                        g_s[k].name, extra);
            return false;
           }
         g_s[k].usdx_extra_fast_h = iMA(extra, g_s[k].usdx_tf, g_s[k].usdx_fast, 0, MODE_EMA, PRICE_CLOSE);
         g_s[k].usdx_extra_slow_h = iMA(extra, g_s[k].usdx_tf, g_s[k].usdx_slow, 0, MODE_EMA, PRICE_CLOSE);
         if(g_s[k].usdx_extra_fast_h == INVALID_HANDLE || g_s[k].usdx_extra_slow_h == INVALID_HANDLE)
           {
            PrintFormat("MSB EA: %s USDX filter - EMA on %s failed, error %d.", g_s[k].name, extra, GetLastError());
            return false;
           }
         g_s[k].usdx_extra_symbol = extra;
         what += ", and " + extra + (g_s[k].usdx_extra_inverse ? " (moves against the dollar)" : " (moves with the dollar)") + " must agree";
        }

      PrintFormat("MSB EA: %s USDX filter - dollar index %s. EMA %d/%d on %s, dollar rising allows %s only.",
                  g_s[k].name, what, g_s[k].usdx_fast, g_s[k].usdx_slow, EnumToString(g_s[k].usdx_tf),
                  (g_s[k].usdx_invert ? "buys" : "sells"));
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Fast and slow EMA of the dollar index on its last CLOSED bar.     |
//| false = data not ready yet.                                       |
//+------------------------------------------------------------------+
bool ASB_EA_UsdxEmas(const int k, double &ef, double &es)
  {
   ef = 0.0; es = 0.0;
   int psec = PeriodSeconds(g_s[k].usdx_tf);
   datetime now = TimeCurrent();

   if(g_s[k].usdx_broker)
     {
      // The index symbol may not have ticked yet in the period that just
      // began; its newest bar is then already a finished one.
      datetime t0 = iTime(g_s[k].usdx_symbol, g_s[k].usdx_tf, 0);
      if(t0 == 0)
         return false;
      int shift = (t0 + psec <= now) ? 0 : 1;
      return (ASB_EA_ReadBuf(g_s[k].usdx_fast_h, 0, shift, ef) &&
              ASB_EA_ReadBuf(g_s[k].usdx_slow_h, 0, shift, es) && ef > 0.0 && es > 0.0);
     }

   // Enough bars for the slow EMA to settle fully (its start value has
   // faded to nothing after about six times its period).
   int want = (int)MathMin(3000, MathMax(200, g_s[k].usdx_slow * 6));

   // EURUSD (the biggest part of the index) sets the bar times.
   MqlRates lead[];
   ArraySetAsSeries(lead, false);
   int nb = CopyRates(g_usdx_pair[0], g_s[k].usdx_tf, 0, want + 1, lead);
   while(nb > 0 && lead[nb - 1].time + psec > now)
      nb--;                                   // drop the bar still forming
   if(nb < g_s[k].usdx_slow + 1)
      return false;

   if(g_s[k].usdx_cache_bar == lead[nb - 1].time)
     {
      ef = g_s[k].usdx_cache_ef; es = g_s[k].usdx_cache_es;
      return true;
     }

   double idx[];
   ArrayResize(idx, nb);
   for(int b = 0; b < nb; b++)
     {
      if(lead[b].close <= 0.0)
         return false;
      idx[b] = 50.14348112 * MathPow(lead[b].close, ASB_USDX_WEIGHT[0]);
     }

   for(int s = 1; s < ASB_USDX_PAIRS; s++)
     {
      if(g_usdx_pair[s] == "")
         continue;
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int nr = CopyRates(g_usdx_pair[s], g_s[k].usdx_tf, lead[0].time, lead[nb - 1].time, r);
      if(nr <= 0)
         return false;
      // Each lead bar takes this pair's latest close at or before its time.
      int j = 0;
      for(int b = 0; b < nb; b++)
        {
         while(j + 1 < nr && r[j + 1].time <= lead[b].time)
            j++;
         if(r[j].close <= 0.0)
            return false;
         idx[b] *= MathPow(r[j].close, ASB_USDX_WEIGHT[s]);
        }
     }

   double kf = 2.0 / (g_s[k].usdx_fast + 1.0);
   double ks = 2.0 / (g_s[k].usdx_slow + 1.0);
   ef = idx[0];
   es = idx[0];
   for(int b = 1; b < nb; b++)
     {
      ef += kf * (idx[b] - ef);
      es += ks * (idx[b] - es);
     }
   if(ef <= 0.0 || es <= 0.0)
      return false;

   g_s[k].usdx_cache_bar = lead[nb - 1].time;
   g_s[k].usdx_cache_ef  = ef;
   g_s[k].usdx_cache_es  = es;
   return true;
  }

//+------------------------------------------------------------------+
//| Which way one plain symbol is pointing on its last CLOSED bar:    |
//| +1 = fast EMA above slow (rising), -1 = below (falling), 0 = flat.|
//| false = data not ready yet.                                       |
//+------------------------------------------------------------------+
bool ASB_EA_SymbolTrend(const string symbol, const ENUM_TIMEFRAMES tf, const int fast_h, const int slow_h, int &trend)
  {
   trend = 0;
   // The symbol may not have ticked yet in the period that just began;
   // its newest bar is then already a finished one.
   datetime t0 = iTime(symbol, tf, 0);
   if(t0 == 0)
      return false;
   int shift = (t0 + PeriodSeconds(tf) <= TimeCurrent()) ? 0 : 1;
   double ef = 0.0, es = 0.0;
   if(!ASB_EA_ReadBuf(fast_h, 0, shift, ef) || !ASB_EA_ReadBuf(slow_h, 0, shift, es) || ef <= 0.0 || es <= 0.0)
      return false;
   if(ef > es) trend = +1;
   if(ef < es) trend = -1;
   return true;
  }

//+------------------------------------------------------------------+
//| Which way the DOLLAR is pointing for session k: +1 rising,        |
//| -1 falling, 0 = no clear answer. The dollar index decides; when   |
//| the session also asks for EURUSD and/or an extra symbol, every    |
//| one of them must point the same way, otherwise the answer is 0    |
//| (and the filter then lets no trade through).                      |
//| false = data not ready yet.                                       |
//+------------------------------------------------------------------+
bool ASB_EA_DollarDirection(const int k, int &dollar_dir)
  {
   dollar_dir = 0;
   double ef = 0.0, es = 0.0;
   if(!ASB_EA_UsdxEmas(k, ef, es))
      return false;
   int dir = 0;
   if(ef > es) dir = +1;
   if(ef < es) dir = -1;

   if(g_s[k].usdx_use_eur)
     {
      int eur = 0;
      if(!ASB_EA_SymbolTrend(g_usdx_pair[0], g_s[k].usdx_tf, g_s[k].usdx_eur_fast_h, g_s[k].usdx_eur_slow_h, eur))
         return false;
      if(-eur != dir)                 // EURUSD rising means the dollar is falling
         dir = 0;
     }

   if(g_s[k].usdx_extra_symbol != "")
     {
      int extra = 0;
      if(!ASB_EA_SymbolTrend(g_s[k].usdx_extra_symbol, g_s[k].usdx_tf, g_s[k].usdx_extra_fast_h, g_s[k].usdx_extra_slow_h, extra))
         return false;
      int vote = g_s[k].usdx_extra_inverse ? -extra : extra;
      if(vote != dir)
         dir = 0;
     }

   dollar_dir = dir;
   return true;
  }

//+------------------------------------------------------------------+
//| Trade direction the dollar allows on this (xxxUSD) symbol: dollar |
//| rising = sells only (-1), dollar falling = buys only (+1), no     |
//| clear answer = nothing (0). `invert` swaps buys and sells.        |
//+------------------------------------------------------------------+
int ASB_EA_AllowedFromDollar(const int dollar_dir, const bool invert)
  {
   return invert ? dollar_dir : -dollar_dir;
  }

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpPipPoints < 1)
     {
      Print("MSB EA: InpPipPoints must be at least 1 - every pip calculation in the EA uses it.");
      return (INIT_PARAMETERS_INCORRECT);
     }
   g_pip = ASB_PipSize(_Point, InpPipPoints);
   bool tester = (bool)MQLInfoInteger(MQL_TESTER);
   g_offset = ASB_ServerOffsetSec(tester, InpManualServerOffsetHours);

   ASB_EA_LoadInputs();
   int  sessions_on = 0;
   bool any_usdx = false;
   for(int k = 0; k < MSB_SESSIONS; k++)
     {
      if(!ASB_EA_SetupSession(k))
         return (INIT_PARAMETERS_INCORRECT);
      if(!g_s[k].use)
         continue;
      sessions_on++;
      if(g_s[k].use_usdx) any_usdx = true;
     }
   if(sessions_on == 0)
     {
      Print("MSB EA: all four sessions are switched off - switch at least one on.");
      return (INIT_PARAMETERS_INCORRECT);
     }

   trade.SetExpertMagicNumber(InpMagic);   // set again per session before every order
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(InpSlippagePoints);

   // Each session's own trend EMA, for its quality gate's trend-conflict check.
   for(int k = 0; k < MSB_SESSIONS; k++)
     {
      if(!g_s[k].use)
         continue;
      g_s[k].trend_ma = iMA(_Symbol, g_s[k].trend_tf, g_s[k].trend_ma_period, 0, MODE_EMA, PRICE_CLOSE);
      if(g_s[k].trend_ma == INVALID_HANDLE)
        {
         PrintFormat("MSB EA: %s trend EMA iMA failed, error %d.", g_s[k].name, GetLastError());
         return (INIT_FAILED);
        }
     }

   // Each session's own OBV and the EMA sitting on top of it.
   for(int k = 0; k < MSB_SESSIONS; k++)
     {
      if(!g_s[k].use || !g_s[k].use_obv)
         continue;
      g_s[k].obv_handle = iOBV(_Symbol, g_s[k].obv_tf, g_s[k].obv_volume);
      if(g_s[k].obv_handle == INVALID_HANDLE)
        {
         PrintFormat("MSB EA: %s iOBV failed, error %d.", g_s[k].name, GetLastError());
         return (INIT_FAILED);
        }
      // In MQL5 an EMA can sit directly on top of another indicator's handle.
      g_s[k].obv_ema_handle = iMA(_Symbol, g_s[k].obv_tf, g_s[k].obv_ma, 0, MODE_EMA, g_s[k].obv_handle);
      if(g_s[k].obv_ema_handle == INVALID_HANDLE)
        {
         PrintFormat("MSB EA: %s iMA on the OBV handle failed, error %d.", g_s[k].name, GetLastError());
         return (INIT_FAILED);
        }
     }

   if(any_usdx)
     {
      if(!ASB_EA_UsdxInit())
         return (INIT_FAILED);
     }

   g_last_m1 = 0;
   PrintFormat("MSB EA initialized on %s with %d of 4 sessions switched on. Demo/Strategy Tester first.", _Symbol, sessions_on);
   return (INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Each handle is also set back to "none": the EA keeps its memory when
   // only the inputs are changed, and a filter that has just been switched
   // off must not find a handle left over from before.
   for(int k = 0; k < MSB_SESSIONS; k++)
     {
      if(g_s[k].obv_ema_handle != INVALID_HANDLE) { IndicatorRelease(g_s[k].obv_ema_handle); g_s[k].obv_ema_handle = INVALID_HANDLE; }
      if(g_s[k].obv_handle     != INVALID_HANDLE) { IndicatorRelease(g_s[k].obv_handle);     g_s[k].obv_handle     = INVALID_HANDLE; }
      if(g_s[k].usdx_fast_h    != INVALID_HANDLE) { IndicatorRelease(g_s[k].usdx_fast_h);    g_s[k].usdx_fast_h    = INVALID_HANDLE; }
      if(g_s[k].usdx_slow_h    != INVALID_HANDLE) { IndicatorRelease(g_s[k].usdx_slow_h);    g_s[k].usdx_slow_h    = INVALID_HANDLE; }
      if(g_s[k].usdx_eur_fast_h   != INVALID_HANDLE) { IndicatorRelease(g_s[k].usdx_eur_fast_h);   g_s[k].usdx_eur_fast_h   = INVALID_HANDLE; }
      if(g_s[k].usdx_eur_slow_h   != INVALID_HANDLE) { IndicatorRelease(g_s[k].usdx_eur_slow_h);   g_s[k].usdx_eur_slow_h   = INVALID_HANDLE; }
      if(g_s[k].usdx_extra_fast_h != INVALID_HANDLE) { IndicatorRelease(g_s[k].usdx_extra_fast_h); g_s[k].usdx_extra_fast_h = INVALID_HANDLE; }
      if(g_s[k].usdx_extra_slow_h != INVALID_HANDLE) { IndicatorRelease(g_s[k].usdx_extra_slow_h); g_s[k].usdx_extra_slow_h = INVALID_HANDLE; }
      if(g_s[k].trend_ma       != INVALID_HANDLE) { IndicatorRelease(g_s[k].trend_ma);       g_s[k].trend_ma       = INVALID_HANDLE; }
     }
  }

//+------------------------------------------------------------------+
//| Is trading allowed right now at all (terminal AutoTrading and     |
//| Expert Advisors both on)? Mirrors CRT_Sweep_AutoBest_EA_MT5.mq5.  |
//+------------------------------------------------------------------+
bool ASB_EA_TradingAllowed()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   static bool s_was_allowed = true;
   bool allowed = ASB_EA_TradingAllowed();
   if(!allowed)
     {
      if(s_was_allowed)
         Print("MSB EA: trading is not allowed right now (AutoTrading or Expert Advisors off) - no entries or management until it is back on.");
      s_was_allowed = false;
      return;
     }
   if(!s_was_allowed)
     {
      Print("MSB EA: trading is allowed again - resuming.");
      s_was_allowed = true;
     }

   ASB_EA_CheckDayEnd();     // every tick
   ASB_EA_ManageM1();        // once per closed M1 bar
   ASB_EA_CheckSignalBar();  // once per closed SignalTF bar
   ASB_EA_WickBreakTick();   // every tick, only while wick-break module A is armed
  }

//+------------------------------------------------------------------+
//| Breakout window end: close own positions, delete own pendings.    |
//| Worked out per trade from its own open time and its session, so   |
//| it needs no shared state and works correctly across a restart.    |
//+------------------------------------------------------------------+
void ASB_EA_CheckDayEnd()
  {
   datetime now = TimeTradeServer();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      int k = ASB_EA_SessionOfMagic(PositionGetInteger(POSITION_MAGIC));
      if(k < 0 || !g_s[k].close_at_window_end) continue;   // each session has its own switch

      datetime open_time  = (datetime)PositionGetInteger(POSITION_TIME);
      datetime window_end = ASB_CycleStart(open_time, g_s[k].start_min) + g_s[k].len_sec + g_s[k].window_sec;
      if(now < window_end) continue;

      if(trade.PositionClose(ticket))
         PrintFormat("MSB EA: %s breakout window ended - closed position ticket %I64u.", g_s[k].name, ticket);
      else
         PrintFormat("MSB EA: %s window end - CLOSE FAILED ticket %I64u, retcode=%u %s.",
                     g_s[k].name, ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      int k = ASB_EA_SessionOfMagic(OrderGetInteger(ORDER_MAGIC));
      if(k < 0 || !g_s[k].close_at_window_end) continue;   // each session has its own switch

      // These pendings already carry an expiration = the end of their own
      // breakout window, so the broker should expire them on its own; this
      // is a belt-and-braces explicit cleanup in case that has not happened.
      datetime exp = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      if(exp <= 0 || now < exp) continue;

      if(trade.OrderDelete(ticket))
         PrintFormat("MSB EA: %s breakout window ended - deleted pending order ticket %I64u.", g_s[k].name, ticket);
      else
         PrintFormat("MSB EA: %s window end - DELETE FAILED ticket %I64u, retcode=%u %s.",
                     g_s[k].name, ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Structure trail: the last swing confirmed AFTER the position      |
//| opened, built fresh from StructTF rates each management pass.     |
//| 0.0 = no usable swing yet.                                        |
//+------------------------------------------------------------------+
double ASB_EA_LastConfirmedSwing(const int k, const int dir, const datetime open_time)
  {
   MqlRates stf[];
   ArraySetAsSeries(stf, false);
   datetime from = TimeCurrent() - 5 * 86400;
   int got = CopyRates(_Symbol, g_s[k].struct_tf, from, TimeCurrent(), stf);
   if(got <= 0)
      return 0.0;

   double   level[];
   datetime ctime[];
   int n = ASB_BuildSwings(stf, got, PeriodSeconds(g_s[k].struct_tf), g_s[k].swing_bars, dir, level, ctime);

   datetime now = TimeCurrent();
   double last = 0.0;
   for(int i = 0; i < n; i++)
     {
      if(ctime[i] > now) break;
      if(ctime[i] >= open_time) last = level[i];
     }
   return last;
  }

//+------------------------------------------------------------------+
//| Management: once per closed M1 bar, for every own-magic position. |
//| Best price and the last closed M1 close are both re-derived from  |
//| CopyRates from the position's own open time - no tick memory, so  |
//| a restart never loses track of the trade's true best price.       |
//+------------------------------------------------------------------+
void ASB_EA_ManageM1()
  {
   datetime cur = iTime(_Symbol, PERIOD_M1, 0);
   if(cur == 0 || cur == g_last_m1)
      return;
   g_last_m1 = cur;
   datetime last_closed = iTime(_Symbol, PERIOD_M1, 1);
   if(last_closed == 0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      int k = ASB_EA_SessionOfMagic(PositionGetInteger(POSITION_MAGIC));
      if(k < 0) continue;      // each trade is managed with its OWN session's exit settings

      long   type       = PositionGetInteger(POSITION_TYPE);
      int    dir        = (type == POSITION_TYPE_BUY) ? +1 : -1;
      double entry      = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur_sl      = PositionGetDouble(POSITION_SL);
      double cur_tp      = PositionGetDouble(POSITION_TP);
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      if(open_time > last_closed)
         continue;   // opened this same bar - nothing closed since entry yet

      MqlRates m1[];
      ArraySetAsSeries(m1, false);
      int got = CopyRates(_Symbol, PERIOD_M1, open_time, last_closed, m1);
      if(got <= 0)
        {
         PrintFormat("MSB EA: manage skipped ticket %I64u - CopyRates M1 failed, error %d.", ticket, GetLastError());
         continue;
        }

      double best = entry;
      for(int b = 0; b < got; b++)
        {
         double ext = (dir > 0) ? m1[b].high : m1[b].low;
         if((ext - best) * dir > 0) best = ext;
        }
      double best_fav_pips = ASB_ToPips((best - entry) * dir, g_pip);
      double close_price   = m1[got - 1].close;

      double new_sl = cur_sl;

      if(g_s[k].use_be)
        {
         double cand = ASB_EA_BECand(dir, entry, best_fav_pips, g_s[k].be_trigger, g_s[k].be_lock, g_pip, new_sl);
         if(cand != 0.0) new_sl = cand;
        }

      if(g_s[k].trail_mode == TrailPips)
        {
         double cand = ASB_EA_TrailPipsCand(dir, entry, best, g_s[k].trail_start, g_s[k].trail_dist, g_pip, new_sl);
         if(cand != 0.0) new_sl = cand;
        }
      else if(g_s[k].trail_mode == TrailStructure)
        {
         double swing = ASB_EA_LastConfirmedSwing(k, dir, open_time);
         if(swing != 0.0)
           {
            double cand = ASB_EA_TrailStructCand(dir, swing, g_s[k].struct_buffer, g_pip, new_sl, close_price);
            if(cand != 0.0) new_sl = cand;
           }
        }

      // Compare NORMALIZED values with a half-point epsilon, not exact
      // equality - new_sl is computed from live prices and can differ from
      // cur_sl (read back from the broker, already normalized) by less than
      // one point due to floating-point noise even when nothing has really
      // changed; sending an identical-looking modify anyway just invites a
      // broker "no changes" rejection (retcode=10025) for no benefit.
      double sln = NormalizeDouble(new_sl, _Digits);
      if(MathAbs(sln - cur_sl) > 0.5 * _Point)
        {
         double mgmt_ref = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(!ASB_EA_StopOK(mgmt_ref, sln))
            PrintFormat("MSB EA: ticket %I64u stop-move skipped - new stop %s is inside the broker's stop level (kept old stop %s).",
                        ticket, DoubleToString(sln, _Digits), DoubleToString(cur_sl, _Digits));
         else if(trade.PositionModify(ticket, sln, cur_tp))
            PrintFormat("MSB EA: ticket %I64u stop moved to %s (best %.1fp in profit).",
                        ticket, DoubleToString(sln, _Digits), best_fav_pips);
         else
            PrintFormat("MSB EA: ticket %I64u stop-move FAILED, retcode=%u %s.",
                        ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
        }
     }
  }

//+------------------------------------------------------------------+
//| Detection gate: each session once per closed bar of ITS OWN       |
//| signal timeframe.                                                 |
//+------------------------------------------------------------------+
void ASB_EA_CheckSignalBar()
  {
   for(int k = 0; k < MSB_SESSIONS; k++)
     {
      if(!g_s[k].use)
         continue;
      datetime cur = iTime(_Symbol, g_s[k].sig_tf, 0);
      if(cur == 0 || cur == g_s[k].last_sig_bar)
         continue;
      g_s[k].last_sig_bar = cur;
      ASB_EA_OnNewSignalBar(k);
     }
  }

//+------------------------------------------------------------------+
//| Restart-safe rescan: mark the directions one session has already  |
//| handled in its current cycle - from open positions, pending       |
//| orders and the deal history - so a restart never doubles an entry.|
//+------------------------------------------------------------------+
void ASB_EA_RescanToday(const int k, const ASBDay &today_day)
  {
   datetime now = TimeCurrent();

   if(HistorySelect(today_day.start, now))
     {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong dt = HistoryDealGetTicket(i);
         if(dt == 0) continue;
         if(HistoryDealGetString(dt, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetInteger(dt, DEAL_MAGIC) != g_s[k].magic) continue;
         if((long)HistoryDealGetInteger(dt, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         long dtype = HistoryDealGetInteger(dt, DEAL_TYPE);
         if(dtype == DEAL_TYPE_BUY)  g_s[k].bull_done = true;
         if(dtype == DEAL_TYPE_SELL) g_s[k].bear_done = true;
        }
     }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != g_s[k].magic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY)  g_s[k].bull_done = true;
      if(type == POSITION_TYPE_SELL) g_s[k].bear_done = true;
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != g_s[k].magic) continue;
      long otype = OrderGetInteger(ORDER_TYPE);
      if(otype == ORDER_TYPE_BUY_LIMIT)  g_s[k].bull_done = true;
      if(otype == ORDER_TYPE_SELL_LIMIT) g_s[k].bear_done = true;
     }

   PrintFormat("MSB EA: %s startup rescan - bull_done=%s bear_done=%s.", g_s[k].name,
               (g_s[k].bull_done ? "true" : "false"), (g_s[k].bear_done ? "true" : "false"));
  }

//+------------------------------------------------------------------+
//| Quality gate, adapted from the indicator's ASB_ComputeQualityNow  |
//| for the EA's own inputs. Same checks; big-candle uses today's     |
//| FIRST event bar's ATR (whichever direction happened first).       |
//| Everything here is day-wide (including both_broken - the second   |
//| breakout on a both-broken day is meant to be blocked when the     |
//| quality filter is on, per the avoid-list rule) EXCEPT              |
//| trend_conflict, which is evaluated against the CANDIDATE event's  |
//| own `dir` - a bull breakout and a bear breakout on the same day   |
//| can disagree with the trend in opposite ways. The trend EMA value |
//| is read ONCE per bar by the caller and passed in (ma_ok/ma_val),  |
//| so calling this once per event stays cheap.                       |
//+------------------------------------------------------------------+
void ASB_EA_BuildQuality(const int k, const MqlRates &sig[], const int got, const ASBDay &days[], const ASBEvent &events[],
                         const int today, const int day_status, const int dir,
                         const bool ma_ok, const double ma_val, ASBQuality &q)
  {
   ASB_QualityInit(q);

   double range_today = days[today].high - days[today].low;
   double sum = 0; int cnt = 0;
   for(int d = MathMax(0, today - g_s[k].avg_range_days); d < today; d++)
     {
      if(!days[d].has_range)
         continue;                          // a day with no session bars has no range to average
      sum += days[d].high - days[d].low;
      cnt++;
     }
   if(cnt > 0)
     {
      double avg = sum / cnt;
      if(range_today > avg * g_s[k].wide_mult) q.wide_range = true;
      if(g_s[k].use_narrow && range_today < avg * g_s[k].narrow_mult) q.narrow_range = true;
     }

   q.both_broken = (day_status == ASB_ST_BOTH);
   q.failed_bo   = (day_status == ASB_ST_FAILED);

   datetime first_ev_time = 0; bool have_ev = false;
   for(int i = 0; i < ArraySize(events); i++)
      if(events[i].day_idx == today && (!have_ev || events[i].time < first_ev_time))
        { first_ev_time = events[i].time; have_ev = true; }
   if(have_ev)
      for(int b = got - 1; b >= 0; b--)
         if(sig[b].time == first_ev_time)
           {
            double atr = ASB_ATRAt(sig, got, b, g_s[k].atr_period);
            if(atr > 0 && (sig[b].high - sig[b].low) > atr * g_s[k].big_candle_mult)
               q.big_candle = true;
            break;
           }

   q.spread_high = (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > g_s[k].max_spread);

   if(ma_ok && dir != 0)
     {
      bool up = (SymbolInfoDouble(_Symbol, SYMBOL_BID) > ma_val);
      if((dir > 0 && !up) || (dir < 0 && up))
         q.trend_conflict = true;
     }

   int news = -1;
   if(g_s[k].use_news) news = ASB_MinutesToHighImpactNews(g_s[k].news_minutes);
   q.news_near = (news >= 0);

   q.rollover = ASB_InWindow(ASB_MinOfDay(TimeTradeServer()), g_s[k].roll_start, g_s[k].roll_end);
  }

//+------------------------------------------------------------------+
//| Build this event's OWN direction's quality (trend_conflict is     |
//| per-direction) and try it, sharing the once-per-bar trend EMA     |
//| read the caller already did.                                      |
//+------------------------------------------------------------------+
void ASB_EA_EvaluateDirection(const int k, const ASBEvent &ev, const MqlRates &sig[], const int got,
                              const ASBDay &days[], const ASBEvent &events[],
                              const int today, const int day_status,
                              const bool ma_ok, const double ma_val)
  {
   ASBQuality q;
   ASB_EA_BuildQuality(k, sig, got, days, events, today, day_status, ev.dir, ma_ok, ma_val, q);
   string why;
   int qstat = ASB_QualityStatus(q, why);
   ASB_EA_TryEnter(k, ev, qstat, why);
  }

//+------------------------------------------------------------------+
//| One session, once per closed SignalTF bar: rebuild its picture    |
//| and try every direction it has not handled yet in this cycle.     |
//+------------------------------------------------------------------+
void ASB_EA_ProcessSession(const int k, const MqlRates &sig[], const int got, const int tf_sec,
                           const bool ma_ok, const double ma_val)
  {
   ASBDay   days[];
   ASBEvent events[];
   int nd = ASB_BuildDays(sig, got, g_s[k].start_min, g_s[k].len_sec, g_s[k].window_sec, days);
   if(nd == 0)
      return;
   ASB_DetectEvents(sig, got, days, nd, tf_sec, g_s[k].start_min, events);

   int today = nd - 1;
   if(g_s[k].track_start != days[today].start)
     {
      g_s[k].track_start = days[today].start;
      g_s[k].bull_done = false;
      g_s[k].bear_done = false;
      PrintFormat("MSB EA: %s session of %s - entry flags reset.", g_s[k].name,
                  TimeToString(days[today].start, TIME_DATE | TIME_MINUTES));
     }

   if(!g_s[k].rescanned)
     {
      ASB_EA_RescanToday(k, days[today]);
      g_s[k].rescanned = true;
     }

   int first_dir = 0;
   int day_status = ASB_DayStatus(events, ArraySize(events), today, days[today].failed, first_dir);

   // Session-wide snapshot for the log only (uses first_dir) - the actual
   // per-event gating below always recomputes quality against that event's
   // OWN direction. Printed only once a breakout exists and only when it
   // changes, to keep backtest logs readable.
   if(first_dir != 0)
     {
      ASBQuality q;
      ASB_EA_BuildQuality(k, sig, got, days, events, today, day_status, first_dir, ma_ok, ma_val, q);
      string why;
      int qstat = ASB_QualityStatus(q, why);
      if(qstat != g_s[k].last_qstat || why != g_s[k].last_why)
        {
         PrintFormat("MSB EA: %s quality=%s%s.", g_s[k].name,
                     (qstat == 2 ? "TRADE OK" : (qstat == 1 ? "CAUTION" : "AVOID")),
                     (why == "" ? "" : (" (" + why + ")")));
         g_s[k].last_qstat = qstat;
         g_s[k].last_why   = why;
        }
     }

   // Wick-break entry (modules A and B), when switched on.
   bool wb_on = (InpWB_UseA || InpWB_UseB);
   if(wb_on)
      ASB_EA_WickBreakOnBar(k, sig, got, days, events, today, day_status, ma_ok, ma_val);
   if(wb_on && !InpWB_KeepNormalEntry)
      return;                                       // wick-break replaces the normal breakout entry

   datetime now = TimeCurrent();
   for(int i = 0; i < ArraySize(events); i++)
     {
      if(events[i].day_idx != today) continue;
      if(now >= events[i].day_end) continue;        // its breakout window has closed
      if(events[i].dir > 0 && !g_s[k].bull_done)
         ASB_EA_EvaluateDirection(k, events[i], sig, got, days, events, today, day_status, ma_ok, ma_val);
      if(events[i].dir < 0 && !g_s[k].bear_done)
         ASB_EA_EvaluateDirection(k, events[i], sig, got, days, events, today, day_status, ma_ok, ma_val);
     }
  }

//+------------------------------------------------------------------+
//| A new bar on session k's signal timeframe: read its bars and let  |
//| the session work on them.                                         |
//+------------------------------------------------------------------+
void ASB_EA_OnNewSignalBar(const int k)
  {
   int tf_sec = PeriodSeconds(g_s[k].sig_tf);
   if(tf_sec <= 0)
      return;
   int days_lookback = MathMax(g_s[k].avg_range_days, 5) + 5;
   int bars_needed = days_lookback * (int)(86400 / tf_sec) + 20;

   // No-look-ahead rule: start_pos=1, never 0. Shift 0 is the bar that just
   // opened this same tick (still forming) - reading it here would let a
   // detection decision see a candle before it has actually closed.
   MqlRates sig[];
   ArraySetAsSeries(sig, false);
   int got = CopyRates(_Symbol, g_s[k].sig_tf, 1, bars_needed, sig);
   if(got <= 0)
     {
      PrintFormat("MSB EA: %s CopyRates on its signal timeframe failed, error %d.", g_s[k].name, GetLastError());
      return;
     }

   // This session's trend EMA, for its quality gate.
   double ma_val = 0.0;
   bool   ma_ok  = false;
   if(g_s[k].trend_ma != INVALID_HANDLE)
     {
      double mabuf[1];
      if(CopyBuffer(g_s[k].trend_ma, 0, 0, 1, mabuf) == 1)
        {
         ma_val = mabuf[0];
         ma_ok  = true;
        }
     }

   ASB_EA_CandleExits(k, sig, got, tf_sec);   // before any new entry is considered
   ASB_EA_ProcessSession(k, sig, got, tf_sec, ma_ok, ma_val);
  }

//+------------------------------------------------------------------+
//| Evaluate every enabled filter for one event: true = all passed.   |
//| Skips (no trade this bar, may retry the next one) are logged      |
//| plainly; nothing here marks the direction done - only an actual   |
//| order placement does.                                             |
//+------------------------------------------------------------------+
bool ASB_EA_FiltersOK(const int k, const ASBEvent &ev, const int qstat, const string why)
  {
   string dirtxt = g_s[k].name + ((ev.dir > 0) ? " BULL" : " BEAR");

   bool obv_pass = true;
   if(g_s[k].use_obv)
     {
      bool needEma   = (g_s[k].obv_mode == OBV_VS_EMA || g_s[k].obv_mode == OBV_BOTH);
      bool needSlope = (g_s[k].obv_mode == OBV_SLOPE  || g_s[k].obv_mode == OBV_BOTH);
      double obv_now = 0, obv_ema = 0;
      if(needEma)
        {
         if(!ASB_EA_ReadBuf(g_s[k].obv_handle, 0, 1, obv_now) || !ASB_EA_ReadBuf(g_s[k].obv_ema_handle, 0, 1, obv_ema))
           {
            PrintFormat("MSB EA: %s skipped - OBV/EMA data not ready.", dirtxt);
            return false;
           }
         if(!CRTOBV_PassEma(obv_now, obv_ema, ev.dir)) obv_pass = false;
        }
      if(obv_pass && needSlope)
        {
         if(!needEma && !ASB_EA_ReadBuf(g_s[k].obv_handle, 0, 1, obv_now))
           {
            PrintFormat("MSB EA: %s skipped - OBV data not ready.", dirtxt);
            return false;
           }
         double obv_past = 0;
         int back = 1 + MathMax(g_s[k].obv_slope, 1);
         if(!ASB_EA_ReadBuf(g_s[k].obv_handle, 0, back, obv_past))
           {
            PrintFormat("MSB EA: %s skipped - OBV history not ready.", dirtxt);
            return false;
           }
         if(!CRTOBV_PassSlope(obv_now, obv_past, ev.dir)) obv_pass = false;
        }
     }

   bool va_pass = true;
   double va_vah = 0, va_poc = 0, va_val = 0;
   if(g_s[k].use_va)
     {
      if(!ASB_EA_BuiltInValueArea(k, va_vah, va_poc, va_val))
        {
         PrintFormat("MSB EA: %s skipped - Value Area levels not ready.", dirtxt);
         return false;
        }
      bool needDir  = (g_s[k].va_mode == VA_DIRECTION  || g_s[k].va_mode == VA_BOTH);
      bool needConf = (g_s[k].va_mode == VA_CONFLUENCE || g_s[k].va_mode == VA_BOTH);
      if(needDir && !CRTVA_PassDirection(g_s[k].va_line, va_vah, va_poc, va_val, ev.entry, ev.dir))
         va_pass = false;
      if(va_pass && needConf)
        {
         double swept = (ev.dir > 0) ? ev.range_hi : ev.range_lo;
         double tol = g_s[k].va_tol * g_pip;
         if(!CRTVA_PassConfluence(va_vah, va_poc, va_val, swept, tol))
            va_pass = false;
        }
      if(!va_pass)
         PrintFormat("MSB EA: %s blocked by Value Area filter (VAH=%s POC=%s VAL=%s).",
                     dirtxt, DoubleToString(va_vah, _Digits), DoubleToString(va_poc, _Digits), DoubleToString(va_val, _Digits));
     }

   int usdx_allowed = 0;
   if(g_s[k].use_usdx)
     {
      int dollar_dir = 0;
      if(!ASB_EA_DollarDirection(k, dollar_dir))
        {
         PrintFormat("MSB EA: %s skipped - USDX data not ready.", dirtxt);
         return false;
        }
      usdx_allowed = ASB_EA_AllowedFromDollar(dollar_dir, g_s[k].usdx_invert);
     }

   bool pass = ASB_EA_FiltersPass(ev.dir, qstat, g_s[k].use_quality, g_s[k].only_ok,
                                  g_s[k].use_obv, obv_pass, g_s[k].use_va, va_pass, g_s[k].use_usdx, usdx_allowed);
   if(!pass)
     {
      PrintFormat("MSB EA: %s breakout blocked - quality=%d(%s) obv=%s/%s va=%s/%s usdx=%s/allowed%d.",
                  dirtxt, qstat, why,
                  (g_s[k].use_obv ? "on" : "off"), (obv_pass ? "pass" : "fail"),
                  (g_s[k].use_va ? "on" : "off"), (va_pass ? "pass" : "fail"),
                  (g_s[k].use_usdx ? "on" : "off"), usdx_allowed);
      return false;
     }

   long spread_pts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread_pts > g_s[k].max_spread)
     {
      PrintFormat("MSB EA: %s skipped - spread %d points over the %d limit.", dirtxt, (int)spread_pts, g_s[k].max_spread);
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| The normal breakout entry: every filter must pass, then place it. |
//+------------------------------------------------------------------+
void ASB_EA_TryEnter(const int k, const ASBEvent &ev, const int qstat, const string why)
  {
   if(ASB_EA_FiltersOK(k, ev, qstat, why))
      ASB_EA_PlaceEntry(k, ev);
  }

//+------------------------------------------------------------------+
//| Broker stop-level check: is one price far enough from ref_price?  |
//+------------------------------------------------------------------+
bool ASB_EA_StopOK(const double ref_price, const double price)
  {
   long stop_pts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stop_pts <= 0)
      return true;
   double min_dist = stop_pts * _Point;
   return (MathAbs(ref_price - price) >= min_dist);
  }

//+------------------------------------------------------------------+
//| Broker stop-level check: is sl/tp far enough from ref_price?      |
//+------------------------------------------------------------------+
bool ASB_EA_StopsOK(const double ref_price, const double sl, const double tp)
  {
   return (ASB_EA_StopOK(ref_price, sl) && ASB_EA_StopOK(ref_price, tp));
  }

void ASB_EA_MarkDone(const int k, const int dir)
  {
   if(dir > 0) g_s[k].bull_done = true; else g_s[k].bear_done = true;
  }

//+------------------------------------------------------------------+
//| Is there ALREADY an own-magic position or pending order for this  |
//| symbol+direction, right now? A final live safety net checked      |
//| immediately before every order send, independent of the in-memory |
//| bull_done/bear_done flags   - so if a live OrderSend response is |
//| ever delayed or lost (a network timeout) and this same direction  |
//| gets evaluated again before the flag was set, the trade already   |
//| sitting at the broker is still found and a duplicate is refused.  |
//| Same position/order scan pattern as ASB_EA_RescanToday, reused     |
//| here scoped to just one direction.                                 |
//+------------------------------------------------------------------+
bool ASB_EA_HasOwnTradeForDir(const int k, const int dir)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != g_s[k].magic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(dir > 0 && type == POSITION_TYPE_BUY)  return true;
      if(dir < 0 && type == POSITION_TYPE_SELL) return true;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != g_s[k].magic) continue;
      long otype = OrderGetInteger(ORDER_TYPE);
      if(dir > 0 && otype == ORDER_TYPE_BUY_LIMIT)  return true;
      if(dir < 0 && otype == ORDER_TYPE_SELL_LIMIT) return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Is a RetestLimit level too close to the CURRENT market to leave a |
//| resting limit order there at all? A broker will reject a limit    |
//| placed inside its own stops/freeze distance even when the level   |
//| has not technically been crossed yet - and that situation IS a    |
//| retest happening live, in real time (price hovering just short of |
//| the level), not a gap to wait out. Always re-reads fresh ask/bid,  |
//| stops level, and freeze level, so it is safe to call again later   |
//| (e.g. right after a rejected OrderSend) for an up-to-date answer.  |
//+------------------------------------------------------------------+
bool ASB_EA_LevelWithinStopsDistance(const int dir, const double level)
  {
   long stop_pts   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_pts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double min_dist = (double)MathMax(stop_pts, freeze_pts) * _Point + 2.0 * (ask - bid);
   double dist = (dir > 0) ? (ask - level) : (level - bid);
   return (dist <= min_dist);
  }

//+------------------------------------------------------------------+
//| Shared RetestLimit market fallback: enter right now at the current |
//| ask/bid, with SL/TP measured from that ACTUAL fill price (never    |
//| the level - a level-based stop would no longer describe the trade |
//| really being opened). Used both when the level was already        |
//| retested before a limit order was even attempted, and when a limit |
//| order gets rejected because price crossed the level in the gap     |
//| between our check and the (simulated) broker processing it. Marks |
//| the direction done only on a successful fill.                     |
//+------------------------------------------------------------------+
void ASB_EA_MarketFallback(const int k, const ASBEvent &ev, const double sl_dist, const double tp_dist, const string reason)
  {
   string side   = (ev.dir > 0) ? "BUY" : "SELL";
   string dirtxt = g_s[k].name + " " + side;
   trade.SetExpertMagicNumber((ulong)g_s[k].magic);
   bool lots_ok = true;
   double lots = ASB_EA_LotsFor(k, sl_dist, lots_ok);
   if(!lots_ok)
     {
      PrintFormat("MSB EA: %s skipped - no lot size could be worked out for this trade (see the line above).", dirtxt);
      return;
     }
   if(ASB_EA_HasOwnTradeForDir(k, ev.dir))
     {
      PrintFormat("MSB EA: %s skipped - %s, but an own-magic position or pending order for this direction already exists (double-order guard).",
                  dirtxt, reason);
      return;
     }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (ev.dir > 0) ? ask : bid;
   double sl = NormalizeDouble(price - ev.dir * sl_dist, _Digits);
   double tp = NormalizeDouble(price + ev.dir * tp_dist, _Digits);
   if(!ASB_EA_StopsOK(price, sl, tp))
     {
      PrintFormat("MSB EA: %s skipped - %s and SL/TP too close to market price for the broker's stop level.", dirtxt, reason);
      return;
     }
   bool ok = (ev.dir > 0) ? trade.Buy(lots, _Symbol, 0.0, sl, tp, g_s[k].tag + " Rt" + side)
                          : trade.Sell(lots, _Symbol, 0.0, sl, tp, g_s[k].tag + " Rt" + side);
   if(ok)
     {
      ASB_EA_MarkDone(k, ev.dir);
      PrintFormat("MSB EA: %s %s - entering at market, stops from market price. Entry=%s SL=%s TP=%s.",
                  dirtxt, reason, DoubleToString(price, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits));
     }
   else
      PrintFormat("MSB EA: %s market fallback order FAILED, retcode=%u %s.", dirtxt, trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Place the entry for a passed event. Marks the direction done only |
//| on an actual order placement (market fill or pending order sent). |
//+------------------------------------------------------------------+
void ASB_EA_PlaceEntry(const int k, const ASBEvent &ev)
  {
   string side   = (ev.dir > 0) ? "BUY" : "SELL";
   string dirtxt = g_s[k].name + " " + side;
   trade.SetExpertMagicNumber((ulong)g_s[k].magic);
   double sl_dist = g_s[k].sl_pips * g_pip;
   double tp_dist = g_s[k].tp_pips * g_pip;
   bool lots_ok = true;
   double lots = ASB_EA_LotsFor(k, sl_dist, lots_ok);
   if(!lots_ok)
     {
      PrintFormat("MSB EA: %s skipped - no lot size could be worked out for this trade (see the line above).", dirtxt);
      return;
     }

   if(g_s[k].entry_mode == EntryBreakoutClose)
     {
      if(ASB_EA_HasOwnTradeForDir(k, ev.dir))
        {
         PrintFormat("MSB EA: %s skipped - an own-magic position or pending order for this direction already exists (double-order guard).", dirtxt);
         return;
        }
      double price = (ev.dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = NormalizeDouble(price - ev.dir * sl_dist, _Digits);
      double tp = NormalizeDouble(price + ev.dir * tp_dist, _Digits);
      if(!ASB_EA_StopsOK(price, sl, tp))
        {
         PrintFormat("MSB EA: %s skipped - SL/TP too close to price for the broker's stop level.", dirtxt);
         return;
        }
      bool ok = (ev.dir > 0) ? trade.Buy(lots, _Symbol, 0.0, sl, tp, g_s[k].tag + " " + side)
                             : trade.Sell(lots, _Symbol, 0.0, sl, tp, g_s[k].tag + " " + side);
      if(ok)
        {
         ASB_EA_MarkDone(k, ev.dir);
         PrintFormat("MSB EA: %s market order sent at %s SL=%s TP=%s.",
                     dirtxt, DoubleToString(price, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits));
        }
      else
         PrintFormat("MSB EA: %s market order FAILED, retcode=%u %s.", dirtxt, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return;
     }

   // RetestLimit
   double level = (ev.dir > 0) ? ev.range_hi : ev.range_lo;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool already_retested = (ev.dir > 0) ? (level >= ask) : (level <= bid);

   if(already_retested)
     {
      // A real limit order needs to sit on the far side of the market (a
      // BuyLimit below the ask, a SellLimit above the bid). If price has
      // already come back through the level, that requirement is broken -
      // so enter at market right now instead.
      ASB_EA_MarketFallback(k, ev, sl_dist, tp_dist, "retest level already passed");
      return;
     }

   // Even short of the level, a broker will not accept a limit order placed
   // inside its own stops/freeze distance from the market - which is exactly
   // what happens right when a retest is actually happening in real time
   // (price hovering just short of the level). Treat that the same way as
   // already-retested: the retest is live, enter at market now rather than
   // trying (and failing) to leave a resting limit order there.
   if(ASB_EA_LevelWithinStopsDistance(ev.dir, level))
     {
      ASB_EA_MarketFallback(k, ev, sl_dist, tp_dist, "level within broker stops distance - retest is live");
      return;
     }

   if(ASB_EA_HasOwnTradeForDir(k, ev.dir))
     {
      PrintFormat("MSB EA: %s limit skipped - an own-magic position or pending order for this direction already exists (double-order guard).", dirtxt);
      return;
     }

   double sl = NormalizeDouble(level - ev.dir * sl_dist, _Digits);
   double tp = NormalizeDouble(level + ev.dir * tp_dist, _Digits);
   double lvln = NormalizeDouble(level, _Digits);
   if(!ASB_EA_StopsOK(lvln, sl, tp))
     {
      PrintFormat("MSB EA: %s limit skipped - SL/TP too close to the level for the broker's stop level.", dirtxt);
      return;
     }
   bool ok = (ev.dir > 0) ? trade.BuyLimit(lots, lvln, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, ev.day_end, g_s[k].tag + " Rt" + side)
                          : trade.SellLimit(lots, lvln, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, ev.day_end, g_s[k].tag + " Rt" + side);
   if(ok)
     {
      ASB_EA_MarkDone(k, ev.dir);
      PrintFormat("MSB EA: %s limit order placed at level %s SL=%s TP=%s, expires at window end %s.",
                  dirtxt, DoubleToString(lvln, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits),
                  TimeToString(ev.day_end, TIME_DATE | TIME_MINUTES));
      return;
     }

   uint retcode = trade.ResultRetcode();
   if(retcode == TRADE_RETCODE_INVALID_PRICE || retcode == TRADE_RETCODE_INVALID_STOPS)
     {
      // Belt-and-braces second layer, in case the two checks above somehow
      // missed it (e.g. the broker's own distance settings changed, or a
      // genuine same-tick price move happened): re-read the market NOW and
      // re-decide with fresh prices whether the retest is live right now,
      // either because the level has since been crossed OR because it now
      // sits within the broker's stops/freeze distance - either way the
      // trade should not be lost. Otherwise leave the event un-marked (no
      // MarkDone happened above, since ok was false) so the next closed
      // SignalTF bar retries this same placement with fresh prices.
      double ask2 = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid2 = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      bool crossed_now = (ev.dir > 0) ? (level >= ask2) : (level <= bid2);
      bool live_now = crossed_now || ASB_EA_LevelWithinStopsDistance(ev.dir, level);
      if(live_now)
         ASB_EA_MarketFallback(k, ev, sl_dist, tp_dist, "limit rejected - price crossed level");
      else
         PrintFormat("MSB EA: %s limit rejected - will retry next bar (retcode=%u %s).",
                     dirtxt, retcode, trade.ResultRetcodeDescription());
      return;
     }

   PrintFormat("MSB EA: %s limit order FAILED, retcode=%u %s.", dirtxt, retcode, trade.ResultRetcodeDescription());
  }
//+------------------------------------------------------------------+
//| WICK-BREAK ENTRY                                                  |
//|                                                                  |
//| Break candle: a closed candle (after the session has ended) whose |
//| wick goes beyond the session high/low while the candle before it  |
//| had not - the candle that first pokes through the level.          |
//| Trigger price: the break candle's wick tip, plus the set % of its |
//| body further in the break direction.                              |
//|   Module A: during the very next candle, enter the moment the bid |
//|             reaches the trigger. One attempt per candle.          |
//|   Module B: when that next candle closes, enter if its CLOSE is   |
//|             at or beyond the trigger.                             |
//| Stop: exactly on the confirming candle's opposite wick (for       |
//| module A, the wick as it stands at the moment of entry). It       |
//| replaces the session's stop-loss pips, and is moved out only when |
//| the wick is closer than the spread / broker stop level allows.    |
//| Take profit, break-even and trailing: the session's own settings. |
//| Every filter of the session (quality, OBV, Value Area, USDX,      |
//| spread) applies, and a direction is still traded once per cycle.  |
//+------------------------------------------------------------------+
bool ASB_EA_IsBreakCandle(const MqlRates &sig[], const int i, const int dir, const double level, const datetime sess_end)
  {
   if(i < 1 || sig[i].time < sess_end)
      return false;
   if(dir > 0)
      return (sig[i].high > level && sig[i - 1].high <= level);
   return (sig[i].low < level && sig[i - 1].low >= level);
  }

double ASB_EA_WickBreakTrigger(const MqlRates &brk, const int dir, const double pct)
  {
   double body = MathAbs(brk.close - brk.open);
   double add  = body * MathMax(pct, 0.0) / 100.0;
   return (dir > 0) ? (brk.high + add) : (brk.low - add);
  }

//+------------------------------------------------------------------+
//| Send the wick-break trade. `anchor` is the confirming candle's    |
//| low (buys) or high (sells). True only when an order was placed.   |
//+------------------------------------------------------------------+
bool ASB_EA_WickBreakEnter(const int k, const int dir, const double anchor, const string module,
                           const int qstat, const string why, const double range_hi, const double range_lo,
                           const datetime day_end, const int day_idx)
  {
   string side   = (dir > 0) ? "BUY" : "SELL";
   string dirtxt = g_s[k].name + " " + side + " wick-break " + module;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (dir > 0) ? ask : bid;

   ASBEvent ev;
   ev.day_idx    = day_idx;
   ev.dir        = dir;
   ev.time       = iTime(_Symbol, g_s[k].sig_tf, 0);
   ev.entry_time = TimeCurrent();
   ev.entry      = price;
   ev.range_hi   = range_hi;
   ev.range_lo   = range_lo;
   ev.day_end    = day_end;
   if(!ASB_EA_FiltersOK(k, ev, qstat, why))
      return false;

   // Stop exactly on the confirming candle's wick (plus the optional buffer). This
   // replaces the session's own stop-loss pips for wick-break trades.
   double sl = anchor - dir * InpWB_SLBufferPips * g_pip;
   double sl_dist = (price - sl) * dir;
   // The closest stop that can exist at all: it must clear the spread (or it would
   // be hit the instant the trade opens) and the broker's own minimum stop distance.
   long   stop_pts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double floor_dist = (ask - bid) + (double)MathMax(stop_pts, 0) * _Point + _Point;
   floor_dist = MathMax(floor_dist, InpWB_MinSLPips * g_pip);
   if(sl_dist < floor_dist)
     {
      PrintFormat("MSB EA: %s - the wick is only %.1f pips from the entry; stop moved out to %.1f pips, the closest allowed (spread, broker stop level, your minimum).",
                  dirtxt, MathMax(sl_dist, 0.0) / g_pip, floor_dist / g_pip);
      sl_dist = floor_dist;
      sl = price - dir * sl_dist;
     }
   double tp_dist = g_s[k].tp_pips * g_pip;

   trade.SetExpertMagicNumber((ulong)g_s[k].magic);
   bool lots_ok = true;
   double lots = ASB_EA_LotsFor(k, sl_dist, lots_ok);
   if(!lots_ok)
     {
      PrintFormat("MSB EA: %s skipped - no lot size could be worked out for this trade (see the line above).", dirtxt);
      return false;
     }
   if(ASB_EA_HasOwnTradeForDir(k, dir))
     {
      PrintFormat("MSB EA: %s skipped - an own-magic position or pending order for this direction already exists (double-order guard).", dirtxt);
      return false;
     }
   sl = NormalizeDouble(sl, _Digits);
   double tp = NormalizeDouble(price + dir * tp_dist, _Digits);
   if(!ASB_EA_StopsOK(price, sl, tp))
     {
      PrintFormat("MSB EA: %s skipped - SL/TP too close to price for the broker's stop level.", dirtxt);
      return false;
     }
   string comment = g_s[k].tag + " W" + module + " " + side;
   bool ok = (dir > 0) ? trade.Buy(lots, _Symbol, 0.0, sl, tp, comment)
                       : trade.Sell(lots, _Symbol, 0.0, sl, tp, comment);
   if(!ok)
     {
      PrintFormat("MSB EA: %s market order FAILED, retcode=%u %s.", dirtxt, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
     }
   ASB_EA_MarkDone(k, dir);
   PrintFormat("MSB EA: %s market order sent at %s SL=%s (%.1f pips) TP=%s.", dirtxt,
               DoubleToString(price, _Digits), DoubleToString(sl, _Digits), sl_dist / g_pip, DoubleToString(tp, _Digits));
   return true;
  }

//+------------------------------------------------------------------+
//| Once per closed signal bar: module B's close check on the bar     |
//| that just closed, and arming module A for the bar now forming.    |
//+------------------------------------------------------------------+
void ASB_EA_WickBreakOnBar(const int k, const MqlRates &sig[], const int got, const ASBDay &days[], const ASBEvent &events[],
                           const int today, const int day_status, const bool ma_ok, const double ma_val)
  {
   // A new candle has opened: whatever module A was waiting for has expired.
   g_s[k].wb_bar     = 0;
   g_s[k].wb_trig_up = 0.0;
   g_s[k].wb_trig_dn = 0.0;

   if(got < 3 || !days[today].has_range)
      return;
   if(TimeCurrent() >= days[today].day_end)
      return;                                   // the breakout window has closed

   int g = got - 1;                             // the candle that just closed
   int p = got - 2;                             // the one before it
   double hi = days[today].high, lo = days[today].low;

   for(int dir = +1; dir >= -1; dir -= 2)
     {
      if((dir > 0) ? g_s[k].bull_done : g_s[k].bear_done)
         continue;
      double level = (dir > 0) ? hi : lo;
      string side  = g_s[k].name + ((dir > 0) ? " BUY" : " SELL");

      ASBQuality q;
      ASB_EA_BuildQuality(k, sig, got, days, events, today, day_status, dir, ma_ok, ma_val, q);
      string why;
      int qstat = ASB_QualityStatus(q, why);

      // Module B: p broke the level, g had to close past p's wick.
      if(InpWB_UseB && ASB_EA_IsBreakCandle(sig, p, dir, level, days[today].sess_end))
        {
         double trig = ASB_EA_WickBreakTrigger(sig[p], dir, InpWB_PctB);
         bool confirmed = (dir > 0) ? (sig[g].close >= trig) : (sig[g].close <= trig);
         if(confirmed)
            ASB_EA_WickBreakEnter(k, dir, (dir > 0) ? sig[g].low : sig[g].high, "B", qstat, why, hi, lo,
                                  days[today].day_end, today);
         else
            PrintFormat("MSB EA: %s wick-break B - break candle %s not confirmed: the next candle closed at %s, needed %s.",
                        side, TimeToString(sig[p].time, TIME_DATE | TIME_MINUTES),
                        DoubleToString(sig[g].close, _Digits), DoubleToString(trig, _Digits));
        }

      // Module A: g broke the level - watch the candle forming now.
      if(InpWB_UseA && !((dir > 0) ? g_s[k].bull_done : g_s[k].bear_done)
         && ASB_EA_IsBreakCandle(sig, g, dir, level, days[today].sess_end))
        {
         double trig = ASB_EA_WickBreakTrigger(sig[g], dir, InpWB_PctA);
         g_s[k].wb_bar      = iTime(_Symbol, g_s[k].sig_tf, 0);
         g_s[k].wb_range_hi = hi;
         g_s[k].wb_range_lo = lo;
         g_s[k].wb_day_end  = days[today].day_end;
         g_s[k].wb_day_idx  = today;
         if(dir > 0)
           { g_s[k].wb_trig_up = trig; g_s[k].wb_q_up = qstat; g_s[k].wb_why_up = why; }
         else
           { g_s[k].wb_trig_dn = trig; g_s[k].wb_q_dn = qstat; g_s[k].wb_why_dn = why; }
         PrintFormat("MSB EA: %s wick-break A armed - break candle %s, enters if price reaches %s during this candle.",
                     side, TimeToString(sig[g].time, TIME_DATE | TIME_MINUTES), DoubleToString(trig, _Digits));
        }
     }
  }

//+------------------------------------------------------------------+
//| Every tick: module A. Fires when the bid reaches an armed trigger |
//| during the candle it was armed for. One attempt per candle and    |
//| direction, whether the order goes through or a filter blocks it.  |
//+------------------------------------------------------------------+
void ASB_EA_WickBreakTick()
  {
   if(!InpWB_UseA)
      return;
   for(int k = 0; k < MSB_SESSIONS; k++)
     {
      if(!g_s[k].use || g_s[k].wb_bar == 0)
         continue;
      if(iTime(_Symbol, g_s[k].sig_tf, 0) != g_s[k].wb_bar || TimeCurrent() >= g_s[k].wb_day_end)
        {
         g_s[k].wb_bar = 0;                     // that candle is over, or the window closed
         continue;
        }
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(g_s[k].wb_trig_up > 0.0 && bid >= g_s[k].wb_trig_up)
        {
         g_s[k].wb_trig_up = 0.0;
         if(!g_s[k].bull_done)
            ASB_EA_WickBreakEnter(k, +1, iLow(_Symbol, g_s[k].sig_tf, 0), "A", g_s[k].wb_q_up, g_s[k].wb_why_up,
                                  g_s[k].wb_range_hi, g_s[k].wb_range_lo, g_s[k].wb_day_end, g_s[k].wb_day_idx);
        }
      if(g_s[k].wb_trig_dn > 0.0 && bid <= g_s[k].wb_trig_dn)
        {
         g_s[k].wb_trig_dn = 0.0;
         if(!g_s[k].bear_done)
            ASB_EA_WickBreakEnter(k, -1, iHigh(_Symbol, g_s[k].sig_tf, 0), "A", g_s[k].wb_q_dn, g_s[k].wb_why_dn,
                                  g_s[k].wb_range_hi, g_s[k].wb_range_lo, g_s[k].wb_day_end, g_s[k].wb_day_idx);
        }
     }
  }
//+------------------------------------------------------------------+
//| CANDLE EXITS - checked once per closed signal bar, per session.   |
//|   After N candles: closes the trade once N signal candles have    |
//|     closed since it was opened; the candle it was opened in       |
//|     counts as the first.                                          |
//|   Opposite candle: closes the trade when the candle that just     |
//|     closed goes against it (bullish for a sell, bearish for a     |
//|     buy) and its body is larger than the set % of the body of the |
//|     candle before it.                                             |
//| Both act at the close of a candle, at market. Stop-loss, take     |
//| profit, break-even and trailing keep working alongside them.      |
//+------------------------------------------------------------------+
void ASB_EA_CandleExits(const int k, const MqlRates &sig[], const int got, const int tf_sec)
  {
   if((!InpEX_UseBars && !InpEX_UseOpposite) || got < 2)
      return;
   int last = got - 1;                                  // the candle that just closed
   datetime last_close = sig[last].time + tf_sec;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != g_s[k].magic) continue;
      string comment = PositionGetString(POSITION_COMMENT);
      if(InpEX_WickBreakOnly && StringFind(comment, " WA ") < 0 && StringFind(comment, " WB ") < 0)
         continue;                                      // not a wick-break trade
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      if(open_time >= last_close)
         continue;                                      // opened after that candle closed
      int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
      string what = g_s[k].name + ((dir > 0) ? " BUY" : " SELL") + " #" + (string)ticket;

      string reason = "";
      if(InpEX_UseBars && InpEX_Bars > 0)
        {
         int closed = 0;                                // candles that closed after the entry
         for(int b = last; b >= 0 && sig[b].time + tf_sec > open_time; b--)
            closed++;
         if(closed >= InpEX_Bars)
            reason = StringFormat("%d candles have closed since the entry", closed);
        }
      if(reason == "" && InpEX_UseOpposite)
        {
         double body = MathAbs(sig[last].close - sig[last].open);
         double prev = MathAbs(sig[last - 1].close - sig[last - 1].open);
         bool against = (dir > 0) ? (sig[last].close < sig[last].open) : (sig[last].close > sig[last].open);
         if(against && body > prev * MathMax(InpEX_OppositePct, 0.0) / 100.0)
            reason = StringFormat("a candle against the trade closed with a body of %.1f pips, previous candle %.1f pips",
                                  body / g_pip, prev / g_pip);
        }
      if(reason == "")
         continue;

      trade.SetExpertMagicNumber((ulong)g_s[k].magic);
      if(trade.PositionClose(ticket))
         PrintFormat("MSB EA: %s closed by candle exit - %s.", what, reason);
      else
         PrintFormat("MSB EA: %s candle exit FAILED (%s), retcode=%u %s - will try again next candle.",
                     what, reason, trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }
//+------------------------------------------------------------------+
