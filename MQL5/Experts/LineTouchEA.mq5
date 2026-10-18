//+------------------------------------------------------------------+
//|                                                  LineTouchEA.mq5 |
//|                      Trades price reactions at chart line levels |
//|                                                                  |
//|  Level sources (all optional, merged into one list):             |
//|   1. Horizontal lines and trend lines on the chart - drawn by    |
//|      hand or by indicators (U_MTF_SRTrend "SR_n" / "Trend_*",    |
//|      ValueAreaLevels "VAL_*" segments, anything else)            |
//|   2. ValueAreaLevels indicator buffers read through iCustom      |
//|      (DVAH/DPOC/DVAL, PDVAH/PDPOC/PDVAL, FVAH/FPOC/FVAL)          |
//|   3. Built-in multi-timeframe ZigZag S/R pivots and up/down      |
//|      trend lines (port of the U_MTF_SRTrend1 engine)             |
//|   4. Manual price list and manual trend lines                    |
//|                                                                  |
//|  Entry modes: Touch (intrabar), Confirm (bar close rejection),   |
//|  Pending (resting limit / stop orders).                          |
//|  Direction: Bounce (buy support / sell resistance) or Breakout.  |
//+------------------------------------------------------------------+
#property copyright   "steinihaf"
#property link        "https://github.com/steinihaf/steinihaf"
#property version     "1.00"
#property description "Executes orders where price touches, rejects or breaks the levels on the chart."
#property description "Reads chart lines, ValueAreaLevels buffers, built-in MTF ZigZag S/R and manual levels."
// The Strategy Tester must bundle the indicator whose name comes from an input string.
// Remove this line if you do not have ValueAreaLevels.ex5 and want to backtest without it.
#property tester_indicator "ValueAreaLevels.ex5"

#include <Trade/Trade.mqh>

#define LT_NAME         "LineTouchEA"
#define LT_PREFIX       "LTEA_"        // prefix of every chart object this EA creates
#define LT_SR_PREFIX    "LTEA_SR_"     // computed S/R horizontal lines
#define LT_TL_PREFIX    "LTEA_TL_"     // computed trend lines
#define LT_MARK_PREFIX  "LTEA_mk_"     // entry markers
#define LT_MAX_SR       64             // hard cap of S/R pivots kept per timeframe
#define LT_VAL_BUFFERS  9              // buffers exposed by ValueAreaLevels

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_LT_ENTRY_MODE
  {
   LT_ENTRY_TOUCH         = 0,   // Touch: market order when price enters the zone
   LT_ENTRY_CONFIRM_CLOSE = 1,   // Confirm: bar touches the zone and closes back (rejection)
   LT_ENTRY_PENDING       = 2    // Pending: limit / stop orders resting at the level
  };

enum ENUM_LT_DIRECTION_MODE
  {
   LT_DIR_BOUNCE   = 0,          // Bounce: buy support / sell resistance
   LT_DIR_BREAKOUT = 1           // Breakout: sell below support / buy above resistance
  };

enum ENUM_LT_TRADE_PERMIT
  {
   LT_PERMIT_BOTH      = 0,      // Buy and sell
   LT_PERMIT_BUY_ONLY  = 1,      // Buy only
   LT_PERMIT_SELL_ONLY = 2       // Sell only
  };

enum ENUM_LT_LOT_MODE
  {
   LT_LOT_FIXED        = 0,      // Fixed lot
   LT_LOT_RISK_PERCENT = 1       // Risk percent of balance (from stop-loss distance)
  };

enum ENUM_LT_SL_MODE
  {
   LT_SL_BEYOND_LEVEL = 0,       // Beyond the level + buffer
   LT_SL_FIXED_POINTS = 1,       // Fixed points from entry
   LT_SL_ATR          = 2        // ATR multiple from entry
  };

enum ENUM_LT_TP_MODE
  {
   LT_TP_NEXT_LEVEL   = 0,       // Next level in trade direction (fallback: R multiple)
   LT_TP_RR           = 1,       // R multiple of the stop-loss distance
   LT_TP_FIXED_POINTS = 2,       // Fixed points from entry
   LT_TP_NONE         = 3        // No take-profit
  };

enum ENUM_LT_TREND_PRICE_METHOD
  {
   LT_TLP_BAR_INDEX = 0,         // Bar-index interpolation (how the chart draws it)
   LT_TLP_TERMINAL  = 1          // ObjectGetValueByTime (terminal function)
  };

enum ENUM_LT_COLOR_FILTER
  {
   LT_CF_OFF     = 0,            // Off: any color
   LT_CF_INCLUDE = 1,            // Only the listed colors
   LT_CF_EXCLUDE = 2             // All but the listed colors
  };

enum ENUM_LT_OPPOSITE
  {
   LT_OPP_SKIP        = 0,       // Skip the signal while an opposite position is open
   LT_OPP_CLOSE_FIRST = 1,       // Close opposite positions, then open
   LT_OPP_HEDGE       = 2        // Open anyway (hedging accounts only)
  };

enum ENUM_LT_VOLTYPE
  {
   LT_VOL_TICK = 0,              // Tick volume
   LT_VOL_REAL = 1               // Real volume (falls back to tick when empty)
  };

enum ENUM_LT_LOG
  {
   LT_LOG_ERRORS  = 0,           // Errors only
   LT_LOG_NORMAL  = 1,           // Trades and important events
   LT_LOG_VERBOSE = 2            // Everything (skipped signals, rescans)
  };

enum ENUM_LT_GRADE
  {
   LT_GRADE_A = 0,               // A: higher-timeframe pivots, previous-session value area, manual, chart lines
   LT_GRADE_B = 1,               // B: H4 pivots, D1 / H4 trend lines
   LT_GRADE_C = 2                // C: H1 and faster pivots and trend lines, developing / forecast value area
  };

enum ENUM_LT_TRADE_MODE
  {
   LT_MODE_LIVE        = 0,      // Live: send orders
   LT_MODE_SIGNAL_ONLY = 1       // Signal only: arrows and alerts, no orders (dry run)
  };

enum ENUM_LT_LOWRR
  {
   LT_LOWRR_SKIP       = 0,      // Skip the trade
   LT_LOWRR_R_MULTIPLE = 1       // Use the R multiple target instead
  };

enum ENUM_LT_SOURCE
  {
   LT_SRC_OBJECT    = 0,
   LT_SRC_VAL       = 1,
   LT_SRC_ENGINE_SR = 2,
   LT_SRC_ENGINE_TL = 3,
   LT_SRC_MANUAL    = 4
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Level source 1: lines on the chart ==="
input bool   InpObjUseHLines         = true;          // Use horizontal lines (OBJ_HLINE)
input bool   InpObjUseTrendLines     = true;          // Use trend lines (OBJ_TREND)
input string InpObjIncludePrefixes   = "";            // Only names starting with... (a;b;c, empty = all)
input string InpObjExcludePrefixes   = "";            // Skip names starting with... (a;b;c)
input bool   InpObjSkipHidden        = false;         // Skip objects hidden from the object list
input ENUM_LT_COLOR_FILTER InpObjColorFilter = LT_CF_OFF; // Color filter
input color  InpObjColor1            = clrRed;        // Color filter 1
input color  InpObjColor2            = clrYellow;     // Color filter 2
input color  InpObjColor3            = clrWhite;      // Color filter 3
input color  InpObjColor4            = clrAqua;       // Color filter 4
input ENUM_LT_TREND_PRICE_METHOD InpTrendPriceMethod = LT_TLP_BAR_INDEX; // Trend line price method
input bool   InpObjTreatAllAsRays    = false;         // Treat every trend line as a right ray
input int    InpObjRescanSeconds     = 1;             // Re-read chart objects every N seconds (0 = every tick)

input group "=== Level source 2: ValueAreaLevels indicator (iCustom) ==="
input bool   InpVAL_Enable           = false;         // Read ValueAreaLevels buffers
input string InpVAL_IndicatorName    = "ValueAreaLevels"; // Indicator file (relative to MQL5\Indicators)
input bool   InpVAL_UseDVAH          = true;          // Use DVAH  (developing value area high)
input bool   InpVAL_UseDPOC          = true;          // Use DPOC  (developing point of control)
input bool   InpVAL_UseDVAL          = true;          // Use DVAL  (developing value area low)
input bool   InpVAL_UsePDVAH         = true;          // Use PDVAH (previous session VAH)
input bool   InpVAL_UsePDPOC         = true;          // Use PDPOC (previous session POC)
input bool   InpVAL_UsePDVAL         = true;          // Use PDVAL (previous session VAL)
input bool   InpVAL_UseFVAH          = false;         // Use FVAH  (forecast VAH)
input bool   InpVAL_UseFPOC          = false;         // Use FPOC  (forecast POC)
input bool   InpVAL_UseFVAL          = false;         // Use FVAL  (forecast VAL)
input ENUM_TIMEFRAMES InpVAL_ProfilePeriod = PERIOD_D1;  // VAL: profile period (one session)
input ENUM_TIMEFRAMES InpVAL_SourceTF      = PERIOD_CURRENT; // VAL: source timeframe (Current = Auto)
input double InpVAL_ValueAreaPercent = 70.0;          // VAL: value area percent
input ENUM_LT_VOLTYPE InpVAL_VolumeType = LT_VOL_TICK; // VAL: volume type
input int    InpVAL_MaxSessions      = 60;            // VAL: max sessions back
input int    InpVAL_BinPoints        = 0;             // VAL: bin size in points (0 = Auto)
input int    InpVAL_ForecastSessions = 5;             // VAL: sessions in the forecast composite
input int    InpVAL_DevelopingMinBars = 6;            // Developing levels are targets only for the first N bars of a session
input bool   InpVAL_ExcludeObjects   = true;          // Skip VAL_ chart objects when buffers are used (no duplicates)

input group "=== Level source 3: built-in MTF ZigZag S/R + trend lines ==="
input bool   InpSR_Enable            = false;         // Compute multi-timeframe ZigZag levels (U_MTF_SRTrend port)
input bool   InpSR_UseSRLines        = true;          // Use the horizontal S/R pivots
input bool   InpSR_UseTrendLines     = true;          // Use the up / down trend lines
input string InpSR_Timeframes        = "AUTO";        // Timeframes: AUTO (original scheme) or list e.g. D1;H4;H1
input int    InpSR_Depth             = 12;            // S/R ZigZag depth
input int    InpSR_Deviation         = 6;             // S/R ZigZag deviation (points)
input int    InpSR_Backstep          = 3;             // S/R ZigZag backstep
input int    InpSR_MaxPerTF          = 8;             // S/R levels per timeframe
input int    InpSR_FilterPoints      = 0;             // Only S/R within N points of price (0 = all)
input int    InpTL_Depth             = 9;             // Trend-line ZigZag depth
input int    InpTL_Deviation         = 0;             // Trend-line ZigZag deviation (points)
input int    InpTL_Backstep          = 3;             // Trend-line ZigZag backstep
input int    InpSR_LookbackBars      = 1000;          // Bars analysed per timeframe
input bool   InpSR_Draw              = true;          // Draw the computed lines on the chart

input group "=== Trend line validity (all sloped lines) ==="
input double InpTL_MaxExtensionRatio = 2.0;           // Ignore a line extended more than N x its anchor span (0 = off)
input double InpTL_MaxSlopeATR       = 0.4;           // Ignore a line steeper than N x ATR per bar (0 = off)

input group "=== Level source 4: manual ==="
input string InpManualLevels         = "";            // Prices, e.g. 4343.31;4272.32;4155.23
input string InpManualTrendLines     = "";            // Lines: yyyy.mm.dd hh:mi|price|yyyy.mm.dd hh:mi|price;...

input group "=== Level handling ==="
input int    InpMergeDistancePoints  = 100;           // Merge levels closer than N points (0 = off)
input ENUM_LT_GRADE InpMinEntryGrade = LT_GRADE_B;    // Lowest level grade allowed for entries (lower = targets only)

input group "=== Signals ==="
input ENUM_TIMEFRAMES InpSignalTF    = PERIOD_CURRENT; // Signal timeframe (Current = chart)
input ENUM_LT_ENTRY_MODE InpEntryMode = LT_ENTRY_TOUCH; // Entry mode
input ENUM_LT_DIRECTION_MODE InpDirectionMode = LT_DIR_BOUNCE; // Direction mode
input ENUM_LT_TRADE_PERMIT InpTradePermit = LT_PERMIT_BOTH; // Allowed directions
input int    InpTouchZonePoints      = 300;           // Touch zone around the level (points)
input double InpZoneATRFraction      = 0.25;          // Zone = max(points, ATR x fraction) (0 = off)
input int    InpATRPeriod            = 14;            // ATR period (zone / stop-loss / filters)
input int    InpTouchRetreatPercent  = 30;            // Touch: wait until price retreats N% of the zone from its extreme (0 = immediate)
input double InpMaxPenetrationATR    = 0.5;           // Bounce: ignore touches that pierced the level by more than N x ATR (0 = off)
input double InpMinRejectionRatio    = 0.6;           // Confirm: min close position inside the bar range (0..1)
input double InpMaxEntryDistanceATR  = 0.5;           // Confirm: skip when the entry is farther than N x ATR from the level (0 = off)
input int    InpBreakoutBufferPoints = 200;           // Break buffer (points): close beyond level +/- buffer = through
input double InpBreakoutBufferATRFraction = 0.15;     // Break buffer = max(points, ATR x fraction)
input int    InpRoleConfirmBars      = 2;             // Closes beyond the break buffer needed to flip a level's role
input int    InpChopWindowBars       = 24;            // Chop filter: window (bars)
input int    InpChopMaxFlips         = 2;             // Chop filter: role flips inside the window that disable the level
input int    InpRearmPoints          = 800;           // Re-arm distance outside the zone (points)
input double InpRearmATRFraction     = 0.75;          // Re-arm distance = max(points, ATR x fraction)
input int    InpCooldownBars         = 3;             // Bars between signals on the same level
input int    InpMaxTradesPerLevel    = 0;             // Lifetime trades per level (0 = unlimited)
input int    InpMaxLossesPerLevelDay = 1;             // Losing trades per level per day before it is disabled (0 = off)
input int    InpMaxPositionsPerLevel = 1;             // Open positions per level
input int    InpMaxOpenPositions     = 2;             // Open positions in total (this EA, this symbol)
input int    InpMinEntrySpacingPoints = 300;          // Min distance from an existing same-direction entry
input ENUM_LT_OPPOSITE InpOppositeMode = LT_OPP_SKIP; // When an opposite position is open
input bool   InpOneSignalPerBar      = true;          // At most one new trade per bar

input group "=== Pending orders (entry mode = Pending) ==="
input int    InpPendingOffsetPoints  = 20;            // Order price offset from the level (points)
input int    InpPendingExpiryBars    = 6;             // Delete after N bars (0 = good till cancelled)
input int    InpPendingMinDistancePoints = 150;       // Do not place when the level is closer than N points
input double InpPendingMaxDistanceATR = 1.5;          // Do not place when the level is farther than N x ATR (0 = off)
input bool   InpPendingDeleteOrphans = true;          // Delete this EA's pending orders that match no level

input group "=== Filters ==="
input int    InpMaxSpreadPoints      = 60;            // Max spread (points, 0 = off)
input double InpMaxSpreadPercentOfSL = 8.0;           // Max spread as % of the stop distance (0 = off)
input int    InpRolloverSkipMinutes  = 20;            // No new trades within N minutes of server midnight (0 = off)
input bool   InpUseTimeFilter        = false;         // Use trading hours (server time)
input int    InpStartHour            = 1;             // Trading start hour
input int    InpEndHour              = 23;            // Trading end hour (exclusive)
input int    InpFridayStopHour       = 0;             // No new trades on Friday from this hour (0 = off)
input int    InpMaxTradesPerDay      = 0;             // Max new trades per day (0 = off)
input double InpMaxDailyLossPercent  = 2.0;           // Stop for the day after losing N% of balance (0 = off)
input int    InpMaxConsecutiveLosses = 3;             // Stop for the day after N losses in a row (0 = off)
input double InpMaxImpulseATR        = 1.5;           // Bounce: skip when the last 3 bars moved more than N x ATR (0 = off)
input double InpMaxBarRangeATR       = 2.0;           // Bounce: skip when the touching bar's range exceeds N x ATR (0 = off)
input bool   InpUseADXFilter         = true;          // ADX regime: when trending, trade only with the trend
input ENUM_TIMEFRAMES InpADXTF       = PERIOD_H4;     // ADX timeframe
input int    InpADXPeriod            = 14;            // ADX period
input double InpADXThreshold         = 30.0;          // ADX above this = trending
input bool   InpUseMAFilter          = false;         // Trade only with the moving-average trend
input int    InpMAPeriod             = 200;           // MA period
input ENUM_MA_METHOD InpMAMethod     = MODE_EMA;      // MA method
input ENUM_TIMEFRAMES InpMATF        = PERIOD_CURRENT; // MA timeframe

input group "=== Risk ==="
input ENUM_LT_LOT_MODE InpLotMode    = LT_LOT_RISK_PERCENT; // Lot mode
input double InpFixedLot             = 0.01;          // Fixed lot
input double InpRiskPercent          = 0.5;           // Risk per trade (% of balance)
input bool   InpAllowMinLotOverRisk  = false;         // Use the minimum lot when the risk lot is smaller
input ENUM_LT_SL_MODE InpSLMode      = LT_SL_BEYOND_LEVEL; // Stop-loss mode
input int    InpSLBufferPoints       = 500;           // Stop-loss buffer beyond the level (points)
input double InpSLBufferATRFraction  = 0.5;           // Stop-loss buffer = max(points, ATR x fraction)
input int    InpSLFixedPoints        = 800;           // Fixed stop-loss (points)
input double InpSLATRMult            = 1.5;           // ATR multiple for the stop-loss
input int    InpMinSLPoints          = 300;           // Minimum stop distance (points)
input int    InpMaxSLPoints          = 3000;          // Skip the trade if the stop would be wider (0 = off)
input ENUM_LT_TP_MODE InpTPMode      = LT_TP_NEXT_LEVEL; // Take-profit mode
input double InpTPRR                 = 1.5;           // R multiple
input int    InpTPFixedPoints        = 1200;          // Fixed take-profit (points)
input int    InpTPLevelBufferPoints  = 150;           // Take profit N points before the next level
input int    InpTPMinPoints          = 400;           // Next level must be at least N points away
input double InpTPMinRR              = 1.2;           // Next level: minimum reward / risk (0 = off)
input ENUM_LT_LOWRR InpTPLowRRAction = LT_LOWRR_SKIP; // Next level: when reward / risk is below the minimum
input double InpTPMaxRR              = 3.0;           // Next level: cap the target at N R (0 = off)
input int    InpBreakEvenTriggerPoints = 0;           // Move stop to break-even after N points (0 = off)
input int    InpBreakEvenLockPoints  = 20;            // Break-even lock (points)
input int    InpTrailingStartPoints  = 0;             // Start trailing after N points (0 = off)
input int    InpTrailingStopPoints   = 500;           // Trailing distance (points)
input int    InpTrailingStepPoints   = 50;            // Trailing step (points)

input group "=== Execution ==="
input ENUM_LT_TRADE_MODE InpTradeMode = LT_MODE_LIVE; // Trade mode
input ulong  InpMagic                = 20261017;      // Magic number
input int    InpDeviationPoints      = 50;            // Max slippage (points)
input string InpTradeComment         = "LT";          // Order comment prefix

input group "=== Display & alerts ==="
input bool   InpShowDashboard        = true;          // Show the dashboard
input int    InpDashboardLevels      = 12;            // Levels listed on the dashboard
input bool   InpDrawMarkers          = true;          // Draw entry arrows
input bool   InpDeleteObjectsOnExit  = true;          // Delete this EA's objects when removed
input bool   InpPersistState         = true;          // Save level state to a file (survives restarts)
input bool   InpAlerts               = false;         // Alert() on every trade
input bool   InpPushNotifications    = false;         // Push notification on every trade
input ENUM_LT_LOG InpLogLevel        = LT_LOG_NORMAL; // Log level

//+------------------------------------------------------------------+
//| Data structures                                                  |
//+------------------------------------------------------------------+
struct SLevel
  {
   // identity
   string   key;            // unique id, stable while the level exists
   string   label;          // display name
   int      source;         // ENUM_LT_SOURCE
   int      kind;           // 0 = horizontal, 1 = sloped (trend line)
   string   objName;        // chart object name (chart-object levels)
   color    clr;
   int      grade;          // ENUM_LT_GRADE
   bool     targetOnly;     // usable as a take-profit target, never for entries
   string   members;        // keys of every level merged into this one, ';' separated
   // geometry
   double   price;          // value at the current bar
   double   prevPrice;      // value at the previous (completed) signal bar
   datetime t1;             // anchors of a sloped line
   double   p1;
   datetime t2;
   double   p2;
   bool     rayRight;
   bool     rayLeft;
   // trading state (carried over between rebuilds by key)
   int      role;           // +1 support (below price), -1 resistance (above price), 0 unknown
   int      pendingRole;    // opposite side seen on recent closes
   int      pendingRoleCount;
   int      lastSide;       // side of the zone price was last outside: +1 above, -1 below, 0 unknown
   bool     inTouch;        // price is inside the zone (touch episode running)
   double   touchExtreme;   // most adverse price seen during the touch episode
   bool     needReset;      // true after a signal until price has moved away again
   datetime lastSignalTime; // signal-bar time of the last signal (or role flip) on this level
   int      trades;         // lifetime trades on this level
   int      flipCount;      // role flips inside the chop window
   datetime flipWindowStart;
   datetime lastFlipTime;
   ulong    pendingTicket;  // resting order ticket (pending mode)
   int      pendingType;    // ENUM_ORDER_TYPE of the resting order, -1 = none
   datetime pendingBar;     // signal-bar time when the order was last placed

   void     Reset()
     {
      key = ""; label = ""; source = 0; kind = 0; objName = ""; clr = clrWhite; grade = 0; targetOnly = false;
      members = "";
      price = 0.0; prevPrice = 0.0; t1 = 0; p1 = 0.0; t2 = 0; p2 = 0.0; rayRight = true; rayLeft = false;
      role = 0; pendingRole = 0; pendingRoleCount = 0; lastSide = 0; inTouch = false; touchExtreme = 0.0;
      needReset = false; lastSignalTime = 0; trades = 0;
      flipCount = 0; flipWindowStart = 0; lastFlipTime = 0;
      pendingTicket = 0; pendingType = -1; pendingBar = 0;
     }
   void     CopyStateFrom(const SLevel &o)
     {
      role = o.role; pendingRole = o.pendingRole; pendingRoleCount = o.pendingRoleCount;
      lastSide = o.lastSide; inTouch = o.inTouch; touchExtreme = o.touchExtreme;
      needReset = o.needReset; lastSignalTime = o.lastSignalTime; trades = o.trades;
      flipCount = o.flipCount; flipWindowStart = o.flipWindowStart; lastFlipTime = o.lastFlipTime;
      pendingTicket = o.pendingTicket; pendingType = o.pendingType; pendingBar = o.pendingBar;
     }
  };

struct SSavedState            // level state restored from the state file
  {
   string   key;
   double   price;
   int      role;
   bool     needReset;
   datetime lastSignalTime;
   int      trades;
   int      flipCount;
   datetime flipWindowStart;
   datetime lastFlipTime;
  };

struct SLossRecord            // one losing trade today: level hash and entry price
  {
   string   hash;
   double   price;
  };

struct SPosLink              // open position / order  ->  level key
  {
   ulong    ticket;
   string   key;
  };

struct SPivot
  {
   int      shift;
   datetime time;
   double   price;
   bool     isPeak;
  };

struct SEngineTF             // one timeframe of the built-in ZigZag engine
  {
   ENUM_TIMEFRAMES tf;
   bool     useSR;
   bool     useTL;
   bool     ready;
   int      srCount;
   double   srPrice[LT_MAX_SR];
   bool     upValid;
   datetime upT1;
   double   upP1;
   datetime upT2;
   double   upP2;
   bool     dnValid;
   datetime dnT1;
   double   dnP1;
   datetime dnT2;
   double   dnP2;
  };

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade          g_trade;
SLevel          g_levels[];
SPosLink        g_links[];
SEngineTF       g_eng[];
string          g_inclPrefix[];
string          g_exclPrefix[];
string          g_manualTL[];          // raw manual trend-line definitions (parsed each rebuild)
double          g_manualPrice[];

ENUM_TIMEFRAMES g_sigTF;
MqlTick         g_tick;
double          g_point        = 0.0;
int             g_digits       = 2;
double          g_tickSize     = 0.0;
long            g_stopsLevel   = 0;
long            g_freezeLevel  = 0;
bool            g_hedging      = false;
bool            g_isTester     = false;
bool            g_isVisual     = false;
bool            g_expirySupported = false;

int             g_atrHandle    = INVALID_HANDLE;
int             g_maHandle     = INVALID_HANDLE;
int             g_adxHandle    = INVALID_HANDLE;
int             g_valHandle    = INVALID_HANDLE;
SSavedState     g_saved[];
SLossRecord     g_losses[];
int             g_consecLosses = 0;
string          g_lastBlock    = "";
bool            g_valReady     = true;    // ValueAreaLevels buffers available
ulong           g_signalSeq    = 0;
bool            g_stateDirty   = false;
double          g_atr          = 0.0;
double          g_zone         = 0.0;   // current touch zone in price units

datetime        g_lastBarTime  = 0;
int             g_signalsThisBar = 0;
datetime        g_lastObjScan  = 0;
bool            g_objDirty     = true;
datetime        g_lastDashboard = 0;
datetime        g_lastEngineRun = 0;
datetime        g_lastHistoryScan = 0;
bool            g_tradeAllowedLogged = false;

datetime        g_dayStart     = 0;
double          g_dayRealized  = 0.0;
double          g_dayFloating  = 0.0;
double          g_dayStartBalance = 0.0;
int             g_dayTrades    = 0;
bool            g_dayStopped   = false;

const string    g_valNames[LT_VAL_BUFFERS] = { "DVAH", "DPOC", "DVAL", "PDVAH", "PDPOC", "PDVAL", "FVAH", "FPOC", "FVAL" };

//+------------------------------------------------------------------+
//| Small helpers                                                    |
//+------------------------------------------------------------------+
void LTLog(const int level, const string msg)
  {
   if((int)InpLogLevel >= level)
      Print(LT_NAME, ": ", msg);
  }

double Pts(const int points)
  {
   return(points * g_point);
  }

string PriceStr(const double p)
  {
   return(DoubleToString(p, g_digits));
  }

string TFToString(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   StringReplace(s, "PERIOD_", "");
   return(s);
  }

ENUM_TIMEFRAMES StringToTF(string s)
  {
   StringTrimLeft(s);
   StringTrimRight(s);
   StringToUpper(s);
   StringReplace(s, "PERIOD_", "");
   if(s == "M1")  return(PERIOD_M1);
   if(s == "M2")  return(PERIOD_M2);
   if(s == "M3")  return(PERIOD_M3);
   if(s == "M4")  return(PERIOD_M4);
   if(s == "M5")  return(PERIOD_M5);
   if(s == "M6")  return(PERIOD_M6);
   if(s == "M10") return(PERIOD_M10);
   if(s == "M12") return(PERIOD_M12);
   if(s == "M15") return(PERIOD_M15);
   if(s == "M20") return(PERIOD_M20);
   if(s == "M30") return(PERIOD_M30);
   if(s == "H1")  return(PERIOD_H1);
   if(s == "H2")  return(PERIOD_H2);
   if(s == "H3")  return(PERIOD_H3);
   if(s == "H4")  return(PERIOD_H4);
   if(s == "H6")  return(PERIOD_H6);
   if(s == "H8")  return(PERIOD_H8);
   if(s == "H12") return(PERIOD_H12);
   if(s == "D1")  return(PERIOD_D1);
   if(s == "W1")  return(PERIOD_W1);
   if(s == "MN1") return(PERIOD_MN1);
   return(PERIOD_CURRENT);
  }

// FNV-1a hash of a string as 8 hex characters (used to tag orders with their level)
string Hash8(const string s)
  {
   uint h = 0x811C9DC5;
   int len = StringLen(s);
   for(int i = 0; i < len; i++)
     {
      h ^= (uint)StringGetCharacter(s, i);
      h *= 0x01000193;
     }
   string hex = "";
   string digits = "0123456789abcdef";
   for(int n = 7; n >= 0; n--)
     {
      int nibble = (int)((h >> (n * 4)) & 15);
      hex += StringSubstr(digits, nibble, 1);
     }
   return(hex);
  }

string LevelComment(const string key)
  {
   return(InpTradeComment + "|" + Hash8(key));
  }

// true if the order/position comment carries this level's hash
bool CommentMatchesKey(const string comment, const string key)
  {
   if(comment == "" || key == "")
      return(false);
   return(StringFind(comment, "|" + Hash8(key)) >= 0);
  }

// does a comment hash belong to this level or to any level merged into it?
bool CommentMatchesLevel(const string comment, const SLevel &L)
  {
   if(CommentMatchesKey(comment, L.key))
      return(true);
   if(L.members == "")
      return(false);
   string ks[];
   int n = StringSplit(L.members, ';', ks);
   for(int k = 0; k < n; k++)
      if(ks[k] != "" && ks[k] != L.key && CommentMatchesKey(comment, ks[k]))
         return(true);
   return(false);
  }

bool StartsWith(const string s, const string prefix)
  {
   if(prefix == "")
      return(false);
   return(StringFind(s, prefix) == 0);
  }

void SplitList(const string list, string &out[])
  {
   ArrayResize(out, 0);
   if(list == "")
      return;
   string parts[];
   int n = StringSplit(list, ';', parts);
   for(int i = 0; i < n; i++)
     {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(p == "")
         continue;
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k] = p;
     }
  }

void AddPrefix(string &arr[], const string prefix)
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == prefix)
         return;
   int k = ArraySize(arr);
   ArrayResize(arr, k + 1);
   arr[k] = prefix;
  }

double RoundToTick(const double price)
  {
   if(g_tickSize <= 0.0)
      return(NormalizeDouble(price, g_digits));
   return(NormalizeDouble(MathRound(price / g_tickSize) * g_tickSize, g_digits));
  }

// minimum distance from the current price for stops and pending orders
double MinStopDistance()
  {
   double d = MathMax((double)g_stopsLevel, (double)g_freezeLevel) * g_point;
   return(MathMax(d, g_point));
  }

datetime SignalBarTime(const int shift)
  {
   return(iTime(_Symbol, g_sigTF, shift));
  }

// number of completed signal bars since a bar time (large when unknown)
int BarsSince(const datetime t)
  {
   if(t == 0)
      return(100000);
   int sh = iBarShift(_Symbol, g_sigTF, t, false);
   if(sh < 0)
      return(100000);
   return(sh);
  }

datetime StartOfDay(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return(StructToTime(dt));
  }

//+------------------------------------------------------------------+
//| Trend-line geometry: the chart draws lines in bar-index space,   |
//| so a line's value at a time is interpolated by chart bar index.  |
//+------------------------------------------------------------------+
bool BarIndexOfTime(const datetime t, double &idx)
  {
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0)
      return(false);
   if(t >= t0)
     {
      idx = -(double)(t - t0) / (double)PeriodSeconds(_Period);   // future: one bar per period
      return(true);
     }
   int total = Bars(_Symbol, _Period);
   if(total > 1)
     {
      datetime tOld = iTime(_Symbol, _Period, total - 1);
      if(tOld > 0 && t < tOld)                             // before the loaded history: extrapolate
        {
         idx = (double)(total - 1) + (double)(tOld - t) / (double)PeriodSeconds(_Period);
         return(true);
        }
     }
   int sh = iBarShift(_Symbol, _Period, t, false);
   if(sh < 0)
      return(false);
   idx = (double)sh;
   return(true);
  }

bool LineValueAt(const datetime t1, const double p1, const datetime t2, const double p2,
                 const datetime t, double &value)
  {
   double b1 = 0.0, b2 = 0.0, bt = 0.0;
   if(!BarIndexOfTime(t1, b1) || !BarIndexOfTime(t2, b2) || !BarIndexOfTime(t, bt))
      return(false);
   if(MathAbs(b1 - b2) < 0.5)
      return(false);                                   // vertical or degenerate
   value = p1 + (p2 - p1) * (b1 - bt) / (b1 - b2);
   return(value > 0.0);
  }

// value of a sloped level at time t, honoring ray flags; false when the line does not reach t
bool SlopedLevelValue(const SLevel &L, const datetime t, double &value)
  {
   datetime tMin = (L.t1 < L.t2) ? L.t1 : L.t2;
   datetime tMax = (L.t1 < L.t2) ? L.t2 : L.t1;
   if(t > tMax && !L.rayRight)
      return(false);
   if(t < tMin && !L.rayLeft)
      return(false);
   if(InpTrendPriceMethod == LT_TLP_TERMINAL && L.objName != "" && L.source == LT_SRC_OBJECT)
     {
      ResetLastError();
      double v = ObjectGetValueByTime(0, L.objName, t, 0);
      if(v > 0.0 && GetLastError() == 0)
        {
         value = v;
         return(true);
        }
     }
   return(LineValueAt(L.t1, L.p1, L.t2, L.p2, t, value));
  }

// over-extended (stale) or too steep lines are ignored; near-flat lines are never stale
bool SlopedLineUsable(const SLevel &L)
  {
   double b1 = 0.0, b2 = 0.0;
   if(!BarIndexOfTime(L.t1, b1) || !BarIndexOfTime(L.t2, b2))
      return(false);
   double span = MathAbs(b1 - b2);
   if(span < 0.5)
      return(false);
   double rise  = MathAbs(L.p1 - L.p2);
   double slope = rise / span;                          // price change per chart bar
   bool   flat  = (rise <= g_zone * 0.1);
   if(!flat && InpTL_MaxExtensionRatio > 0.0)
     {
      double sinceNewest = MathMin(b1, b2);             // bars since the newest anchor (negative = future)
      if(sinceNewest > InpTL_MaxExtensionRatio * span)
         return(false);
     }
   if(InpTL_MaxSlopeATR > 0.0 && g_atr > 0.0 && slope > InpTL_MaxSlopeATR * g_atr)
      return(false);
   return(true);
  }

// fills price (current bar) and prevPrice (previous signal bar) of a sloped level
bool ComputeSlopedPrices(SLevel &L)
  {
   datetime tNow  = iTime(_Symbol, _Period, 0);
   datetime tPrev = SignalBarTime(1);
   if(tNow == 0)
      return(false);
   if(!SlopedLineUsable(L))
      return(false);
   double v0 = 0.0, v1 = 0.0;
   if(!SlopedLevelValue(L, tNow, v0))
      return(false);
   if(tPrev == 0 || !SlopedLevelValue(L, tPrev, v1))
      v1 = v0;
   L.price = v0;
   L.prevPrice = v1;
   return(true);
  }

//+------------------------------------------------------------------+
//| Level list helpers                                               |
//+------------------------------------------------------------------+
void AppendLevel(SLevel &arr[], const SLevel &L)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = L;
  }

int FindLevelByKey(const SLevel &arr[], const string key)
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i].key == key)
         return(i);
   return(-1);
  }

bool NameFilterOK(const string name)
  {
   if(StartsWith(name, LT_PREFIX))
      return(false);
   for(int i = 0; i < ArraySize(g_exclPrefix); i++)
      if(StartsWith(name, g_exclPrefix[i]))
         return(false);
   if(ArraySize(g_inclPrefix) == 0)
      return(true);
   for(int i = 0; i < ArraySize(g_inclPrefix); i++)
      if(StartsWith(name, g_inclPrefix[i]))
         return(true);
   return(false);
  }

bool ColorFilterOK(const color c)
  {
   if(InpObjColorFilter == LT_CF_OFF)
      return(true);
   bool listed = (c == InpObjColor1 || c == InpObjColor2 || c == InpObjColor3 || c == InpObjColor4);
   if(InpObjColorFilter == LT_CF_INCLUDE)
      return(listed);
   return(!listed);
  }

//+------------------------------------------------------------------+
//| Source 1: horizontal lines and trend lines on the chart          |
//+------------------------------------------------------------------+
void ScanChartObjects(SLevel &out[])
  {
   for(int k = 0; k < 2; k++)
     {
      int type = (k == 0) ? OBJ_HLINE : OBJ_TREND;
      if(k == 0 && !InpObjUseHLines)
         continue;
      if(k == 1 && !InpObjUseTrendLines)
         continue;
      int total = ObjectsTotal(0, 0, type);
      for(int i = 0; i < total; i++)
        {
         string name = ObjectName(0, i, 0, type);
         if(name == "")
            continue;
         if(!NameFilterOK(name))
            continue;
         if(InpObjSkipHidden && ObjectGetInteger(0, name, OBJPROP_HIDDEN) != 0)
            continue;
         color c = (color)ObjectGetInteger(0, name, OBJPROP_COLOR);
         if(!ColorFilterOK(c))
            continue;
         SLevel L;
         L.Reset();
         L.key     = "OBJ:" + name;
         L.label   = name;
         L.source  = LT_SRC_OBJECT;
         L.objName = name;
         L.clr     = c;
         L.grade   = (StartsWith(name, "VAL_cur_D") || StartsWith(name, "VAL_fcst_")) ? LT_GRADE_C : LT_GRADE_A;
         if(k == 0)
           {
            L.kind      = 0;
            L.price     = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
            L.prevPrice = L.price;
           }
         else
           {
            L.kind     = 1;
            L.t1       = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
            L.p1       = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
            L.t2       = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
            L.p2       = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
            L.rayRight = InpObjTreatAllAsRays || (ObjectGetInteger(0, name, OBJPROP_RAY_RIGHT) != 0);
            L.rayLeft  = (ObjectGetInteger(0, name, OBJPROP_RAY_LEFT) != 0);
            if(L.t1 == 0 || L.t2 == 0 || L.p1 <= 0.0 || L.p2 <= 0.0)
               continue;
            if(!ComputeSlopedPrices(L))
               continue;
           }
         if(L.price <= 0.0)
            continue;
         AppendLevel(out, L);
        }
     }
  }

//+------------------------------------------------------------------+
//| Source 2: ValueAreaLevels buffers                                |
//+------------------------------------------------------------------+
bool ValBufferEnabled(const int b)
  {
   switch(b)
     {
      case 0: return(InpVAL_UseDVAH);
      case 1: return(InpVAL_UseDPOC);
      case 2: return(InpVAL_UseDVAL);
      case 3: return(InpVAL_UsePDVAH);
      case 4: return(InpVAL_UsePDPOC);
      case 5: return(InpVAL_UsePDVAL);
      case 6: return(InpVAL_UseFVAH);
      case 7: return(InpVAL_UseFPOC);
      case 8: return(InpVAL_UseFVAL);
     }
   return(false);
  }

color ValBufferColor(const int b)
  {
   if(b == 1) return(clrAqua);
   if(b == 4) return(clrWhite);
   if(b >= 6) return(clrViolet);
   if(b >= 3) return(clrOrange);
   return(clrGold);
  }

// carries the previous levels of a source over while that source is temporarily unavailable
void KeepPreviousLevels(SLevel &out[], const int source, const string keyPrefix)
  {
   for(int i = 0; i < ArraySize(g_levels); i++)
      if(g_levels[i].source == source && (keyPrefix == "" || StartsWith(g_levels[i].key, keyPrefix)))
         AppendLevel(out, g_levels[i]);
  }

void ReadValueAreaLevels(SLevel &out[])
  {
   if(g_valHandle == INVALID_HANDLE)
      return;
   if(BarsCalculated(g_valHandle) < 2)
     {
      g_valReady = false;                              // still computing: keep the last known levels
      KeepPreviousLevels(out, LT_SRC_VAL, "");
      return;
     }
   g_valReady = true;
   int barsIntoSession = 100000;
   datetime sess = iTime(_Symbol, InpVAL_ProfilePeriod, 0);
   if(sess > 0)
      barsIntoSession = BarsSince(sess);
   for(int b = 0; b < LT_VAL_BUFFERS; b++)
     {
      if(!ValBufferEnabled(b))
         continue;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(g_valHandle, b, 0, 2, buf) < 2)
         continue;
      double v0 = buf[0];
      double v1 = buf[1];
      if(v0 == EMPTY_VALUE || v0 <= 0.0)
         continue;
      if(v1 == EMPTY_VALUE || v1 <= 0.0 || barsIntoSession == 0)
         v1 = v0;                                       // bar 1 belongs to the previous session: old line
      SLevel L;
      L.Reset();
      L.key       = "VAL:" + g_valNames[b];
      L.label     = g_valNames[b];
      L.source    = LT_SRC_VAL;
      L.kind      = 0;
      L.price     = v0;
      L.prevPrice = v1;
      L.clr       = ValBufferColor(b);
      L.grade     = (b >= 3 && b <= 5) ? LT_GRADE_A : LT_GRADE_C;     // previous session = A, developing / forecast = C
      L.targetOnly = (b <= 2 && barsIntoSession < InpVAL_DevelopingMinBars);
      AppendLevel(out, L);
     }
  }

//+------------------------------------------------------------------+
//| Source 3: built-in MTF ZigZag engine (port of U_MTF_SRTrend1)    |
//+------------------------------------------------------------------+
int LowestIndex(const double &low[], const int n, const int depth, const int shift)
  {
   int best = shift;
   int last = MathMin(n - 1, shift + depth - 1);
   for(int i = shift + 1; i <= last; i++)
      if(low[i] < low[best])
         best = i;
   return(best);
  }

int HighestIndex(const double &high[], const int n, const int depth, const int shift)
  {
   int best = shift;
   int last = MathMin(n - 1, shift + depth - 1);
   for(int i = shift + 1; i <= last; i++)
      if(high[i] > high[best])
         best = i;
   return(best);
  }

// Classic MT4 ZigZag (Depth / Deviation / Backstep) on series arrays (index 0 = newest).
// zz[i] holds the pivot price at bar i or 0.
void ZigZagCompute(const double &high[], const double &low[], const int n,
                   const int depth, const int deviation, const int backstep, double &zz[])
  {
   double hiMap[], loMap[];
   ArrayResize(zz, n);
   ArrayResize(hiMap, n);
   ArrayResize(loMap, n);
   ArrayInitialize(zz, 0.0);
   ArrayInitialize(hiMap, 0.0);
   ArrayInitialize(loMap, 0.0);
   if(n <= depth)
      return;
   int    limit    = n - depth;
   double dev      = deviation * g_point;
   double lastLow  = 0.0;
   double lastHigh = 0.0;
   //--- pass 1: candidate highs and lows
   for(int shift = limit; shift >= 0; shift--)
     {
      double val = low[LowestIndex(low, n, depth, shift)];
      if(val == lastLow)
         val = 0.0;
      else
        {
         lastLow = val;
         if(low[shift] - val > dev)
            val = 0.0;
         else
            for(int back = 1; back <= backstep; back++)
              {
               int idx = shift + back;
               if(idx >= n)
                  break;
               double res = loMap[idx];
               if(res != 0.0 && res > val)
                  loMap[idx] = 0.0;
              }
        }
      loMap[shift] = (low[shift] == val) ? val : 0.0;

      val = high[HighestIndex(high, n, depth, shift)];
      if(val == lastHigh)
         val = 0.0;
      else
        {
         lastHigh = val;
         if(val - high[shift] > dev)
            val = 0.0;
         else
            for(int back = 1; back <= backstep; back++)
              {
               int idx = shift + back;
               if(idx >= n)
                  break;
               double res = hiMap[idx];
               if(res != 0.0 && res < val)
                  hiMap[idx] = 0.0;
              }
        }
      hiMap[shift] = (high[shift] == val) ? val : 0.0;
     }
   //--- pass 2: alternate peaks and troughs
   int whatlookfor = 0;
   int lastHighPos = 0;
   int lastLowPos  = 0;
   lastLow  = 0.0;
   lastHigh = 0.0;
   for(int shift = limit; shift >= 0; shift--)
     {
      switch(whatlookfor)
        {
         case 0:
            if(lastLow == 0.0 && lastHigh == 0.0)
              {
               if(hiMap[shift] != 0.0)
                 {
                  lastHigh = high[shift]; lastHighPos = shift; whatlookfor = -1; zz[shift] = lastHigh;
                 }
               if(loMap[shift] != 0.0)
                 {
                  lastLow = low[shift]; lastLowPos = shift; whatlookfor = 1; zz[shift] = lastLow;
                 }
              }
            break;
         case 1:   // last pivot was a trough
            if(loMap[shift] != 0.0 && loMap[shift] < lastLow && hiMap[shift] == 0.0)
              {
               zz[lastLowPos] = 0.0; lastLowPos = shift; lastLow = loMap[shift]; zz[shift] = lastLow;
              }
            if(hiMap[shift] != 0.0 && loMap[shift] == 0.0)
              {
               lastHigh = hiMap[shift]; lastHighPos = shift; zz[shift] = lastHigh; whatlookfor = -1;
              }
            break;
         case -1:  // last pivot was a peak
            if(hiMap[shift] != 0.0 && hiMap[shift] > lastHigh && loMap[shift] == 0.0)
              {
               zz[lastHighPos] = 0.0; lastHighPos = shift; lastHigh = hiMap[shift]; zz[shift] = lastHigh;
              }
            if(loMap[shift] != 0.0 && hiMap[shift] == 0.0)
              {
               lastLow = loMap[shift]; lastLowPos = shift; zz[shift] = lastLow; whatlookfor = 1;
              }
            break;
        }
     }
  }

// pivots from newest to oldest, flagged peak / trough by alternation
int CollectPivots(const double &zz[], const datetime &times[], const int n, SPivot &piv[])
  {
   ArrayResize(piv, 0);
   for(int i = 0; i < n; i++)
     {
      if(zz[i] <= 0.0)
         continue;
      int k = ArraySize(piv);
      ArrayResize(piv, k + 1);
      piv[k].shift  = i;
      piv[k].time   = times[i];
      piv[k].price  = zz[i];
      piv[k].isPeak = false;
     }
   int cnt = ArraySize(piv);
   if(cnt == 0)
      return(0);
   bool peak = (cnt >= 2) ? (piv[0].price > piv[1].price) : true;
   for(int i = 0; i < cnt; i++)
     {
      piv[i].isPeak = peak;
      peak = !peak;
     }
   return(cnt);
  }

// one timeframe: copies data, runs both ZigZags, fills S/R pivots and the two trend lines
bool ComputeEngineTF(SEngineTF &e)
  {
   e.ready   = false;
   e.srCount = 0;
   e.upValid = false;
   e.dnValid = false;
   int want = MathMax(InpSR_LookbackBars, 50);
   int avail = Bars(_Symbol, e.tf);
   if(avail <= 0)
      return(false);
   if(want > avail)
      want = avail;
   double high[], low[];
   datetime times[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(times, true);
   int n = CopyHigh(_Symbol, e.tf, 0, want, high);
   if(n <= 0)
      return(false);
   if(CopyLow(_Symbol, e.tf, 0, n, low) != n)
      return(false);
   if(CopyTime(_Symbol, e.tf, 0, n, times) != n)
      return(false);
   int minBars = MathMax(InpSR_Depth, InpTL_Depth) + MathMax(InpSR_Backstep, InpTL_Backstep) + 3;
   if(n < minBars)
      return(false);

   double zz[];
   SPivot piv[];
   //--- S/R pivots: the most recent MaxPerTF pivots, skipping the newest one
   if(e.useSR)
     {
      ZigZagCompute(high, low, n, InpSR_Depth, InpSR_Deviation, InpSR_Backstep, zz);
      int cnt = CollectPivots(zz, times, n, piv);
      double ref = (g_tick.bid > 0.0) ? g_tick.bid : low[0];     // like Close[0] in the original
      int maxPer = MathMin(InpSR_MaxPerTF, LT_MAX_SR);
      for(int i = 1; i < cnt && e.srCount < maxPer; i++)
        {
         if(InpSR_FilterPoints > 0 && MathAbs(piv[i].price - ref) > Pts(InpSR_FilterPoints))
            continue;
         e.srPrice[e.srCount] = piv[i].price;
         e.srCount++;
        }
     }
   //--- trend lines: through the two most recent qualifying peaks / troughs
   if(e.useTL)
     {
      ZigZagCompute(high, low, n, InpTL_Depth, InpTL_Deviation, InpTL_Backstep, zz);
      int cnt = CollectPivots(zz, times, n, piv);
      if(cnt >= 3)
        {
         double newest = piv[0].price;
         // descending line: recent peak P1, older peak P2 >= P1
         int i1 = -1;
         for(int i = 0; i < cnt; i++)
           {
            if(!piv[i].isPeak || piv[i].price == newest)
               continue;
            if(i1 < 0)
              {
               i1 = i;
               continue;
              }
            if(piv[i].price >= piv[i1].price)
              {
               e.dnValid = true;
               e.dnT1 = piv[i].time;  e.dnP1 = piv[i].price;     // older anchor
               e.dnT2 = piv[i1].time; e.dnP2 = piv[i1].price;    // recent anchor
               break;
              }
           }
         // ascending line: recent trough T1, older trough T2 <= T1
         i1 = -1;
         for(int i = 0; i < cnt; i++)
           {
            if(piv[i].isPeak || piv[i].price == newest)
               continue;
            if(i1 < 0)
              {
               i1 = i;
               continue;
              }
            if(piv[i].price <= piv[i1].price)
              {
               e.upValid = true;
               e.upT1 = piv[i].time;  e.upP1 = piv[i].price;
               e.upT2 = piv[i1].time; e.upP2 = piv[i1].price;
               break;
              }
           }
        }
     }
   e.ready = true;
   return(true);
  }

// the original indicator's timeframe scheme by chart period
void AutoEngineTimeframes(ENUM_TIMEFRAMES &srTF[], ENUM_TIMEFRAMES &tlTF[])
  {
   int ps = PeriodSeconds(_Period);
   ArrayResize(srTF, 0);
   ArrayResize(tlTF, 0);
   if(ps >= PeriodSeconds(PERIOD_MN1))
     {
      ArrayResize(srTF, 1); srTF[0] = PERIOD_MN1;
     }
   else if(ps >= PeriodSeconds(PERIOD_W1))
     {
      ArrayResize(srTF, 2); srTF[0] = PERIOD_MN1; srTF[1] = PERIOD_W1;
     }
   else if(ps >= PeriodSeconds(PERIOD_D1))
     {
      ArrayResize(srTF, 3); srTF[0] = PERIOD_MN1; srTF[1] = PERIOD_W1; srTF[2] = PERIOD_D1;
     }
   else if(ps >= PeriodSeconds(PERIOD_H4))
     {
      ArrayResize(srTF, 4); srTF[0] = PERIOD_MN1; srTF[1] = PERIOD_W1; srTF[2] = PERIOD_D1; srTF[3] = PERIOD_H4;
     }
   else if(ps >= PeriodSeconds(PERIOD_M30))
     {
      ArrayResize(srTF, 5); srTF[0] = PERIOD_MN1; srTF[1] = PERIOD_W1; srTF[2] = PERIOD_D1; srTF[3] = PERIOD_H4; srTF[4] = PERIOD_H1;
     }
   else
     {
      ArrayResize(srTF, 3); srTF[0] = PERIOD_H4; srTF[1] = PERIOD_H1; srTF[2] = PERIOD_M15;
     }
   ENUM_TIMEFRAMES all[7] = { PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5 };
   for(int i = 0; i < 7; i++)
     {
      if(PeriodSeconds(all[i]) < ps)
         continue;
      int k = ArraySize(tlTF);
      ArrayResize(tlTF, k + 1);
      tlTF[k] = all[i];
     }
  }

void SetupEngine()
  {
   ArrayResize(g_eng, 0);
   if(!InpSR_Enable)
      return;
   ENUM_TIMEFRAMES srTF[], tlTF[];
   string mode = InpSR_Timeframes;
   StringTrimLeft(mode);
   StringTrimRight(mode);
   StringToUpper(mode);
   if(mode == "" || mode == "AUTO")
      AutoEngineTimeframes(srTF, tlTF);
   else
     {
      string parts[];
      SplitList(mode, parts);
      for(int i = 0; i < ArraySize(parts); i++)
        {
         ENUM_TIMEFRAMES tf = StringToTF(parts[i]);
         if(tf == PERIOD_CURRENT)
           {
            LTLog(0, "unknown timeframe '" + parts[i] + "' in InpSR_Timeframes - ignored");
            continue;
           }
         int k = ArraySize(srTF);
         ArrayResize(srTF, k + 1);
         srTF[k] = tf;
         ArrayResize(tlTF, k + 1);
         tlTF[k] = tf;
        }
     }
   for(int pass = 0; pass < 2; pass++)
     {
      int cnt = (pass == 0) ? ArraySize(srTF) : ArraySize(tlTF);
      for(int i = 0; i < cnt; i++)
        {
         ENUM_TIMEFRAMES tf = (pass == 0) ? srTF[i] : tlTF[i];
         int found = -1;
         for(int j = 0; j < ArraySize(g_eng); j++)
            if(g_eng[j].tf == tf)
               found = j;
         if(found < 0)
           {
            found = ArraySize(g_eng);
            ArrayResize(g_eng, found + 1);
            g_eng[found].tf      = tf;
            g_eng[found].useSR   = false;
            g_eng[found].useTL   = false;
            g_eng[found].ready   = false;
            g_eng[found].srCount = 0;
            g_eng[found].upValid = false;
            g_eng[found].dnValid = false;
           }
         if(pass == 0)
            g_eng[found].useSR = InpSR_UseSRLines;
         else
            g_eng[found].useTL = InpSR_UseTrendLines;
        }
     }
   string list = "";
   for(int j = 0; j < ArraySize(g_eng); j++)
      list += (j > 0 ? ";" : "") + TFToString(g_eng[j].tf);
   LTLog(1, "built-in ZigZag engine timeframes: " + list);
  }

void RunEngine()
  {
   for(int j = 0; j < ArraySize(g_eng); j++)
      ComputeEngineTF(g_eng[j]);
   g_lastEngineRun = TimeCurrent();
   if(InpSR_Draw)
      DrawEngineLines();
  }

color EngineSRColor(const ENUM_TIMEFRAMES tf, int &width)
  {
   width = 1;
   switch(tf)
     {
      case PERIOD_MN1: width = 4; return(clrMaroon);
      case PERIOD_W1:  width = 3; return(clrPurple);
      case PERIOD_D1:  width = 2; return(clrRed);
      case PERIOD_H4:  return(clrBrown);
      case PERIOD_H1:  return(clrRoyalBlue);
      case PERIOD_M15: return(clrChocolate);
      default:         return(clrGray);
     }
  }

color EngineTLColor(const ENUM_TIMEFRAMES tf, ENUM_LINE_STYLE &style)
  {
   style = STYLE_DASH;
   switch(tf)
     {
      case PERIOD_MN1: return(clrDarkViolet);
      case PERIOD_W1:  return(clrWhite);
      case PERIOD_D1:  return(clrRed);
      case PERIOD_H4:  return(clrYellow);
      case PERIOD_H1:  style = STYLE_DOT; return(clrAqua);
      case PERIOD_M15: style = STYLE_DOT; return(clrGreen);
      case PERIOD_M5:  style = STYLE_DOT; return(clrHotPink);
      default:         return(clrGray);
     }
  }

void DrawOwnTrend(const string name, const bool valid, const datetime t1, const double p1,
                  const datetime t2, const double p2, const color clr, const ENUM_LINE_STYLE style)
  {
   if(!valid)
     {
      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);
      return;
     }
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
         return;
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
  }

void DrawEngineLines()
  {
   if(g_isTester && !g_isVisual)
      return;
   for(int j = 0; j < ArraySize(g_eng); j++)
     {
      string tfs = TFToString(g_eng[j].tf);
      int width = 1;
      color srClr = EngineSRColor(g_eng[j].tf, width);
      int maxPer = MathMin(InpSR_MaxPerTF, LT_MAX_SR);
      for(int i = 0; i < maxPer; i++)
        {
         string name = LT_SR_PREFIX + tfs + "_" + IntegerToString(i);
         if(!g_eng[j].useSR || i >= g_eng[j].srCount)
           {
            if(ObjectFind(0, name) >= 0)
               ObjectDelete(0, name);
            continue;
           }
         if(ObjectFind(0, name) < 0)
           {
            if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, g_eng[j].srPrice[i]))
               continue;
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, name, OBJPROP_BACK, true);
            ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
           }
         ObjectSetDouble(0, name, OBJPROP_PRICE, 0, g_eng[j].srPrice[i]);
         ObjectSetInteger(0, name, OBJPROP_COLOR, srClr);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
         ObjectSetString(0, name, OBJPROP_TOOLTIP, tfs + " S/R " + PriceStr(g_eng[j].srPrice[i]));
        }
      ENUM_LINE_STYLE style = STYLE_DASH;
      color tlClr = EngineTLColor(g_eng[j].tf, style);
      DrawOwnTrend(LT_TL_PREFIX + tfs + "_Down", g_eng[j].useTL && g_eng[j].dnValid,
                   g_eng[j].dnT1, g_eng[j].dnP1, g_eng[j].dnT2, g_eng[j].dnP2, tlClr, style);
      DrawOwnTrend(LT_TL_PREFIX + tfs + "_Up", g_eng[j].useTL && g_eng[j].upValid,
                   g_eng[j].upT1, g_eng[j].upP1, g_eng[j].upT2, g_eng[j].upP2, tlClr, style);
     }
  }

int EngineGrade(const ENUM_TIMEFRAMES tf, const bool trendLine)
  {
   int ps = PeriodSeconds(tf);
   if(ps >= PeriodSeconds(PERIOD_W1))
      return(LT_GRADE_A);
   if(ps >= PeriodSeconds(PERIOD_D1))
      return(trendLine ? LT_GRADE_B : LT_GRADE_A);
   if(ps >= PeriodSeconds(PERIOD_H4))
      return(LT_GRADE_B);
   return(LT_GRADE_C);
  }

void ReadEngineLevels(SLevel &out[])
  {
   for(int j = 0; j < ArraySize(g_eng); j++)
     {
      string tfs = TFToString(g_eng[j].tf);
      if(!g_eng[j].ready)
        {
         KeepPreviousLevels(out, LT_SRC_ENGINE_SR, "SR:" + tfs + ":");
         KeepPreviousLevels(out, LT_SRC_ENGINE_TL, "TL:" + tfs + ":");
         continue;
        }
      if(g_eng[j].useSR)
         for(int i = 0; i < g_eng[j].srCount; i++)
           {
            SLevel L;
            L.Reset();
            L.key       = "SR:" + tfs + ":" + PriceStr(g_eng[j].srPrice[i]);
            L.label     = tfs + " SR";
            L.source    = LT_SRC_ENGINE_SR;
            L.kind      = 0;
            L.price     = g_eng[j].srPrice[i];
            L.prevPrice = L.price;
            int w = 1;
            L.clr       = EngineSRColor(g_eng[j].tf, w);
            L.grade     = EngineGrade(g_eng[j].tf, false);
            AppendLevel(out, L);
           }
      if(g_eng[j].useTL)
         for(int d = 0; d < 2; d++)
           {
            bool valid = (d == 0) ? g_eng[j].dnValid : g_eng[j].upValid;
            if(!valid)
               continue;
            SLevel L;
            L.Reset();
            datetime kt1 = (d == 0) ? g_eng[j].dnT1 : g_eng[j].upT1;
            datetime kt2 = (d == 0) ? g_eng[j].dnT2 : g_eng[j].upT2;
            L.key      = "TL:" + tfs + ((d == 0) ? ":Down:" : ":Up:")
                         + IntegerToString((long)kt1) + ":" + IntegerToString((long)kt2);
            L.label    = tfs + ((d == 0) ? " TL down" : " TL up");
            L.source   = LT_SRC_ENGINE_TL;
            L.kind     = 1;
            L.t1       = (d == 0) ? g_eng[j].dnT1 : g_eng[j].upT1;
            L.p1       = (d == 0) ? g_eng[j].dnP1 : g_eng[j].upP1;
            L.t2       = (d == 0) ? g_eng[j].dnT2 : g_eng[j].upT2;
            L.p2       = (d == 0) ? g_eng[j].dnP2 : g_eng[j].upP2;
            L.rayRight = true;
            L.rayLeft  = false;
            ENUM_LINE_STYLE st = STYLE_DASH;
            L.clr      = EngineTLColor(g_eng[j].tf, st);
            L.grade    = EngineGrade(g_eng[j].tf, true);
            if(!ComputeSlopedPrices(L))
               continue;
            AppendLevel(out, L);
           }
     }
  }

//+------------------------------------------------------------------+
//| Source 4: manual levels                                          |
//+------------------------------------------------------------------+
void ParseManualInputs()
  {
   ArrayResize(g_manualPrice, 0);
   string parts[];
   SplitList(InpManualLevels, parts);
   for(int i = 0; i < ArraySize(parts); i++)
     {
      double p = StringToDouble(parts[i]);
      if(p <= 0.0)
        {
         LTLog(0, "manual level '" + parts[i] + "' is not a price - ignored");
         continue;
        }
      int k = ArraySize(g_manualPrice);
      ArrayResize(g_manualPrice, k + 1);
      g_manualPrice[k] = p;
     }
   SplitList(InpManualTrendLines, g_manualTL);
  }

void ReadManualLevels(SLevel &out[])
  {
   for(int i = 0; i < ArraySize(g_manualPrice); i++)
     {
      SLevel L;
      L.Reset();
      L.key       = "MAN:" + PriceStr(g_manualPrice[i]);
      L.label     = "Manual";
      L.source    = LT_SRC_MANUAL;
      L.kind      = 0;
      L.price     = g_manualPrice[i];
      L.prevPrice = L.price;
      L.clr       = clrSilver;
      L.grade     = LT_GRADE_A;
      AppendLevel(out, L);
     }
   for(int i = 0; i < ArraySize(g_manualTL); i++)
     {
      string f[];
      if(StringSplit(g_manualTL[i], '|', f) != 4)
        {
         LTLog(0, "manual trend line '" + g_manualTL[i] + "' must be t1|p1|t2|p2 - ignored");
         continue;
        }
      SLevel L;
      L.Reset();
      L.key      = "MTL:" + IntegerToString(i);
      L.label    = "Manual TL " + IntegerToString(i + 1);
      L.source   = LT_SRC_MANUAL;
      L.kind     = 1;
      L.t1       = StringToTime(f[0]);
      L.p1       = StringToDouble(f[1]);
      L.t2       = StringToTime(f[2]);
      L.p2       = StringToDouble(f[3]);
      L.rayRight = true;
      L.rayLeft  = false;
      L.clr      = clrSilver;
      L.grade    = LT_GRADE_A;
      if(L.t1 == 0 || L.t2 == 0 || L.p1 <= 0.0 || L.p2 <= 0.0 || L.t1 == L.t2)
        {
         LTLog(0, "manual trend line '" + g_manualTL[i] + "' has invalid anchors - ignored");
         continue;
        }
      if(!ComputeSlopedPrices(L))
         continue;
      AppendLevel(out, L);
     }
  }

//+------------------------------------------------------------------+
//| Merge nearby levels and carry the trading state over by key      |
//+------------------------------------------------------------------+
int SourceRank(const int source)
  {
   switch(source)
     {
      case LT_SRC_VAL:       return(0);
      case LT_SRC_OBJECT:    return(1);
      case LT_SRC_ENGINE_SR: return(2);
      case LT_SRC_ENGINE_TL: return(3);
     }
   return(4);
  }

// lower = better primary for a merged cluster: tradable first, then grade, then source
int LevelPriority(const SLevel &L)
  {
   return((L.targetOnly ? 1000 : 0) + L.grade * 100 + SourceRank(L.source));
  }

void SortLevelsByPrice(SLevel &arr[])
  {
   int n = ArraySize(arr);
   for(int i = 1; i < n; i++)
     {
      SLevel tmp = arr[i];
      int j = i - 1;
      while(j >= 0 && arr[j].price > tmp.price)
        {
         arr[j + 1] = arr[j];
         j--;
        }
      arr[j + 1] = tmp;
     }
  }

void MergeLevels(SLevel &src[], SLevel &out[])
  {
   ArrayResize(out, 0);
   SortLevelsByPrice(src);
   int n = ArraySize(src);
   double dist = Pts(InpMergeDistancePoints);
   int i = 0;
   while(i < n)
     {
      int j = i + 1;
      if(InpMergeDistancePoints > 0)
         while(j < n && src[j].price - src[i].price <= dist)
            j++;
      // group [i, j): primary = best priority, then lowest price
      int  best = i;
      int  bestGrade = src[i].grade;
      bool allTargetOnly = src[i].targetOnly;
      for(int k = i + 1; k < j; k++)
        {
         if(LevelPriority(src[k]) < LevelPriority(src[best]))
            best = k;
         if(src[k].grade < bestGrade)
            bestGrade = src[k].grade;
         if(!src[k].targetOnly)
            allTargetOnly = false;
        }
      SLevel L = src[best];
      int keep = -1;                                   // a member that already exists keeps the identity stable
      for(int k = i; k < j && keep < 0; k++)
         if(FindLevelByKey(g_levels, src[k].key) >= 0)
            keep = k;
      if(keep >= 0 && keep != best)
         L.key = src[keep].key;
      L.members = "";
      for(int k = i; k < j; k++)
        {
         L.members += src[k].key + ";";
         if(k != best)
            L.label += "+" + src[k].label;
        }
      L.grade = bestGrade;
      L.targetOnly = allTargetOnly || (L.grade > (int)InpMinEntryGrade);
      AppendLevel(out, L);
      i = j;
     }
  }

// a level whose price jumped (developing value area at a session start, a dragged line,
// a positional indicator name that now holds another pivot) is a new level: start over
void ResetLevelDynamics(SLevel &L)
  {
   L.role = 0;
   L.pendingRole = 0;
   L.pendingRoleCount = 0;
   L.lastSide = 0;
   L.inTouch = false;
   L.touchExtreme = 0.0;
   L.needReset = false;
   L.lastSignalTime = 0;
   L.trades = 0;
   L.flipCount = 0;
   L.flipWindowStart = 0;
   L.lastFlipTime = 0;
   L.prevPrice = L.price;
  }

bool ApplySavedState(SLevel &L)
  {
   for(int i = 0; i < ArraySize(g_saved); i++)
     {
      if(g_saved[i].key != L.key)
         continue;
      if(g_saved[i].price > 0.0 && MathAbs(g_saved[i].price - L.price) > g_zone)
        {
         int lastIdx = ArraySize(g_saved) - 1;          // saved for another price: discard
         if(i != lastIdx)
            g_saved[i] = g_saved[lastIdx];
         ArrayResize(g_saved, lastIdx);
         return(false);
        }
      L.role            = g_saved[i].role;
      L.needReset       = g_saved[i].needReset;
      L.lastSignalTime  = g_saved[i].lastSignalTime;
      L.trades          = g_saved[i].trades;
      L.flipCount       = g_saved[i].flipCount;
      L.flipWindowStart = g_saved[i].flipWindowStart;
      L.lastFlipTime    = g_saved[i].lastFlipTime;
      int last = ArraySize(g_saved) - 1;
      if(i != last)
         g_saved[i] = g_saved[last];
      ArrayResize(g_saved, last);
      return(true);
     }
   return(false);
  }

void RebuildLevels()
  {
   SLevel fresh[];
   ScanChartObjects(fresh);
   ReadValueAreaLevels(fresh);
   ReadEngineLevels(fresh);
   ReadManualLevels(fresh);
   SLevel merged[];
   MergeLevels(fresh, merged);
   for(int i = 0; i < ArraySize(merged); i++)
     {
      int old = FindLevelByKey(g_levels, merged[i].key);
      if(old < 0)                                      // a member of the cluster may carry the state
         for(int o = 0; o < ArraySize(g_levels) && old < 0; o++)
            if(StringFind(merged[i].members, g_levels[o].key + ";") >= 0
               || StringFind(g_levels[o].members, merged[i].key + ";") >= 0)
               old = o;
      if(old >= 0)
        {
         merged[i].CopyStateFrom(g_levels[old]);
         if(MathAbs(merged[i].price - g_levels[old].price) > g_zone)
            ResetLevelDynamics(merged[i]);
        }
      else
         ApplySavedState(merged[i]);
     }
   ArrayResize(g_levels, ArraySize(merged));
   for(int i = 0; i < ArraySize(merged); i++)
      g_levels[i] = merged[i];
   g_lastObjScan = TimeCurrent();
   g_objDirty = false;
  }

//+------------------------------------------------------------------+
//| State file: level state survives a restart (not in the tester)   |
//+------------------------------------------------------------------+
string StateFileName()
  {
   return("LineTouchEA_" + _Symbol + "_" + IntegerToString((long)InpMagic) + ".txt");
  }

string StateLine(const string key, const double price, const int role, const bool needReset, const datetime lastSignalTime,
                 const int trades, const int flipCount, const datetime flipWindowStart, const datetime lastFlipTime)
  {
   return(key + "|" + PriceStr(price) + "|" + IntegerToString(role) + "|" + (needReset ? "1" : "0") + "|"
          + IntegerToString((long)lastSignalTime) + "|" + IntegerToString(trades) + "|"
          + IntegerToString(flipCount) + "|" + IntegerToString((long)flipWindowStart) + "|"
          + IntegerToString((long)lastFlipTime));
  }

void SaveState()
  {
   g_stateDirty = false;
   if(!InpPersistState || g_isTester)
      return;
   int h = FileOpen(StateFileName(), FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      LTLog(2, "cannot write the state file (error " + IntegerToString(GetLastError()) + ")");
      return;
     }
   FileWriteString(h, "LTEA1|" + IntegerToString((long)TimeCurrent()) + "\r\n");
   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      if(StringFind(g_levels[i].key, "|") >= 0)
         continue;
      if(g_levels[i].trades == 0 && g_levels[i].lastSignalTime == 0 && g_levels[i].flipCount == 0
         && !g_levels[i].needReset && g_levels[i].role == 0)
         continue;
      FileWriteString(h, StateLine(g_levels[i].key, g_levels[i].price, g_levels[i].role, g_levels[i].needReset,
                                   g_levels[i].lastSignalTime, g_levels[i].trades, g_levels[i].flipCount,
                                   g_levels[i].flipWindowStart, g_levels[i].lastFlipTime) + "\r\n");
     }
   for(int i = 0; i < ArraySize(g_saved); i++)        // levels not seen yet this session keep their saved state
     {
      datetime newest = (g_saved[i].lastSignalTime > g_saved[i].lastFlipTime) ? g_saved[i].lastSignalTime : g_saved[i].lastFlipTime;
      if(newest > 0 && TimeCurrent() - newest > 7 * 86400)
         continue;                                    // stale record: let it expire
      FileWriteString(h, StateLine(g_saved[i].key, g_saved[i].price, g_saved[i].role, g_saved[i].needReset,
                                   g_saved[i].lastSignalTime, g_saved[i].trades, g_saved[i].flipCount,
                                   g_saved[i].flipWindowStart, g_saved[i].lastFlipTime) + "\r\n");
     }
   FileClose(h);
  }

void LoadState()
  {
   ArrayResize(g_saved, 0);
   if(!InpPersistState || g_isTester)
      return;
   if(!FileIsExist(StateFileName()))
      return;
   int h = FileOpen(StateFileName(), FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   string header = FileReadString(h);
   string hp[];
   if(StringSplit(header, '|', hp) != 2 || hp[0] != "LTEA1")
     {
      FileClose(h);
      return;
     }
   datetime savedAt = (datetime)StringToInteger(hp[1]);
   if(TimeCurrent() - savedAt > 7 * 86400)
     {
      FileClose(h);
      LTLog(1, "state file is older than 7 days - ignored");
      return;
     }
   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      string f[];
      if(StringSplit(line, '|', f) != 9)
         continue;
      datetime lastSig  = (datetime)StringToInteger(f[4]);
      datetime lastFlip = (datetime)StringToInteger(f[8]);
      datetime newest   = (lastSig > lastFlip) ? lastSig : lastFlip;
      if(newest > 0 && TimeCurrent() - newest > 7 * 86400)
         continue;                                    // stale record
      int k = ArraySize(g_saved);
      ArrayResize(g_saved, k + 1);
      g_saved[k].key             = f[0];
      g_saved[k].price           = StringToDouble(f[1]);
      g_saved[k].role            = (int)StringToInteger(f[2]);
      g_saved[k].needReset       = (f[3] == "1");
      g_saved[k].lastSignalTime  = lastSig;
      g_saved[k].trades          = (int)StringToInteger(f[5]);
      g_saved[k].flipCount       = (int)StringToInteger(f[6]);
      g_saved[k].flipWindowStart = (datetime)StringToInteger(f[7]);
      g_saved[k].lastFlipTime    = lastFlip;
     }
   FileClose(h);
   LTLog(1, "restored saved state for " + IntegerToString(ArraySize(g_saved)) + " levels");
  }

//+------------------------------------------------------------------+
//| Market state                                                     |
//+------------------------------------------------------------------+
bool UpdateMarket()
  {
   if(!SymbolInfoTick(_Symbol, g_tick))
      return(false);
   if(g_tick.bid <= 0.0 || g_tick.ask <= 0.0)
      return(false);
   g_stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return(true);
  }

void UpdateATR()
  {
   if(g_atrHandle == INVALID_HANDLE)
      return;
   double a[];
   ArraySetAsSeries(a, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, a) == 1 && a[0] > 0.0)
      g_atr = a[0];
  }

void UpdateZone()
  {
   g_zone = Pts(InpTouchZonePoints);
   if(InpZoneATRFraction > 0.0 && g_atr > 0.0)
      g_zone = MathMax(g_zone, g_atr * InpZoneATRFraction);
  }

// every distance below = max(points, ATR x fraction)
double ATRScaled(const int points, const double atrFraction)
  {
   double d = Pts(points);
   if(atrFraction > 0.0 && g_atr > 0.0)
      d = MathMax(d, g_atr * atrFraction);
   return(d);
  }

double BreakBuffer()
  {
   return(ATRScaled(InpBreakoutBufferPoints, InpBreakoutBufferATRFraction));
  }

double RearmDistance()
  {
   return(ATRScaled(InpRearmPoints, InpRearmATRFraction));
  }

double SLBuffer()
  {
   return(ATRScaled(InpSLBufferPoints, InpSLBufferATRFraction));
  }

int SpreadPoints()
  {
   return((int)MathRound((g_tick.ask - g_tick.bid) / g_point));
  }

//+------------------------------------------------------------------+
//| Positions and orders of this EA                                  |
//+------------------------------------------------------------------+
bool IsOurPosition()
  {
   return(PositionGetInteger(POSITION_MAGIC) == (long)InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol);
  }

bool IsOurOrder()
  {
   return(OrderGetInteger(ORDER_MAGIC) == (long)InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol);
  }

void CountPositions(int &buys, int &sells)
  {
   buys = 0;
   sells = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !IsOurPosition())
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         buys++;
      else
         sells++;
     }
  }

int CountPendingOrders()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0 || !IsOurOrder())
         continue;
      n++;
     }
   return(n);
  }

void LinkTicket(const ulong ticket, const string key)
  {
   for(int i = 0; i < ArraySize(g_links); i++)
      if(g_links[i].ticket == ticket)
        {
         g_links[i].key = key;
         return;
        }
   int k = ArraySize(g_links);
   ArrayResize(g_links, k + 1);
   g_links[k].ticket = ticket;
   g_links[k].key = key;
  }

string LinkedKey(const ulong ticket)
  {
   for(int i = 0; i < ArraySize(g_links); i++)
      if(g_links[i].ticket == ticket)
         return(g_links[i].key);
   return("");
  }

// position id a filled order opened into (0 when unknown); works on netting accounts too
ulong OrderPositionId(const ulong orderTicket)
  {
   if(!HistoryOrderSelect(orderTicket))
      return(0);
   return((ulong)HistoryOrderGetInteger(orderTicket, ORDER_POSITION_ID));
  }

// forget links of tickets that are neither open positions nor pending orders
void PruneLinks()
  {
   int n = ArraySize(g_links);
   int w = 0;
   for(int i = 0; i < n; i++)
     {
      bool alive = PositionSelectByTicket(g_links[i].ticket) || OrderSelect(g_links[i].ticket);
      if(!alive)
        {
         for(int j = PositionsTotal() - 1; j >= 0 && !alive; j--)
            if(PositionGetTicket(j) != 0 && IsOurPosition()
               && (ulong)PositionGetInteger(POSITION_IDENTIFIER) == g_links[i].ticket)
               alive = true;
        }
      if(!alive)
        {
         ulong pid = OrderPositionId(g_links[i].ticket);
         alive = (pid != 0 && PositionSelectByTicket(pid));
        }
      if(alive)
        {
         if(w != i)
            g_links[w] = g_links[i];
         w++;
        }
     }
   ArrayResize(g_links, w);
  }

// does the selected position belong to the level (or to a level merged into it)?
bool SelectedPositionIsLevel(const SLevel &L)
  {
   ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   ulong ident  = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   for(int i = 0; i < ArraySize(g_links); i++)
     {
      if(g_links[i].key != L.key && (L.members == "" || StringFind(L.members, g_links[i].key + ";") < 0))
         continue;
      if(g_links[i].ticket == ticket || g_links[i].ticket == ident)
         return(true);
      if(OrderPositionId(g_links[i].ticket) == ident)     // netting: order filled into this position
         return(true);
     }
   return(CommentMatchesLevel(PositionGetString(POSITION_COMMENT), L));
  }

int CountLevelPositions(const SLevel &L)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !IsOurPosition())
         continue;
      if(SelectedPositionIsLevel(L))
         n++;
     }
   return(n);
  }

bool EntrySpacingOK(const int dir, const double entry)
  {
   if(InpMinEntrySpacingPoints <= 0)
      return(true);
   double minDist = Pts(InpMinEntrySpacingPoints);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !IsOurPosition())
         continue;
      int pdir = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      if(pdir != dir)
         continue;
      if(MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - entry) < minDist)
         return(false);
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)           // resting orders reserve their price too
     {
      if(OrderGetTicket(i) == 0 || !IsOurOrder())
         continue;
      int type = (int)OrderGetInteger(ORDER_TYPE);
      int odir = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP) ? 1 : -1;
      if(odir != dir)
         continue;
      if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - entry) < minDist)
         return(false);
     }
   return(true);
  }

bool CloseOppositePositions(const int dir)
  {
   bool ok = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition())
         continue;
      int pdir = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      if(pdir == dir)
         continue;
      if(!g_trade.PositionClose(ticket, (ulong)InpDeviationPoints))
        {
         LTLog(0, "failed to close opposite position #" + IntegerToString((long)ticket) + ": "
               + g_trade.ResultRetcodeDescription());
         ok = false;
        }
      else
         LTLog(1, "closed opposite position #" + IntegerToString((long)ticket));
     }
   return(ok);
  }

//+------------------------------------------------------------------+
//| Daily statistics and the daily loss stop                         |
//+------------------------------------------------------------------+
void AddLoss(const string hash, const double price)
  {
   int k = ArraySize(g_losses);
   ArrayResize(g_losses, k + 1);
   g_losses[k].hash  = hash;
   g_losses[k].price = price;
  }

// losing trades today on this level: same hash (any merged member) and an entry near the level's price,
// so a positional indicator name that now holds another pivot is not locked by the old one's loss
int LevelLossesToday(const SLevel &L)
  {
   double tol = 2.0 * g_zone + Pts(InpPendingOffsetPoints);
   int n = 0;
   for(int i = 0; i < ArraySize(g_losses); i++)
     {
      if(g_losses[i].price > 0.0 && MathAbs(g_losses[i].price - L.price) > tol)
         continue;
      string probe = "|" + g_losses[i].hash;
      if(CommentMatchesLevel(probe, L))
         n++;
     }
   return(n);
  }

void UpdateDailyStats(const bool scanHistory)
  {
   datetime now = TimeCurrent();
   datetime dayStart = StartOfDay(now);
   bool newDay = (dayStart != g_dayStart);
   if(newDay)
     {
      g_dayStart   = dayStart;
      g_dayStopped = false;
     }
   if(scanHistory || newDay)
     {
      g_dayRealized  = 0.0;
      g_dayTrades    = 0;
      g_consecLosses = 0;
      ArrayResize(g_losses, 0);
      ulong  posIds[];                                  // position id -> level hash / entry price (from entry deals)
      string posHash[];
      double posPrice[];
      ulong  unresolved[];                              // losing positions whose entry deal is older than the window
      if(HistorySelect(dayStart - 3 * 86400, now + 86400))
        {
         int total = HistoryDealsTotal();
         for(int i = 0; i < total; i++)
           {
            ulong deal = HistoryDealGetTicket(i);
            if(deal == 0)
               continue;
            if(HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)InpMagic)
               continue;
            if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
               continue;
            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
            datetime dealTime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
            ulong posId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
            if(entry == DEAL_ENTRY_IN)
              {
               string c = StringSubstr(HistoryDealGetString(deal, DEAL_COMMENT), 0, 64);
               int bar = StringFind(c, "|");
               if(bar >= 0 && StringLen(c) >= bar + 9)
                 {
                  int k = ArraySize(posIds);
                  ArrayResize(posIds, k + 1);
                  ArrayResize(posHash, k + 1);
                  ArrayResize(posPrice, k + 1);
                  posIds[k]   = posId;
                  posHash[k]  = StringSubstr(c, bar + 1, 8);
                  posPrice[k] = HistoryDealGetDouble(deal, DEAL_PRICE);
                 }
              }
            if(dealTime < dayStart)
               continue;
            if(entry == DEAL_ENTRY_IN)
               g_dayTrades++;
            double pl = HistoryDealGetDouble(deal, DEAL_PROFIT)
                        + HistoryDealGetDouble(deal, DEAL_COMMISSION)
                        + HistoryDealGetDouble(deal, DEAL_SWAP);
            g_dayRealized += pl;
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
              {
               if(pl < 0.0)
                 {
                  g_consecLosses++;
                  bool found = false;
                  for(int k = 0; k < ArraySize(posIds); k++)
                     if(posIds[k] == posId)
                       {
                        AddLoss(posHash[k], posPrice[k]);  // every level that filled into this position
                        found = true;
                       }
                  if(!found)
                    {
                     int u = ArraySize(unresolved);
                     ArrayResize(unresolved, u + 1);
                     unresolved[u] = posId;
                    }
                 }
               else if(pl > 0.0)
                  g_consecLosses = 0;
              }
           }
        }
      // entry deals older than the window: look the position up directly (replaces the selection)
      for(int u = 0; u < ArraySize(unresolved); u++)
        {
         if(!HistorySelectByPosition(unresolved[u]))
            continue;
         int cnt = HistoryDealsTotal();
         for(int d = 0; d < cnt; d++)
           {
            ulong dl = HistoryDealGetTicket(d);
            if(dl == 0 || (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dl, DEAL_ENTRY) != DEAL_ENTRY_IN)
               continue;
            string c = StringSubstr(HistoryDealGetString(dl, DEAL_COMMENT), 0, 64);
            int bar = StringFind(c, "|");
            if(bar >= 0 && StringLen(c) >= bar + 9)
               AddLoss(StringSubstr(c, bar + 1, 8), HistoryDealGetDouble(dl, DEAL_PRICE));
           }
        }
      g_lastHistoryScan = now;
     }
   g_dayFloating = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !IsOurPosition())
         continue;
      g_dayFloating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayRealized;
   if(InpMaxDailyLossPercent > 0.0 && !g_dayStopped && g_dayStartBalance > 0.0)
     {
      double limit = -g_dayStartBalance * InpMaxDailyLossPercent / 100.0;
      if(g_dayRealized + g_dayFloating <= limit)
        {
         g_dayStopped = true;
         LTLog(0, "daily loss limit reached (" + DoubleToString(g_dayRealized + g_dayFloating, 2)
               + ") - no new trades until the next day");
        }
     }
   if(InpMaxConsecutiveLosses > 0 && !g_dayStopped && g_consecLosses >= InpMaxConsecutiveLosses)
     {
      g_dayStopped = true;
      LTLog(0, IntegerToString(g_consecLosses) + " losses in a row - no new trades until the next day");
     }
  }

//+------------------------------------------------------------------+
//| Permission to trade now                                          |
//+------------------------------------------------------------------+
bool TradingAllowed(string &why)
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      why = "AutoTrading is disabled in the terminal";
      return(false);
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      why = "Algo trading is not allowed for this EA (check the EA properties)";
      return(false);
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
     {
      why = "trading is not allowed on this account";
      return(false);
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     {
      why = "expert trading is not allowed on this account";
      return(false);
     }
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED || mode == SYMBOL_TRADE_MODE_CLOSEONLY)
     {
      why = "symbol is not tradable now";
      return(false);
     }
   return(true);
  }

bool DirectionPermitted(const int dir)
  {
   if(dir > 0 && InpTradePermit == LT_PERMIT_SELL_ONLY)
      return(false);
   if(dir < 0 && InpTradePermit == LT_PERMIT_BUY_ONLY)
      return(false);
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(dir > 0 && mode == SYMBOL_TRADE_MODE_SHORTONLY)
      return(false);
   if(dir < 0 && mode == SYMBOL_TRADE_MODE_LONGONLY)
      return(false);
   return(true);
  }

bool TimeFilterOK()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpFridayStopHour > 0 && dt.day_of_week == 5 && dt.hour >= InpFridayStopHour)
      return(false);
   if(InpRolloverSkipMinutes > 0)
     {
      int minuteOfDay = dt.hour * 60 + dt.min;
      if(minuteOfDay >= 1440 - InpRolloverSkipMinutes || minuteOfDay < InpRolloverSkipMinutes)
         return(false);
     }
   if(!InpUseTimeFilter)
      return(true);
   if(InpStartHour == InpEndHour)
      return(true);
   if(InpStartHour < InpEndHour)
      return(dt.hour >= InpStartHour && dt.hour < InpEndHour);
   return(dt.hour >= InpStartHour || dt.hour < InpEndHour);      // overnight window
  }

bool MAFilterOK(const int dir)
  {
   if(!InpUseMAFilter || g_maHandle == INVALID_HANDLE)
      return(true);
   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(g_maHandle, 0, 1, 1, ma) != 1 || ma[0] <= 0.0)
      return(false);
   double c = iClose(_Symbol, (InpMATF == PERIOD_CURRENT) ? g_sigTF : InpMATF, 1);
   if(c <= 0.0)
      return(false);
   return((dir > 0) ? (c > ma[0]) : (c < ma[0]));
  }

bool ADXFilterOK(const int dir, string &why)
  {
   if(!InpUseADXFilter || g_adxHandle == INVALID_HANDLE)
      return(true);
   double adx[], pdi[], mdi[];
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(pdi, true);
   ArraySetAsSeries(mdi, true);
   if(CopyBuffer(g_adxHandle, 0, 1, 1, adx) != 1 || CopyBuffer(g_adxHandle, 1, 1, 1, pdi) != 1
      || CopyBuffer(g_adxHandle, 2, 1, 1, mdi) != 1)
     {
      why = "ADX data not ready";
      return(false);
     }
   if(adx[0] < InpADXThreshold)
      return(true);
   bool up = (pdi[0] > mdi[0]);
   if((dir > 0) ? up : !up)
      return(true);
   why = "against the ADX trend";
   return(false);
  }

// bounce entries are skipped when price slams into the level
bool MomentumFilterOK(const int touchBar, string &why)
  {
   if(g_atr <= 0.0)
      return(true);
   if(InpMaxImpulseATR > 0.0)
     {
      double c1 = iClose(_Symbol, g_sigTF, 1);
      double c4 = iClose(_Symbol, g_sigTF, 4);
      if(c1 > 0.0 && c4 > 0.0 && MathAbs(c1 - c4) > InpMaxImpulseATR * g_atr)
        {
         why = "impulse move into the level";
         return(false);
        }
     }
   if(InpMaxBarRangeATR > 0.0)
     {
      double h = iHigh(_Symbol, g_sigTF, touchBar);
      double l = iLow(_Symbol, g_sigTF, touchBar);
      if(h > 0.0 && l > 0.0 && h - l > InpMaxBarRangeATR * g_atr)
        {
         why = "touching bar range too large";
         return(false);
        }
     }
   return(true);
  }

bool OppositeConflict(const int dir, const int buys, const int sells, const bool marketOrder, string &why)
  {
   int opposite = (dir > 0) ? sells : buys;
   if(opposite == 0)
      return(false);
   if(InpOppositeMode == LT_OPP_HEDGE)
     {
      if(g_hedging)
         return(false);
      why = "opposite position open (netting account cannot hedge)";
      return(true);
     }
   if(InpOppositeMode == LT_OPP_CLOSE_FIRST && marketOrder)
      return(false);
   why = "opposite position open";
   return(true);
  }

// common checks for a new entry (market or pending); touchBar = bar whose range is checked
bool EntryAllowed(const int dir, const SLevel &L, const bool marketOrder, const int touchBar, string &why)
  {
   if(InpTradeMode == LT_MODE_LIVE && !TradingAllowed(why))
      return(false);
   if(!DirectionPermitted(dir))
     {
      why = "direction not permitted";
      return(false);
     }
   if(g_dayStopped)
     {
      why = "stopped for the day (loss limit)";
      return(false);
     }
   if(InpMaxTradesPerDay > 0 && g_dayTrades >= InpMaxTradesPerDay)
     {
      why = "max trades per day reached";
      return(false);
     }
   if(InpMaxSpreadPoints > 0 && SpreadPoints() > InpMaxSpreadPoints)
     {
      why = "spread " + IntegerToString(SpreadPoints()) + " > max";
      return(false);
     }
   if(!TimeFilterOK())
     {
      why = "outside trading hours / rollover";
      return(false);
     }
   if(!MAFilterOK(dir))
     {
      why = "against the MA trend";
      return(false);
     }
   if(!ADXFilterOK(dir, why))
      return(false);
   if(InpDirectionMode == LT_DIR_BOUNCE && !MomentumFilterOK(touchBar, why))
      return(false);
   int buys = 0, sells = 0;
   CountPositions(buys, sells);
   int same = (dir > 0) ? buys : sells;
   int counted = (InpOppositeMode == LT_OPP_CLOSE_FIRST && marketOrder) ? same : buys + sells;
   if(!marketOrder)
      counted += CountPendingOrders();                 // every resting order can fill in the same bar
   if(counted >= InpMaxOpenPositions)
     {
      why = "max open positions reached";
      return(false);
     }
   if(InpMaxPositionsPerLevel > 0 && CountLevelPositions(L) >= InpMaxPositionsPerLevel)
     {
      why = "level already has a position";
      return(false);
     }
   if(OppositeConflict(dir, buys, sells, marketOrder, why))
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Stop-loss, take-profit, lot size                                 |
//+------------------------------------------------------------------+
double ComputeSL(const int dir, const double entry, const double levelPrice)
  {
   double sl = 0.0;
   switch(InpSLMode)
     {
      case LT_SL_BEYOND_LEVEL:
         sl = (dir > 0) ? levelPrice - SLBuffer() : levelPrice + SLBuffer();
         break;
      case LT_SL_ATR:
         if(g_atr > 0.0)
           {
            sl = (dir > 0) ? entry - g_atr * InpSLATRMult : entry + g_atr * InpSLATRMult;
            break;
           }
      // no ATR yet: fall back to fixed points
      default:
         sl = (dir > 0) ? entry - Pts(InpSLFixedPoints) : entry + Pts(InpSLFixedPoints);
         break;
     }
   // a stop that would sit on the wrong side of the entry is pushed to the fixed distance
   if((dir > 0 && sl >= entry) || (dir < 0 && sl <= entry))
      sl = (dir > 0) ? entry - Pts(InpSLFixedPoints) : entry + Pts(InpSLFixedPoints);
   double minSL = Pts(InpMinSLPoints);
   if(minSL > 0.0 && MathAbs(entry - sl) < minSL)
      sl = (dir > 0) ? entry - minSL : entry + minSL;
   return(RoundToTick(sl));
  }

// nearest level beyond the entry in the trade direction (0 when none)
double NextLevelPrice(const int dir, const double entry, const string skipKey)
  {
   double best = 0.0;
   double minDist = Pts(InpTPMinPoints) + Pts(InpTPLevelBufferPoints);
   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      if(g_levels[i].key == skipKey)
         continue;
      double p = g_levels[i].price;
      if(dir > 0)
        {
         if(p - entry < minDist)
            continue;
         if(best == 0.0 || p < best)
            best = p;
        }
      else
        {
         if(entry - p < minDist)
            continue;
         if(best == 0.0 || p > best)
            best = p;
        }
     }
   return(best);
  }

// returns the take-profit (0 = none); skip = true when the trade should not be taken at all
double ComputeTP(const int dir, const double entry, const double sl, const SLevel &L, bool &skip, string &why)
  {
   skip = false;
   double risk = MathAbs(entry - sl);
   double tp = 0.0;
   double rTarget = (InpTPRR > 0.0) ? ((dir > 0) ? entry + risk * InpTPRR : entry - risk * InpTPRR) : 0.0;
   switch(InpTPMode)
     {
      case LT_TP_NONE:
         return(0.0);
      case LT_TP_FIXED_POINTS:
         tp = (dir > 0) ? entry + Pts(InpTPFixedPoints) : entry - Pts(InpTPFixedPoints);
         break;
      case LT_TP_RR:
         tp = rTarget;
         break;
      case LT_TP_NEXT_LEVEL:
        {
         double nxt = NextLevelPrice(dir, entry, L.key);
         if(nxt <= 0.0)
           {
            if(InpTPLowRRAction == LT_LOWRR_SKIP)
              {
               skip = true;
               why = "no level to target";
               return(0.0);
              }
            tp = rTarget;
            break;
           }
         tp = (dir > 0) ? nxt - Pts(InpTPLevelBufferPoints) : nxt + Pts(InpTPLevelBufferPoints);
         double rr = (risk > 0.0) ? MathAbs(tp - entry) / risk : 0.0;
         if(InpTPMinRR > 0.0 && rr < InpTPMinRR)
           {
            if(InpTPLowRRAction == LT_LOWRR_SKIP)
              {
               skip = true;
               why = "next level only " + DoubleToString(rr, 2) + "R away";
               return(0.0);
              }
            tp = rTarget;
           }
         else if(InpTPMaxRR > 0.0 && rr > InpTPMaxRR)
            tp = (dir > 0) ? entry + risk * InpTPMaxRR : entry - risk * InpTPMaxRR;
         break;
        }
     }
   if(tp <= 0.0)
      return(0.0);
   return(RoundToTick(tp));
  }

double NormalizeLots(double lots)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = minLot;
   if(step <= 0.0)
      step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   if(maxLot > 0.0 && lots > maxLot)
      lots = maxLot;
   return(NormalizeDouble(lots, 8));
  }

double ComputeLots(const double entry, const double sl)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lots = 0.0;
   if(InpLotMode == LT_LOT_FIXED)
      lots = InpFixedLot;
   else
     {
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickValue <= 0.0)
         tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double slDist = MathAbs(entry - sl);
      if(tickValue <= 0.0 || g_tickSize <= 0.0 || slDist <= 0.0)
        {
         LTLog(0, "cannot size the position (tick value / stop distance unknown)");
         return(0.0);
        }
      double lossPerLot = slDist / g_tickSize * tickValue;
      double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
      lots = riskMoney / lossPerLot;
     }
   lots = NormalizeLots(lots);
   if(lots < minLot)
     {
      if(InpLotMode == LT_LOT_RISK_PERCENT && !InpAllowMinLotOverRisk)
        {
         LTLog(1, "risk lot " + DoubleToString(lots, 2) + " is below the minimum lot - trade skipped "
               + "(set InpAllowMinLotOverRisk=true to trade the minimum lot)");
         return(0.0);
        }
      lots = minLot;
     }
   // broker-wide volume limit per symbol
   double limit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   if(limit > 0.0)
     {
      double open = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
         if(PositionGetTicket(i) != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
            open += PositionGetDouble(POSITION_VOLUME);
      for(int i = OrdersTotal() - 1; i >= 0; i--)
         if(OrderGetTicket(i) != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol)
            open += OrderGetDouble(ORDER_VOLUME_CURRENT);
      if(open + lots > limit)
        {
         LTLog(1, "symbol volume limit reached - trade skipped");
         return(0.0);
        }
     }
   return(lots);
  }

bool MarginOK(const int dir, const double lots, const double price)
  {
   double margin = 0.0;
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(type, _Symbol, lots, price, margin))
      return(true);                                  // cannot check: let the server decide
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin > freeMargin)
     {
      LTLog(1, "insufficient free margin (" + DoubleToString(freeMargin, 2) + " < "
            + DoubleToString(margin, 2) + ") - trade skipped");
      return(false);
     }
   return(true);
  }

// SL / TP must respect the broker's minimum distance from the reference price
void EnforceStopDistances(const int dir, const double refPrice, double &sl, double &tp)
  {
   double minDist = MinStopDistance();
   if(dir > 0)
     {
      if(sl > 0.0 && refPrice - sl < minDist)
         sl = RoundToTick(refPrice - minDist);
      if(tp > 0.0 && tp - refPrice < minDist)
         tp = RoundToTick(refPrice + minDist);
     }
   else
     {
      if(sl > 0.0 && sl - refPrice < minDist)
         sl = RoundToTick(refPrice + minDist);
      if(tp > 0.0 && refPrice - tp < minDist)
         tp = RoundToTick(refPrice - minDist);
     }
  }

//+------------------------------------------------------------------+
//| Markers, alerts                                                  |
//+------------------------------------------------------------------+
void DrawMarker(const int dir, const double price, const string text, const ulong ticket)
  {
   if(!InpDrawMarkers || (g_isTester && !g_isVisual))
      return;
   string name = LT_MARK_PREFIX + IntegerToString((long)ticket);
   datetime t = iTime(_Symbol, _Period, 0);
   if(!ObjectCreate(0, name, (dir > 0) ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0, t, price))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, (dir > 0) ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, text);
  }

void Notify(const string msg)
  {
   LTLog(1, msg);
   if(g_isTester)
      return;
   if(InpAlerts)
      Alert(LT_NAME, " ", _Symbol, ": ", msg);
   if(InpPushNotifications)
     {
      string txt = LT_NAME;
      txt += " " + _Symbol + ": " + msg;
      SendNotification(txt);
     }
  }

//+------------------------------------------------------------------+
//| Market entry                                                     |
//+------------------------------------------------------------------+
void BlockSignal(SLevel &L, const string why)
  {
   g_lastBlock = L.label + ": " + why;
   LTLog(2, "signal on " + L.label + " skipped: " + why);
  }

// touchBar = bar whose range the momentum filter checks (0 intrabar, 1 bar-close logic)
bool TryOpen(SLevel &L, const int dir, const string reason, const int touchBar, const bool checkEntryDistance)
  {
   string why = "";
   if(!EntryAllowed(dir, L, true, touchBar, why))
     {
      BlockSignal(L, why);
      return(false);
     }
   double entry = (dir > 0) ? g_tick.ask : g_tick.bid;
   if(checkEntryDistance && InpMaxEntryDistanceATR > 0.0 && g_atr > 0.0
      && MathAbs(entry - L.price) > InpMaxEntryDistanceATR * g_atr)
     {
      BlockSignal(L, "entry too far from the level");
      return(false);
     }
   if(!EntrySpacingOK(dir, entry))
     {
      BlockSignal(L, "too close to an existing entry");
      return(false);
     }
   double sl = ComputeSL(dir, entry, L.price);
   double slDist = MathAbs(entry - sl);
   if(InpMaxSLPoints > 0 && slDist > Pts(InpMaxSLPoints))
     {
      BlockSignal(L, "stop " + DoubleToString(slDist / g_point, 0) + " pts > max " + IntegerToString(InpMaxSLPoints));
      return(false);
     }
   if(InpMaxSpreadPercentOfSL > 0.0 && slDist > 0.0
      && SpreadPoints() * g_point > slDist * InpMaxSpreadPercentOfSL / 100.0)
     {
      BlockSignal(L, "spread too large for the stop distance");
      return(false);
     }
   bool skip = false;
   double tp = ComputeTP(dir, entry, sl, L, skip, why);
   if(skip)
     {
      BlockSignal(L, why);
      return(false);
     }
   EnforceStopDistances(dir, (dir > 0) ? g_tick.bid : g_tick.ask, sl, tp);
   double lots = ComputeLots(entry, sl);
   if(lots <= 0.0)
     {
      BlockSignal(L, "lot size");
      return(false);
     }
   string side = (dir > 0) ? "BUY" : "SELL";
   if(InpTradeMode == LT_MODE_SIGNAL_ONLY)
     {
      g_signalSeq++;
      L.lastSignalTime = SignalBarTime(0);
      L.needReset = true;
      L.trades++;
      g_signalsThisBar++;
      g_stateDirty = true;
      DrawMarker(dir, entry, L.label + " " + reason + " (signal only)", g_signalSeq);
      Notify("SIGNAL ONLY: " + side + " " + DoubleToString(lots, 2) + " @ " + PriceStr(entry) + " level " + L.label
             + " " + PriceStr(L.price) + " (" + reason + ") SL " + PriceStr(sl) + " TP " + (tp > 0.0 ? PriceStr(tp) : "none"));
      return(true);
     }
   if(!MarginOK(dir, lots, entry))
     {
      BlockSignal(L, "margin");
      return(false);
     }
   int buys = 0, sells = 0;
   CountPositions(buys, sells);
   int opposite = (dir > 0) ? sells : buys;
   if(opposite > 0 && InpOppositeMode == LT_OPP_CLOSE_FIRST)
     {
      if(!CloseOppositePositions(dir))
         return(false);
      if(!UpdateMarket())
         return(false);
      entry = (dir > 0) ? g_tick.ask : g_tick.bid;
     }
   string comment = LevelComment(L.key);
   bool sent = (dir > 0) ? g_trade.Buy(lots, _Symbol, 0.0, sl, tp, comment)
               : g_trade.Sell(lots, _Symbol, 0.0, sl, tp, comment);
   uint rc = g_trade.ResultRetcode();
   if(!sent || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL))
     {
      LTLog(0, side + " on " + L.label + " failed: " + IntegerToString((int)rc)
            + " " + g_trade.ResultRetcodeDescription());
      g_lastBlock = L.label + ": order rejected " + IntegerToString((int)rc);
      return(false);
     }
   ulong ticket = g_trade.ResultOrder();
   if(ticket != 0)
      LinkTicket(ticket, L.key);
   if(g_trade.ResultDeal() != 0)
      LinkTicket(g_trade.ResultDeal(), L.key);
   double fill = (g_trade.ResultPrice() > 0.0) ? g_trade.ResultPrice() : entry;
   L.lastSignalTime = SignalBarTime(0);
   L.needReset = true;
   L.trades++;
   g_signalsThisBar++;
   g_dayTrades++;
   g_stateDirty = true;
   DrawMarker(dir, fill, L.label + " " + reason, ticket);
   Notify(side + " " + DoubleToString(lots, 2) + " @ " + PriceStr(fill)
          + " level " + L.label + " " + PriceStr(L.price) + " (" + reason + ") SL " + PriceStr(sl)
          + " TP " + (tp > 0.0 ? PriceStr(tp) : "none"));
   return(true);
  }

//+------------------------------------------------------------------+
//| Level roles and arming                                           |
//+------------------------------------------------------------------+
bool LevelArmed(const SLevel &L)
  {
   if(L.targetOnly || L.role == 0 || L.needReset)
      return(false);
   if(InpMaxTradesPerLevel > 0 && L.trades >= InpMaxTradesPerLevel)
      return(false);
   if(InpCooldownBars > 0 && BarsSince(L.lastSignalTime) < InpCooldownBars)
      return(false);
   if(InpChopMaxFlips > 0 && L.flipCount >= InpChopMaxFlips && BarsSince(L.lastFlipTime) < InpChopWindowBars)
      return(false);
   if(InpMaxLossesPerLevelDay > 0 && LevelLossesToday(L) >= InpMaxLossesPerLevelDay)
      return(false);
   return(true);
  }

void RegisterFlip(SLevel &L, const int newRole)
  {
   datetime now = SignalBarTime(0);
   if(L.flipWindowStart == 0 || BarsSince(L.flipWindowStart) >= InpChopWindowBars)
     {
      L.flipWindowStart = now;
      L.flipCount = 0;
     }
   L.flipCount++;
   L.lastFlipTime = now;
   L.lastSignalTime = now;                          // a flip starts the cooldown
   L.role = newRole;
   L.pendingRoleCount = 0;
   L.inTouch = false;
   g_stateDirty = true;
   LTLog(2, "level " + L.label + " " + PriceStr(L.price) + " is now " + (newRole > 0 ? "support" : "resistance"));
  }

// roles come from completed closes only: a level is support while closes stay above it;
// it flips after InpRoleConfirmBars consecutive closes beyond the break buffer on the other side
void UpdateLevelRoles(const double closePrice)
  {
   if(closePrice <= 0.0)
      return;
   double buf = BreakBuffer();
   int confirm = MathMax(InpRoleConfirmBars, 1);
   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      double d = closePrice - g_levels[i].prevPrice;
      int side = (d > buf) ? 1 : ((d < -buf) ? -1 : 0);
      if(side == 0)
        {
         g_levels[i].pendingRoleCount = 0;
         continue;
        }
      if(g_levels[i].role == 0)
        {
         g_levels[i].role = side;
         g_levels[i].pendingRoleCount = 0;
         g_stateDirty = true;
         continue;
        }
      if(side == g_levels[i].role)
        {
         g_levels[i].pendingRoleCount = 0;
         continue;
        }
      if(g_levels[i].pendingRole != side)
        {
         g_levels[i].pendingRole = side;
         g_levels[i].pendingRoleCount = 0;
        }
      g_levels[i].pendingRoleCount++;
      if(g_levels[i].pendingRoleCount >= confirm)
         RegisterFlip(g_levels[i], side);
     }
  }

// per tick: which side of the zone price last was on, touch episodes, re-arming
void UpdateLevelTicks(const double bid)
  {
   double rearm = g_zone + RearmDistance();
   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      double d = bid - g_levels[i].price;
      if(d > g_zone)
        {
         g_levels[i].lastSide = 1;
         g_levels[i].inTouch = false;
        }
      else if(d < -g_zone)
        {
         g_levels[i].lastSide = -1;
         g_levels[i].inTouch = false;
        }
      if(g_levels[i].needReset && MathAbs(d) > rearm)
        {
         g_levels[i].needReset = false;
         g_stateDirty = true;
        }
     }
  }

//+------------------------------------------------------------------+
//| Signal detection                                                 |
//+------------------------------------------------------------------+
void CheckTouchSignals()
  {
   if(InpOneSignalPerBar && g_signalsThisBar > 0)
      return;
   double bid = g_tick.bid;
   double breakBuf = BreakBuffer();
   double maxPen = (InpMaxPenetrationATR > 0.0 && g_atr > 0.0) ? InpMaxPenetrationATR * g_atr : 0.0;
   double retreatNeeded = g_zone * MathMax(InpTouchRetreatPercent, 0) / 100.0;
   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      double lv = g_levels[i].price;
      double d  = bid - lv;
      int dir = 0;
      string reason = "";
      if(InpDirectionMode == LT_DIR_BOUNCE)
        {
         if(MathAbs(d) > g_zone)
            continue;                                // outside the zone: no touch
         if(g_levels[i].role == 0 || g_levels[i].lastSide != g_levels[i].role)
            continue;                                // price must arrive from the role's side
         if(!g_levels[i].inTouch)
           {
            g_levels[i].inTouch = true;
            g_levels[i].touchExtreme = bid;
           }
         else if((g_levels[i].role > 0 && bid < g_levels[i].touchExtreme)
                 || (g_levels[i].role < 0 && bid > g_levels[i].touchExtreme))
            g_levels[i].touchExtreme = bid;
         if(!LevelArmed(g_levels[i]))
            continue;
         if(maxPen > 0.0 && ((g_levels[i].role > 0 && g_levels[i].touchExtreme < lv - maxPen)
                             || (g_levels[i].role < 0 && g_levels[i].touchExtreme > lv + maxPen)))
            continue;                                // pierced too deep: not a touch
         double retreat = (g_levels[i].role > 0) ? bid - g_levels[i].touchExtreme : g_levels[i].touchExtreme - bid;
         if(retreat < retreatNeeded)
            continue;                                // wait for price to turn away from the level
         dir = (g_levels[i].role > 0) ? 1 : -1;
         reason = "touch";
        }
      else
        {
         if(!LevelArmed(g_levels[i]))
            continue;
         if(g_levels[i].lastSide != g_levels[i].role)
            continue;                                // price must have been on the role's side before the break
         double maxBreak = breakBuf + ((InpMaxEntryDistanceATR > 0.0 && g_atr > 0.0) ? InpMaxEntryDistanceATR * g_atr : breakBuf);
         if(g_levels[i].role > 0 && bid < lv - breakBuf && bid >= lv - maxBreak)
            dir = -1;
         else if(g_levels[i].role < 0 && bid > lv + breakBuf && bid <= lv + maxBreak)
            dir = 1;
         if(dir == 0)
            continue;
         reason = "break";
        }
      if(TryOpen(g_levels[i], dir, reason, 0, false))
        {
         if(InpOneSignalPerBar)
            return;
        }
      else
        {
         // the touch happened but could not be traded: do not retry on every tick
         g_levels[i].needReset = true;
         g_levels[i].lastSignalTime = SignalBarTime(0);
         g_stateDirty = true;
        }
     }
  }

// called once per new signal bar; bar 1 has just closed
void CheckBarSignals()
  {
   if(InpOneSignalPerBar && g_signalsThisBar > 0)
      return;
   double o1 = iOpen(_Symbol, g_sigTF, 1);
   double h1 = iHigh(_Symbol, g_sigTF, 1);
   double l1 = iLow(_Symbol, g_sigTF, 1);
   double c1 = iClose(_Symbol, g_sigTF, 1);
   if(o1 <= 0.0 || h1 <= 0.0 || l1 <= 0.0 || c1 <= 0.0)
      return;
   double range = h1 - l1;
   double breakBuf = BreakBuffer();
   double maxPen = (InpMaxPenetrationATR > 0.0 && g_atr > 0.0) ? InpMaxPenetrationATR * g_atr : 0.0;
   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      if(!LevelArmed(g_levels[i]))
         continue;
      double lv = g_levels[i].prevPrice;        // level value on the bar that just closed
      int dir = 0;
      string reason = "";
      if(InpDirectionMode == LT_DIR_BOUNCE)
        {
         if(g_levels[i].role > 0 && l1 <= lv + g_zone && c1 > lv && (maxPen <= 0.0 || l1 >= lv - maxPen))
           {
            double ratio = (range > 0.0) ? (c1 - l1) / range : 1.0;
            if(ratio >= InpMinRejectionRatio)
               dir = 1;
           }
         else if(g_levels[i].role < 0 && h1 >= lv - g_zone && c1 < lv && (maxPen <= 0.0 || h1 <= lv + maxPen))
           {
            double ratio = (range > 0.0) ? (h1 - c1) / range : 1.0;
            if(ratio >= InpMinRejectionRatio)
               dir = -1;
           }
         reason = "rejection";
        }
      else
        {
         if(g_levels[i].role > 0 && c1 < lv - breakBuf)
            dir = -1;
         else if(g_levels[i].role < 0 && c1 > lv + breakBuf)
            dir = 1;
         reason = "break close";
        }
      if(dir == 0)
         continue;
      if(TryOpen(g_levels[i], dir, reason, 1, true))
        {
         if(InpOneSignalPerBar)
            return;
        }
      else
        {
         g_levels[i].needReset = true;
         g_levels[i].lastSignalTime = SignalBarTime(0);
         g_stateDirty = true;
        }
     }
  }

//+------------------------------------------------------------------+
//| Open-position management: break-even and trailing stop           |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   if(InpBreakEvenTriggerPoints <= 0 && InpTrailingStartPoints <= 0)
      return;
   double minDist = MinStopDistance();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition())
         continue;
      bool   isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double cur   = isBuy ? g_tick.bid : g_tick.ask;
      double profitPts = (isBuy ? (cur - open) : (open - cur)) / g_point;
      double newSL = sl;
      //--- break-even
      if(InpBreakEvenTriggerPoints > 0 && profitPts >= InpBreakEvenTriggerPoints)
        {
         double be = isBuy ? open + Pts(InpBreakEvenLockPoints) : open - Pts(InpBreakEvenLockPoints);
         if(isBuy ? (sl < be - g_point / 2.0) : (sl == 0.0 || sl > be + g_point / 2.0))
            newSL = be;
        }
      //--- trailing
      if(InpTrailingStartPoints > 0 && InpTrailingStopPoints > 0 && profitPts >= InpTrailingStartPoints)
        {
         double trail = isBuy ? cur - Pts(InpTrailingStopPoints) : cur + Pts(InpTrailingStopPoints);
         double step  = Pts(InpTrailingStepPoints);
         if(isBuy ? (trail - newSL >= step || newSL == 0.0) : (newSL == 0.0 || newSL - trail >= step))
            if(isBuy ? (trail > newSL) : (newSL == 0.0 || trail < newSL))
               newSL = trail;
        }
      if(newSL == sl || newSL == 0.0)
         continue;
      //--- broker distance and freeze level
      if(isBuy ? (cur - newSL < minDist) : (newSL - cur < minDist))
         continue;
      newSL = RoundToTick(newSL);
      if(MathAbs(newSL - sl) < g_point / 2.0)
         continue;
      if(!g_trade.PositionModify(ticket, newSL, tp))
         LTLog(0, "modify #" + IntegerToString((long)ticket) + " failed: " + g_trade.ResultRetcodeDescription());
      else
         LTLog(2, "position #" + IntegerToString((long)ticket) + " stop moved to " + PriceStr(newSL));
     }
  }

//+------------------------------------------------------------------+
//| Pending-order mode                                               |
//+------------------------------------------------------------------+
int DesiredPendingType(const SLevel &L)
  {
   if(!LevelArmed(L))
      return(-1);
   if(InpDirectionMode == LT_DIR_BOUNCE)
     {
      if(L.role > 0 && DirectionPermitted(1))
         return(ORDER_TYPE_BUY_LIMIT);
      if(L.role < 0 && DirectionPermitted(-1))
         return(ORDER_TYPE_SELL_LIMIT);
     }
   else
     {
      if(L.role > 0 && DirectionPermitted(-1))
         return(ORDER_TYPE_SELL_STOP);
      if(L.role < 0 && DirectionPermitted(1))
         return(ORDER_TYPE_BUY_STOP);
     }
   return(-1);
  }

int PendingDir(const int type)
  {
   return((type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP) ? 1 : -1);
  }

double PendingPrice(const SLevel &L, const int type)
  {
   double off = Pts(InpPendingOffsetPoints);
   return(RoundToTick(PendingDir(type) > 0 ? L.price + off : L.price - off));
  }

// can an order of this type be placed at this price right now?
bool PendingPriceValid(const int type, const double price)
  {
   double minDist = MathMax(MinStopDistance(), Pts(InpPendingMinDistancePoints));
   switch(type)
     {
      case ORDER_TYPE_BUY_LIMIT:  return(g_tick.ask - price >= minDist);
      case ORDER_TYPE_SELL_LIMIT: return(price - g_tick.bid >= minDist);
      case ORDER_TYPE_BUY_STOP:   return(price - g_tick.ask >= minDist);
      case ORDER_TYPE_SELL_STOP:  return(g_tick.bid - price >= minDist);
     }
   return(false);
  }

bool DeletePending(const ulong ticket, const string why)
  {
   if(InpTradeMode == LT_MODE_SIGNAL_ONLY)
      return(false);                                   // dry run: never touch real orders
   if(!g_trade.OrderDelete(ticket))
     {
      uint rc = g_trade.ResultRetcode();
      if(rc == TRADE_RETCODE_INVALID || rc == TRADE_RETCODE_REJECT || rc == TRADE_RETCODE_FROZEN)
         LTLog(0, "delete order #" + IntegerToString((long)ticket) + " failed: " + g_trade.ResultRetcodeDescription());
      return(false);
     }
   LTLog(1, "deleted order #" + IntegerToString((long)ticket) + " (" + why + ")");
   return(true);
  }

datetime PendingExpiration()
  {
   if(InpPendingExpiryBars <= 0 || !g_expirySupported)
      return(0);
   return(SignalBarTime(0) + (datetime)(InpPendingExpiryBars * PeriodSeconds(g_sigTF)));
  }

bool PlacePending(SLevel &L, const int type)
  {
   string why = "";
   int dir = PendingDir(type);
   if(!EntryAllowed(dir, L, false, 0, why))
     {
      BlockSignal(L, why);
      return(false);
     }
   if(InpPendingMaxDistanceATR > 0.0 && g_atr > 0.0
      && MathAbs(L.price - g_tick.bid) > InpPendingMaxDistanceATR * g_atr)
      return(false);                                 // too far away for now: try again later
   double price = PendingPrice(L, type);
   if(!PendingPriceValid(type, price))
      return(false);
   if(!EntrySpacingOK(dir, price))
      return(false);
   double sl = ComputeSL(dir, price, L.price);
   double slDist = MathAbs(price - sl);
   if(InpMaxSLPoints > 0 && slDist > Pts(InpMaxSLPoints))
     {
      BlockSignal(L, "stop wider than max");
      return(false);
     }
   if(InpMaxSpreadPercentOfSL > 0.0 && slDist > 0.0
      && SpreadPoints() * g_point > slDist * InpMaxSpreadPercentOfSL / 100.0)
      return(false);
   bool skip = false;
   double tp = ComputeTP(dir, price, sl, L, skip, why);
   if(skip)
     {
      BlockSignal(L, why);
      L.pendingBar = SignalBarTime(0);
      return(false);
     }
   EnforceStopDistances(dir, price, sl, tp);
   double lots = ComputeLots(price, sl);
   if(lots <= 0.0)
      return(false);
   if(InpTradeMode == LT_MODE_SIGNAL_ONLY)
     {
      L.pendingBar = SignalBarTime(0);
      Notify("SIGNAL ONLY: would place " + EnumToString((ENUM_ORDER_TYPE)type) + " " + DoubleToString(lots, 2)
             + " @ " + PriceStr(price) + " level " + L.label + " SL " + PriceStr(sl) + " TP " + (tp > 0.0 ? PriceStr(tp) : "none"));
      return(false);
     }
   if(!MarginOK(dir, lots, price))
      return(false);
   datetime expiry = PendingExpiration();
   ENUM_ORDER_TYPE_TIME tt = (expiry > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
   string comment = LevelComment(L.key);
   bool sent = false;
   switch(type)
     {
      case ORDER_TYPE_BUY_LIMIT:  sent = g_trade.BuyLimit(lots, price, _Symbol, sl, tp, tt, expiry, comment);  break;
      case ORDER_TYPE_SELL_LIMIT: sent = g_trade.SellLimit(lots, price, _Symbol, sl, tp, tt, expiry, comment); break;
      case ORDER_TYPE_BUY_STOP:   sent = g_trade.BuyStop(lots, price, _Symbol, sl, tp, tt, expiry, comment);   break;
      case ORDER_TYPE_SELL_STOP:  sent = g_trade.SellStop(lots, price, _Symbol, sl, tp, tt, expiry, comment);  break;
     }
   uint rc = g_trade.ResultRetcode();
   if(!sent || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED))
     {
      LTLog(0, "pending order on " + L.label + " failed: " + IntegerToString((int)rc) + " "
            + g_trade.ResultRetcodeDescription());
      L.pendingBar = SignalBarTime(0);               // do not hammer the server: retry next bar
      return(false);
     }
   L.pendingTicket = g_trade.ResultOrder();
   L.pendingType   = type;
   L.pendingBar    = SignalBarTime(0);
   LinkTicket(L.pendingTicket, L.key);
   Notify("placed " + EnumToString((ENUM_ORDER_TYPE)type) + " " + DoubleToString(lots, 2) + " @ " + PriceStr(price)
          + " level " + L.label + " SL " + PriceStr(sl) + " TP " + (tp > 0.0 ? PriceStr(tp) : "none"));
   return(true);
  }

// re-price a resting order when the level moved (sloped lines, dragged lines)
void UpdatePending(SLevel &L)
  {
   if(InpTradeMode == LT_MODE_SIGNAL_ONLY)
      return;
   if(!OrderSelect(L.pendingTicket))
      return;
   int    type  = (int)OrderGetInteger(ORDER_TYPE);
   int    dir   = PendingDir(type);
   double price = PendingPrice(L, type);
   double cur   = OrderGetDouble(ORDER_PRICE_OPEN);
   if(MathAbs(price - cur) < g_point / 2.0)
      return;
   if(!PendingPriceValid(type, price))
      return;                                        // price moved onto the level: leave the order
   double freeze = MathMax((double)g_freezeLevel, (double)g_stopsLevel) * g_point;
   double mkt = (dir > 0) ? g_tick.ask : g_tick.bid;
   if(MathAbs(cur - mkt) <= freeze)
      return;                                        // inside the freeze zone: cannot modify
   double sl = ComputeSL(dir, price, L.price);
   bool skip = false;
   string why = "";
   double tp = ComputeTP(dir, price, sl, L, skip, why);
   if(skip)
      tp = OrderGetDouble(ORDER_TP);                  // keep the old target rather than cancelling here
   EnforceStopDistances(dir, price, sl, tp);
   ENUM_ORDER_TYPE_TIME tt = (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
   datetime expiry = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
   if(!g_trade.OrderModify(L.pendingTicket, price, sl, tp, tt, expiry))
      LTLog(2, "modify order #" + IntegerToString((long)L.pendingTicket) + " failed: " + g_trade.ResultRetcodeDescription());
   else
      LTLog(2, "order #" + IntegerToString((long)L.pendingTicket) + " moved to " + PriceStr(price));
  }

// the level's order is no longer among the pending orders: filled, expired or deleted
void OnPendingGone(SLevel &L)
  {
   bool filled = false;
   if(HistoryOrderSelect(L.pendingTicket))
      filled = ((ENUM_ORDER_STATE)HistoryOrderGetInteger(L.pendingTicket, ORDER_STATE) == ORDER_STATE_FILLED);
   if(filled)
     {
      L.trades++;
      L.lastSignalTime = SignalBarTime(0);
      L.needReset = true;
      g_signalsThisBar++;
      g_dayTrades++;
      g_stateDirty = true;
      Notify("order #" + IntegerToString((long)L.pendingTicket) + " on " + L.label + " filled");
     }
   else
     {
      L.needReset = true;                              // expired or deleted: the level must re-arm first
      L.lastSignalTime = SignalBarTime(0);
      L.pendingBar = SignalBarTime(0);
      g_stateDirty = true;
     }
   L.pendingTicket = 0;
   L.pendingType   = -1;
  }

void MaintainPendingOrders(const bool newBar)
  {
   //--- claim orders by link or comment hash (also after a restart)
   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      if(g_levels[i].pendingTicket != 0)
        {
         if(OrderSelect(g_levels[i].pendingTicket))
            continue;
         OnPendingGone(g_levels[i]);
        }
      for(int o = OrdersTotal() - 1; o >= 0; o--)
        {
         ulong ticket = OrderGetTicket(o);
         if(ticket == 0 || !IsOurOrder())
            continue;
         string lk = LinkedKey(ticket);
         bool mine = (lk != "" && (lk == g_levels[i].key || StringFind(g_levels[i].members, lk + ";") >= 0))
                     || CommentMatchesLevel(OrderGetString(ORDER_COMMENT), g_levels[i]);
         if(!mine)
            continue;
         g_levels[i].pendingTicket = ticket;
         g_levels[i].pendingType   = (int)OrderGetInteger(ORDER_TYPE);
         if(g_levels[i].pendingBar == 0)
            g_levels[i].pendingBar = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         LinkTicket(ticket, g_levels[i].key);
         break;
        }
     }
   //--- orphans and manual expiry (never while a level source is still warming up)
   bool sourcesReady = g_valReady;
   for(int j = 0; j < ArraySize(g_eng); j++)
      if(!g_eng[j].ready)
         sourcesReady = false;
   for(int o = OrdersTotal() - 1; o >= 0; o--)
     {
      ulong ticket = OrderGetTicket(o);
      if(ticket == 0 || !IsOurOrder())
         continue;
      bool claimed = false;
      for(int i = 0; i < ArraySize(g_levels) && !claimed; i++)
         if(g_levels[i].pendingTicket == ticket)
            claimed = true;
      if(!claimed)
        {
         if(InpPendingDeleteOrphans && sourcesReady)
            DeletePending(ticket, "no matching level");
         continue;
        }
      if(InpPendingExpiryBars > 0 && !g_expirySupported)
        {
         datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         if(BarsSince(setup) >= InpPendingExpiryBars && DeletePending(ticket, "expired"))
            for(int i = 0; i < ArraySize(g_levels); i++)
               if(g_levels[i].pendingTicket == ticket)
                 {
                  g_levels[i].pendingTicket = 0;
                  g_levels[i].pendingType   = -1;
                  g_levels[i].needReset     = true;
                  g_levels[i].lastSignalTime = SignalBarTime(0);
                  g_levels[i].pendingBar    = SignalBarTime(0);
                  g_stateDirty = true;
                 }
        }
     }
   //--- position caps: no resting orders while the cap is reached
   int buys = 0, sells = 0;
   CountPositions(buys, sells);
   bool capReached = (buys + sells >= InpMaxOpenPositions) || g_dayStopped
                     || (InpMaxTradesPerDay > 0 && g_dayTrades >= InpMaxTradesPerDay);
   //--- per level: delete, update or place
   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      int desired = DesiredPendingType(g_levels[i]);
      bool hasOrder = (g_levels[i].pendingTicket != 0 && OrderSelect(g_levels[i].pendingTicket));
      if(hasOrder)
        {
         int type = (int)OrderGetInteger(ORDER_TYPE);
         string conflict = "";
         bool wrong = (desired < 0) || (type != desired) || capReached
                      || OppositeConflict(PendingDir(type), buys, sells, false, conflict)
                      || (InpMaxPositionsPerLevel > 0 && CountLevelPositions(g_levels[i]) >= InpMaxPositionsPerLevel);
         if(wrong)
           {
            if(DeletePending(g_levels[i].pendingTicket, capReached ? "position cap" : "level state changed"))
              {
               g_levels[i].pendingTicket = 0;
               g_levels[i].pendingType   = -1;
              }
            continue;
           }
         if(newBar || g_levels[i].kind == 0)
            UpdatePending(g_levels[i]);
         continue;
        }
      if(desired < 0 || capReached)
         continue;
      if(g_levels[i].pendingBar == SignalBarTime(0))
         continue;                                   // one placement attempt per bar per level
      PlacePending(g_levels[i], desired);
     }
  }

// after a restart: link open positions to their levels by comment hash
void RelinkPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition())
         continue;
      if(LinkedKey(ticket) != "")
         continue;
      string comment = PositionGetString(POSITION_COMMENT);
      for(int k = 0; k < ArraySize(g_levels); k++)
         if(CommentMatchesLevel(comment, g_levels[k]))
           {
            LinkTicket(ticket, g_levels[k].key);
            break;
           }
     }
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
string EntryModeName()
  {
   switch(InpEntryMode)
     {
      case LT_ENTRY_TOUCH:         return("Touch");
      case LT_ENTRY_CONFIRM_CLOSE: return("Confirm close");
      case LT_ENTRY_PENDING:       return("Pending");
     }
   return("?");
  }

string SourceName(const int source)
  {
   switch(source)
     {
      case LT_SRC_OBJECT:    return("chart");
      case LT_SRC_VAL:       return("VAL");
      case LT_SRC_ENGINE_SR: return("zz S/R");
      case LT_SRC_ENGINE_TL: return("zz TL");
      case LT_SRC_MANUAL:    return("manual");
     }
   return("?");
  }

string LevelStateName(const SLevel &L)
  {
   if(L.targetOnly)
      return("target only");
   if(L.role == 0)
      return("wait side");
   if(InpMaxTradesPerLevel > 0 && L.trades >= InpMaxTradesPerLevel)
      return("done");
   if(InpMaxLossesPerLevelDay > 0 && LevelLossesToday(L) >= InpMaxLossesPerLevelDay)
      return("lost today");
   if(InpChopMaxFlips > 0 && L.flipCount >= InpChopMaxFlips && BarsSince(L.lastFlipTime) < InpChopWindowBars)
      return("chop");
   if(L.needReset)
      return("used");
   if(InpCooldownBars > 0 && BarsSince(L.lastSignalTime) < InpCooldownBars)
      return("cooldown");
   if(L.pendingTicket != 0)
      return("order #" + IntegerToString((long)L.pendingTicket));
   if(L.inTouch)
      return("touching");
   return("ARMED");
  }

string GradeName(const int grade)
  {
   if(grade <= LT_GRADE_A)
      return("A");
   if(grade == LT_GRADE_B)
      return("B");
   return("C");
  }

void UpdateDashboard()
  {
   if(!InpShowDashboard || (g_isTester && !g_isVisual))
      return;
   datetime now = TimeCurrent();
   if(now == g_lastDashboard)
      return;
   g_lastDashboard = now;
   int buys = 0, sells = 0;
   CountPositions(buys, sells);
   string why = "";
   bool allowed = TradingAllowed(why);
   string s = LT_NAME;
   s += "  " + _Symbol + " " + TFToString(_Period) + "   signals: " + TFToString(g_sigTF) + "\n";
   s += "Mode: " + EntryModeName() + " / " + (InpDirectionMode == LT_DIR_BOUNCE ? "Bounce" : "Breakout")
        + (InpTradeMode == LT_MODE_SIGNAL_ONLY ? "   *** SIGNAL ONLY ***" : "")
        + "   zone: " + DoubleToString(g_zone / g_point, 0) + " pts   spread: " + IntegerToString(SpreadPoints())
        + "   ATR: " + (g_atr > 0.0 ? DoubleToString(g_atr / g_point, 0) : "-") + " pts\n";
   s += "Trading: " + (allowed ? "allowed" : ("BLOCKED - " + why))
        + (g_dayStopped ? "   STOPPED FOR THE DAY" : "") + "\n";
   if(g_lastBlock != "")
      s += "Last skipped signal: " + g_lastBlock + "\n";
   s += "Positions: " + IntegerToString(buys + sells) + " (B " + IntegerToString(buys) + " / S " + IntegerToString(sells)
        + ")   pending: " + IntegerToString(CountPendingOrders())
        + "   today: " + IntegerToString(g_dayTrades) + " trades, P/L "
        + DoubleToString(g_dayRealized, 2) + " closed / " + DoubleToString(g_dayFloating, 2) + " open\n";
   int n = ArraySize(g_levels);
   s += "Levels: " + IntegerToString(n) + "\n";
   //--- nearest levels first
   int idx[];
   double dist[];
   ArrayResize(idx, n);
   ArrayResize(dist, n);
   for(int i = 0; i < n; i++)
     {
      idx[i] = i;
      dist[i] = MathAbs(g_levels[i].price - g_tick.bid);
     }
   for(int i = 1; i < n; i++)
     {
      int    ti = idx[i];
      double td = dist[i];
      int j = i - 1;
      while(j >= 0 && dist[j] > td)
        {
         idx[j + 1] = idx[j];
         dist[j + 1] = dist[j];
         j--;
        }
      idx[j + 1] = ti;
      dist[j + 1] = td;
     }
   int shown = MathMin(n, MathMax(InpDashboardLevels, 1));
   for(int k = 0; k < shown; k++)
     {
      int i = idx[k];
      double d = (g_levels[i].price - g_tick.bid) / g_point;
      string roleTxt = (g_levels[i].role > 0) ? "S" : ((g_levels[i].role < 0) ? "R" : "?");
      string lbl = g_levels[i].label;
      if(StringLen(lbl) > 24)
         lbl = StringSubstr(lbl, 0, 24);
      s += "  " + PriceStr(g_levels[i].price) + "  " + roleTxt + " " + GradeName(g_levels[i].grade) + "  "
           + (d >= 0 ? "+" : "") + DoubleToString(d, 0) + " pts  " + LevelStateName(g_levels[i])
           + "  [" + SourceName(g_levels[i].source) + "] " + lbl + "\n";
     }
   Comment(s);
  }

//+------------------------------------------------------------------+
//| Input validation                                                 |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   bool ok = true;
   if(InpTouchZonePoints <= 0)
     {
      LTLog(0, "InpTouchZonePoints must be > 0");
      ok = false;
     }
   if(InpMinRejectionRatio < 0.0 || InpMinRejectionRatio > 1.0)
     {
      LTLog(0, "InpMinRejectionRatio must be between 0 and 1");
      ok = false;
     }
   if(InpLotMode == LT_LOT_FIXED && InpFixedLot <= 0.0)
     {
      LTLog(0, "InpFixedLot must be > 0");
      ok = false;
     }
   if(InpLotMode == LT_LOT_RISK_PERCENT && (InpRiskPercent <= 0.0 || InpRiskPercent > 50.0))
     {
      LTLog(0, "InpRiskPercent must be between 0 and 50");
      ok = false;
     }
   if(InpSLMode == LT_SL_FIXED_POINTS && InpSLFixedPoints <= 0)
     {
      LTLog(0, "InpSLFixedPoints must be > 0");
      ok = false;
     }
   if(InpSLMode == LT_SL_BEYOND_LEVEL && InpSLBufferPoints < 0)
     {
      LTLog(0, "InpSLBufferPoints must be >= 0");
      ok = false;
     }
   if(InpSLMode == LT_SL_ATR && InpSLATRMult <= 0.0)
     {
      LTLog(0, "InpSLATRMult must be > 0");
      ok = false;
     }
   if(InpSLFixedPoints <= 0)
     {
      LTLog(0, "InpSLFixedPoints must be > 0 (it is the fallback stop distance)");
      ok = false;
     }
   if(InpTPMode == LT_TP_FIXED_POINTS && InpTPFixedPoints <= 0)
     {
      LTLog(0, "InpTPFixedPoints must be > 0");
      ok = false;
     }
   if(InpMaxOpenPositions <= 0)
     {
      LTLog(0, "InpMaxOpenPositions must be > 0");
      ok = false;
     }
   if(InpATRPeriod <= 0)
     {
      LTLog(0, "InpATRPeriod must be > 0");
      ok = false;
     }
   if(InpTouchRetreatPercent < 0 || InpTouchRetreatPercent > 90)
     {
      LTLog(0, "InpTouchRetreatPercent must be between 0 and 90");
      ok = false;
     }
   if(InpRoleConfirmBars <= 0 || InpChopWindowBars <= 0)
     {
      LTLog(0, "InpRoleConfirmBars and InpChopWindowBars must be > 0");
      ok = false;
     }
   if(InpMergeDistancePoints > InpTouchZonePoints)
     {
      LTLog(0, "InpMergeDistancePoints should not exceed InpTouchZonePoints");
      ok = false;
     }
   if(InpRolloverSkipMinutes < 0 || InpRolloverSkipMinutes > 180)
     {
      LTLog(0, "InpRolloverSkipMinutes must be between 0 and 180");
      ok = false;
     }
   if(InpUseADXFilter && InpADXPeriod <= 0)
     {
      LTLog(0, "InpADXPeriod must be > 0");
      ok = false;
     }
   if(InpMagic == 0)
     {
      LTLog(0, "InpMagic must not be 0");
      ok = false;
     }
   if(InpUseTimeFilter && (InpStartHour < 0 || InpStartHour > 23 || InpEndHour < 0 || InpEndHour > 24))
     {
      LTLog(0, "trading hours must be 0..23 (start) and 0..24 (end)");
      ok = false;
     }
   if(InpSR_Enable && (InpSR_Depth <= 0 || InpSR_Backstep < 0 || InpSR_Backstep >= InpSR_Depth
                       || InpTL_Depth <= 0 || InpTL_Backstep < 0 || InpTL_Backstep >= InpTL_Depth))
     {
      LTLog(0, "ZigZag depth must be > 0 and backstep must be smaller than depth");
      ok = false;
     }
   if(InpSR_Enable && InpSR_MaxPerTF <= 0)
     {
      LTLog(0, "InpSR_MaxPerTF must be > 0");
      ok = false;
     }
   if(InpEntryMode == LT_ENTRY_PENDING)
     {
      long orderMode = SymbolInfoInteger(_Symbol, SYMBOL_ORDER_MODE);
      long need = (InpDirectionMode == LT_DIR_BOUNCE) ? SYMBOL_ORDER_LIMIT : SYMBOL_ORDER_STOP;
      if((orderMode & need) == 0)
        {
         LTLog(0, "the symbol does not allow the pending order type required by this mode");
         ok = false;
        }
     }
   if(!InpObjUseHLines && !InpObjUseTrendLines && !InpVAL_Enable && !InpSR_Enable
      && InpManualLevels == "" && InpManualTrendLines == "")
      LTLog(0, "warning: every level source is disabled - the EA will not trade");
   return(ok);
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_point     = _Point;
   g_digits    = _Digits;
   g_tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_sigTF     = (InpSignalTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpSignalTF;
   g_isTester  = (MQLInfoInteger(MQL_TESTER) != 0);
   g_isVisual  = (MQLInfoInteger(MQL_VISUAL_MODE) != 0);
   g_hedging   = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   g_expirySupported = ((SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_SPECIFIED) != 0);
   if(g_point <= 0.0)
     {
      LTLog(0, "symbol point size unknown");
      return(INIT_FAILED);
     }
   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

   //--- trade object
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints((ulong)InpDeviationPoints);
   g_trade.SetMarginMode();
   g_trade.SetAsyncMode(false);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   //--- indicators
   g_atrHandle = iATR(_Symbol, g_sigTF, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
      LTLog(0, "ATR handle failed (" + IntegerToString(GetLastError()) + ") - ATR features disabled");
   if(InpUseMAFilter)
     {
      ENUM_TIMEFRAMES maTF = (InpMATF == PERIOD_CURRENT) ? g_sigTF : InpMATF;
      g_maHandle = iMA(_Symbol, maTF, InpMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
      if(g_maHandle == INVALID_HANDLE)
        {
         LTLog(0, "MA handle failed (" + IntegerToString(GetLastError()) + ")");
         return(INIT_FAILED);
        }
     }
   if(InpUseADXFilter)
     {
      ENUM_TIMEFRAMES adxTF = (InpADXTF == PERIOD_CURRENT) ? g_sigTF : InpADXTF;
      g_adxHandle = iADX(_Symbol, adxTF, InpADXPeriod);
      if(g_adxHandle == INVALID_HANDLE)
        {
         LTLog(0, "ADX handle failed (" + IntegerToString(GetLastError()) + ")");
         return(INIT_FAILED);
        }
     }
   if(InpVAL_Enable)
     {
      g_valHandle = iCustom(_Symbol, g_sigTF, InpVAL_IndicatorName,
                            InpVAL_ProfilePeriod,          // Profile period
                            InpVAL_SourceTF,               // Source timeframe
                            InpVAL_ValueAreaPercent,       // Value Area percent
                            (int)InpVAL_VolumeType,        // Volume type
                            InpVAL_MaxSessions,            // Max sessions back
                            InpVAL_BinPoints,              // Bin size in points
                            8,                             // Sessions to draw back (unused, silent)
                            false,                         // Forecast objects
                            InpVAL_ForecastSessions,       // Forecast sessions
                            false,                         // Show developing
                            false,                         // Show previous
                            false,                         // Show history
                            false,                         // Show profile
                            false,                         // POC live colors
                            false,                         // POC history colors
                            false);                        // Draw chart objects -> silent instance
      if(g_valHandle == INVALID_HANDLE)
        {
         LTLog(0, "cannot load indicator '" + InpVAL_IndicatorName + "' (error " + IntegerToString(GetLastError())
               + ") - put ValueAreaLevels.ex5 in MQL5\\Indicators or fix InpVAL_IndicatorName");
         return(INIT_FAILED);
        }
     }

   //--- name filters
   SplitList(InpObjIncludePrefixes, g_inclPrefix);
   SplitList(InpObjExcludePrefixes, g_exclPrefix);
   if(InpVAL_Enable && InpVAL_ExcludeObjects)
      AddPrefix(g_exclPrefix, "VAL_");
   ParseManualInputs();
   SetupEngine();

   //--- chart events for live line editing
   if(!g_isTester)
     {
      ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
      ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
     }
   EventSetTimer(1);

   ArrayResize(g_levels, 0);
   ArrayResize(g_links, 0);
   ArrayResize(g_losses, 0);
   g_lastBarTime = 0;
   g_objDirty = true;
   g_lastEngineRun = 0;
   g_dayStart = 0;
   g_lastBlock = "";
   g_signalSeq = 0;
   LoadState();
   string why = "";
   if(!TradingAllowed(why))
      LTLog(0, "warning: " + why);
   if(InpTradeMode == LT_MODE_SIGNAL_ONLY)
      LTLog(0, "SIGNAL ONLY mode: no orders will be sent");
   LTLog(1, "initialised: " + EntryModeName() + " / " + (InpDirectionMode == LT_DIR_BOUNCE ? "Bounce" : "Breakout")
         + ", signals on " + TFToString(g_sigTF) + ", " + (g_hedging ? "hedging" : "netting") + " account");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(ArraySize(g_levels) > 0 || ArraySize(g_saved) > 0)
      SaveState();
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   if(g_maHandle != INVALID_HANDLE)
      IndicatorRelease(g_maHandle);
   if(g_adxHandle != INVALID_HANDLE)
      IndicatorRelease(g_adxHandle);
   if(g_valHandle != INVALID_HANDLE)
      IndicatorRelease(g_valHandle);
   g_atrHandle = INVALID_HANDLE;
   g_maHandle  = INVALID_HANDLE;
   g_adxHandle = INVALID_HANDLE;
   g_valHandle = INVALID_HANDLE;
   Comment("");
   if(InpDeleteObjectsOnExit)
      ObjectsDeleteAll(0, LT_PREFIX);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Main loop                                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!UpdateMarket())
      return;
   datetime barTime = SignalBarTime(0);
   if(barTime == 0)
      return;
   bool newBar = (barTime != g_lastBarTime);
   bool firstRun = (g_lastBarTime == 0);
   if(newBar)
     {
      g_lastBarTime = barTime;
      g_signalsThisBar = 0;
     }
   if(newBar || g_atr <= 0.0)
     {
      UpdateATR();
      UpdateZone();
     }

   //--- built-in engine: on every new chart bar (and until it is ready)
   bool engineDue = false;
   if(ArraySize(g_eng) > 0)
     {
      datetime chartBar = iTime(_Symbol, _Period, 0);
      bool notReady = false;
      for(int j = 0; j < ArraySize(g_eng); j++)
         if(!g_eng[j].ready)
            notReady = true;
      engineDue = (g_lastEngineRun == 0) || (chartBar != 0 && g_lastEngineRun < chartBar)
                  || (notReady && TimeCurrent() - g_lastEngineRun >= 10);
      if(engineDue)
         RunEngine();
     }

   //--- level list
   bool rescan = newBar || engineDue || g_objDirty || firstRun
                 || (TimeCurrent() - g_lastObjScan >= MathMax(InpObjRescanSeconds, 0));
   if(rescan)
     {
      RebuildLevels();
      if(firstRun)
         RelinkPositions();
     }

   //--- bookkeeping
   if(newBar || firstRun || TimeCurrent() - g_lastHistoryScan >= 10)
      UpdateDailyStats(true);
   else
      UpdateDailyStats(false);
   PruneLinks();
   ManagePositions();

   //--- bar logic: the close-confirmed check runs BEFORE roles are updated with that close,
   //    so it sees the side price came from
   if(newBar)
     {
      if(!firstRun && InpEntryMode == LT_ENTRY_CONFIRM_CLOSE)
         CheckBarSignals();
      UpdateLevelRoles(iClose(_Symbol, g_sigTF, 1));
      if(g_stateDirty)
         SaveState();
     }
   //--- tick logic
   if(InpEntryMode == LT_ENTRY_TOUCH)
      CheckTouchSignals();
   UpdateLevelTicks(g_tick.bid);
   if(InpEntryMode == LT_ENTRY_PENDING)
      MaintainPendingOrders(newBar);
   UpdateDashboard();
  }

void OnTimer()
  {
   if(g_isTester)
      return;
   if(g_lastBarTime == 0)
      return;
   if(UpdateMarket())
      UpdateDashboard();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CREATE || id == CHARTEVENT_OBJECT_DELETE || id == CHARTEVENT_OBJECT_CHANGE
      || id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_ENDEDIT)
     {
      if(!StartsWith(sparam, LT_PREFIX))
         g_objDirty = true;
     }
  }
//+------------------------------------------------------------------+
