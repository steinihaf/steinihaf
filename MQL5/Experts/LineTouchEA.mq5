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

input group "=== Level source 4: manual ==="
input string InpManualLevels         = "";            // Prices, e.g. 4343.31;4272.32;4155.23
input string InpManualTrendLines     = "";            // Lines: yyyy.mm.dd hh:mi|price|yyyy.mm.dd hh:mi|price;...

input group "=== Level handling ==="
input int    InpMergeDistancePoints  = 50;            // Merge levels closer than N points (0 = off)

input group "=== Signals ==="
input ENUM_TIMEFRAMES InpSignalTF    = PERIOD_CURRENT; // Signal timeframe (Current = chart)
input ENUM_LT_ENTRY_MODE InpEntryMode = LT_ENTRY_TOUCH; // Entry mode
input ENUM_LT_DIRECTION_MODE InpDirectionMode = LT_DIR_BOUNCE; // Direction mode
input ENUM_LT_TRADE_PERMIT InpTradePermit = LT_PERMIT_BOTH; // Allowed directions
input int    InpTouchZonePoints      = 200;           // Touch zone around the level (points)
input double InpZoneATRFraction      = 0.0;           // Zone = max(points, ATR x fraction) (0 = off)
input int    InpATRPeriod            = 14;            // ATR period (zone / stop-loss)
input double InpMinRejectionRatio    = 0.5;           // Confirm: min close position inside the bar range (0..1)
input int    InpBreakoutBufferPoints = 100;           // Breakout: price must pass the level by N points
input int    InpRearmPoints          = 200;           // Re-arm when price is N points outside the zone
input int    InpCooldownBars         = 3;             // Bars between signals on the same level
input int    InpMaxTradesPerLevel    = 0;             // Lifetime trades per level (0 = unlimited)
input int    InpMaxPositionsPerLevel = 1;             // Open positions per level
input int    InpMaxOpenPositions     = 2;             // Open positions in total (this EA, this symbol)
input int    InpMinEntrySpacingPoints = 300;          // Min distance from an existing same-direction entry
input ENUM_LT_OPPOSITE InpOppositeMode = LT_OPP_SKIP; // When an opposite position is open
input bool   InpOneSignalPerBar      = true;          // At most one new trade per bar

input group "=== Pending orders (entry mode = Pending) ==="
input int    InpPendingOffsetPoints  = 20;            // Order price offset from the level (points)
input int    InpPendingExpiryBars    = 24;            // Delete after N bars (0 = good till cancelled)
input int    InpPendingMinDistancePoints = 150;       // Do not place when the level is closer than N points
input bool   InpPendingDeleteOrphans = true;          // Delete this EA's pending orders that match no level

input group "=== Filters ==="
input int    InpMaxSpreadPoints      = 350;           // Max spread (points, 0 = off)
input bool   InpUseTimeFilter        = false;         // Use trading hours (server time)
input int    InpStartHour            = 1;             // Trading start hour
input int    InpEndHour              = 23;            // Trading end hour (exclusive)
input int    InpFridayStopHour       = 0;             // No new trades on Friday from this hour (0 = off)
input int    InpMaxTradesPerDay      = 0;             // Max new trades per day (0 = off)
input double InpMaxDailyLossPercent  = 0.0;           // Stop for the day after losing N% of balance (0 = off)
input bool   InpUseMAFilter          = false;         // Trade only with the moving-average trend
input int    InpMAPeriod             = 200;           // MA period
input ENUM_MA_METHOD InpMAMethod     = MODE_EMA;      // MA method
input ENUM_TIMEFRAMES InpMATF        = PERIOD_CURRENT; // MA timeframe

input group "=== Risk ==="
input ENUM_LT_LOT_MODE InpLotMode    = LT_LOT_RISK_PERCENT; // Lot mode
input double InpFixedLot             = 0.01;          // Fixed lot
input double InpRiskPercent          = 1.0;           // Risk per trade (% of balance)
input bool   InpAllowMinLotOverRisk  = false;         // Use the minimum lot when the risk lot is smaller
input ENUM_LT_SL_MODE InpSLMode      = LT_SL_BEYOND_LEVEL; // Stop-loss mode
input int    InpSLBufferPoints       = 300;           // Stop-loss buffer beyond the level (points)
input int    InpSLFixedPoints        = 800;           // Fixed stop-loss (points)
input double InpSLATRMult            = 1.5;           // ATR multiple for the stop-loss
input int    InpMaxSLPoints          = 1500;          // Skip the trade if the stop would be wider (0 = off)
input ENUM_LT_TP_MODE InpTPMode      = LT_TP_NEXT_LEVEL; // Take-profit mode
input double InpTPRR                 = 1.5;           // R multiple
input int    InpTPFixedPoints        = 1200;          // Fixed take-profit (points)
input int    InpTPLevelBufferPoints  = 100;           // Take profit N points before the next level
input int    InpTPMinPoints          = 400;           // Next level must be at least N points away
input int    InpBreakEvenTriggerPoints = 0;           // Move stop to break-even after N points (0 = off)
input int    InpBreakEvenLockPoints  = 20;            // Break-even lock (points)
input int    InpTrailingStartPoints  = 0;             // Start trailing after N points (0 = off)
input int    InpTrailingStopPoints   = 500;           // Trailing distance (points)
input int    InpTrailingStepPoints   = 50;            // Trailing step (points)

input group "=== Execution ==="
input ulong  InpMagic                = 20261017;      // Magic number
input int    InpDeviationPoints      = 50;            // Max slippage (points)
input string InpTradeComment         = "LT";          // Order comment prefix

input group "=== Display & alerts ==="
input bool   InpShowDashboard        = true;          // Show the dashboard
input int    InpDashboardLevels      = 12;            // Levels listed on the dashboard
input bool   InpDrawMarkers          = true;          // Draw entry arrows
input bool   InpDeleteObjectsOnExit  = true;          // Delete this EA's objects when removed
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
   bool     needReset;      // true after a signal until price has moved away again
   datetime lastSignalTime; // signal-bar time of the last signal on this level
   int      trades;         // lifetime trades on this level
   ulong    pendingTicket;  // resting order ticket (pending mode)
   int      pendingType;    // ENUM_ORDER_TYPE of the resting order, -1 = none
   datetime pendingBar;     // signal-bar time when the order was last placed

   void     Reset()
     {
      key = ""; label = ""; source = 0; kind = 0; objName = ""; clr = clrWhite;
      price = 0.0; prevPrice = 0.0; t1 = 0; p1 = 0.0; t2 = 0; p2 = 0.0; rayRight = true; rayLeft = false;
      role = 0; needReset = false; lastSignalTime = 0; trades = 0;
      pendingTicket = 0; pendingType = -1; pendingBar = 0;
     }
   void     CopyStateFrom(const SLevel &o)
     {
      role = o.role; needReset = o.needReset; lastSignalTime = o.lastSignalTime; trades = o.trades;
      pendingTicket = o.pendingTicket; pendingType = o.pendingType; pendingBar = o.pendingBar;
     }
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
int             g_valHandle    = INVALID_HANDLE;
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

// fills price (current bar) and prevPrice (previous signal bar) of a sloped level
bool ComputeSlopedPrices(SLevel &L)
  {
   datetime tNow  = iTime(_Symbol, _Period, 0);
   datetime tPrev = SignalBarTime(1);
   if(tNow == 0)
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

void ReadValueAreaLevels(SLevel &out[])
  {
   if(g_valHandle == INVALID_HANDLE)
      return;
   if(BarsCalculated(g_valHandle) < 2)
      return;
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
      if(v1 == EMPTY_VALUE || v1 <= 0.0)
         v1 = v0;
      SLevel L;
      L.Reset();
      L.key       = "VAL:" + g_valNames[b];
      L.label     = g_valNames[b];
      L.source    = LT_SRC_VAL;
      L.kind      = 0;
      L.price     = v0;
      L.prevPrice = v1;
      L.clr       = ValBufferColor(b);
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
      double ref = low[0];
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

void ReadEngineLevels(SLevel &out[])
  {
   for(int j = 0; j < ArraySize(g_eng); j++)
     {
      if(!g_eng[j].ready)
         continue;
      string tfs = TFToString(g_eng[j].tf);
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
            L.key      = "TL:" + tfs + ((d == 0) ? ":Down" : ":Up");
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
      case LT_SRC_OBJECT:    return(0);
      case LT_SRC_VAL:       return(1);
      case LT_SRC_ENGINE_SR: return(2);
      case LT_SRC_ENGINE_TL: return(3);
     }
   return(4);
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
      // group [i, j): primary = best source rank, then lowest price
      int best = i;
      for(int k = i + 1; k < j; k++)
         if(SourceRank(src[k].source) < SourceRank(src[best].source))
            best = k;
      SLevel L = src[best];
      for(int k = i; k < j; k++)
         if(k != best)
            L.label += "+" + src[k].label;
      AppendLevel(out, L);
      i = j;
     }
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
      if(old >= 0)
         merged[i].CopyStateFrom(g_levels[old]);
     }
   ArrayResize(g_levels, ArraySize(merged));
   for(int i = 0; i < ArraySize(merged); i++)
      g_levels[i] = merged[i];
   g_lastObjScan = TimeCurrent();
   g_objDirty = false;
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
      if(alive)
        {
         if(w != i)
            g_links[w] = g_links[i];
         w++;
        }
     }
   ArrayResize(g_links, w);
  }

// does the selected position belong to the level?
bool SelectedPositionIsLevel(const string key)
  {
   ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   ulong ident  = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(LinkedKey(ticket) == key || LinkedKey(ident) == key)
      return(true);
   return(CommentMatchesKey(PositionGetString(POSITION_COMMENT), key));
  }

int CountLevelPositions(const string key)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !IsOurPosition())
         continue;
      if(SelectedPositionIsLevel(key))
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
      g_dayRealized = 0.0;
      g_dayTrades   = 0;
      if(HistorySelect(dayStart, now + 86400))
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
            if(entry == DEAL_ENTRY_IN)
               g_dayTrades++;
            g_dayRealized += HistoryDealGetDouble(deal, DEAL_PROFIT)
                             + HistoryDealGetDouble(deal, DEAL_COMMISSION)
                             + HistoryDealGetDouble(deal, DEAL_SWAP);
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

// common checks for a new entry (market or pending)
bool EntryAllowed(const int dir, const SLevel &L, string &why)
  {
   if(!TradingAllowed(why))
      return(false);
   if(!DirectionPermitted(dir))
     {
      why = "direction not permitted";
      return(false);
     }
   if(g_dayStopped)
     {
      why = "daily loss limit reached";
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
      why = "outside trading hours";
      return(false);
     }
   if(!MAFilterOK(dir))
     {
      why = "against the MA trend";
      return(false);
     }
   int buys = 0, sells = 0;
   CountPositions(buys, sells);
   if(buys + sells >= InpMaxOpenPositions)
     {
      why = "max open positions reached";
      return(false);
     }
   if(InpMaxPositionsPerLevel > 0 && CountLevelPositions(L.key) >= InpMaxPositionsPerLevel)
     {
      why = "level already has a position";
      return(false);
     }
   int opposite = (dir > 0) ? sells : buys;
   if(opposite > 0)
     {
      if(InpOppositeMode == LT_OPP_SKIP)
        {
         why = "opposite position open";
         return(false);
        }
      if(InpOppositeMode == LT_OPP_HEDGE && !g_hedging)
        {
         why = "opposite position open (netting account cannot hedge)";
         return(false);
        }
     }
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
         sl = (dir > 0) ? levelPrice - Pts(InpSLBufferPoints) : levelPrice + Pts(InpSLBufferPoints);
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

double ComputeTP(const int dir, const double entry, const double sl, const SLevel &L)
  {
   double risk = MathAbs(entry - sl);
   double tp = 0.0;
   switch(InpTPMode)
     {
      case LT_TP_NONE:
         return(0.0);
      case LT_TP_FIXED_POINTS:
         tp = (dir > 0) ? entry + Pts(InpTPFixedPoints) : entry - Pts(InpTPFixedPoints);
         break;
      case LT_TP_NEXT_LEVEL:
        {
         double nxt = NextLevelPrice(dir, entry, L.key);
         if(nxt > 0.0)
           {
            tp = (dir > 0) ? nxt - Pts(InpTPLevelBufferPoints) : nxt + Pts(InpTPLevelBufferPoints);
            break;
           }
         if(InpTPRR <= 0.0)
            return(0.0);
        }
      // fallback: R multiple
      default:
         if(InpTPRR <= 0.0)
            return(0.0);
         tp = (dir > 0) ? entry + risk * InpTPRR : entry - risk * InpTPRR;
         break;
     }
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
bool TryOpen(SLevel &L, const int dir, const string reason)
  {
   string why = "";
   if(!EntryAllowed(dir, L, why))
     {
      LTLog(2, "signal on " + L.label + " skipped: " + why);
      return(false);
     }
   double entry = (dir > 0) ? g_tick.ask : g_tick.bid;
   if(!EntrySpacingOK(dir, entry))
     {
      LTLog(2, "signal on " + L.label + " skipped: too close to an existing entry");
      return(false);
     }
   double sl = ComputeSL(dir, entry, L.price);
   if(InpMaxSLPoints > 0 && MathAbs(entry - sl) > Pts(InpMaxSLPoints))
     {
      LTLog(2, "signal on " + L.label + " skipped: stop " + DoubleToString(MathAbs(entry - sl) / g_point, 0)
            + " pts > max " + IntegerToString(InpMaxSLPoints));
      return(false);
     }
   double tp = ComputeTP(dir, entry, sl, L);
   EnforceStopDistances(dir, (dir > 0) ? g_tick.bid : g_tick.ask, sl, tp);
   double lots = ComputeLots(entry, sl);
   if(lots <= 0.0)
      return(false);
   if(!MarginOK(dir, lots, entry))
      return(false);
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
      string side = (dir > 0) ? "BUY" : "SELL";
      LTLog(0, side + " on " + L.label + " failed: " + IntegerToString((int)rc)
            + " " + g_trade.ResultRetcodeDescription());
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
   DrawMarker(dir, fill, L.label + " " + reason, ticket);
   Notify((dir > 0 ? "BUY " : "SELL ") + DoubleToString(lots, 2) + " @ " + PriceStr(fill)
          + " level " + L.label + " " + PriceStr(L.price) + " (" + reason + ") SL " + PriceStr(sl)
          + " TP " + (tp > 0.0 ? PriceStr(tp) : "none"));
   return(true);
  }

//+------------------------------------------------------------------+
//| Level roles and arming                                           |
//+------------------------------------------------------------------+
bool LevelArmed(const SLevel &L)
  {
   if(L.role == 0 || L.needReset)
      return(false);
   if(InpMaxTradesPerLevel > 0 && L.trades >= InpMaxTradesPerLevel)
      return(false);
   if(InpCooldownBars > 0 && BarsSince(L.lastSignalTime) < InpCooldownBars)
      return(false);
   return(true);
  }

// refPrice: current Bid (intrabar logic) or the last completed close (bar logic)
void UpdateLevelStates(const double refPrice)
  {
   double rearm = g_zone + Pts(InpRearmPoints);
   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      double d = refPrice - g_levels[i].price;
      if(d > g_zone)
         g_levels[i].role = 1;
      else if(d < -g_zone)
         g_levels[i].role = -1;
      if(g_levels[i].needReset && MathAbs(d) > rearm)
         g_levels[i].needReset = false;
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
   double breakBuf = Pts(InpBreakoutBufferPoints);
   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      if(!LevelArmed(g_levels[i]))
         continue;
      double lv = g_levels[i].price;
      int dir = 0;
      string reason = "";
      if(InpDirectionMode == LT_DIR_BOUNCE)
        {
         bool inZone = (bid <= lv + g_zone && bid >= lv - g_zone);
         if(!inZone)
            continue;
         dir = (g_levels[i].role > 0) ? 1 : -1;
         reason = "touch";
        }
      else
        {
         if(g_levels[i].role > 0 && bid < lv - breakBuf)
            dir = -1;
         else if(g_levels[i].role < 0 && bid > lv + breakBuf)
            dir = 1;
         if(dir == 0)
            continue;
         reason = "break";
        }
      if(TryOpen(g_levels[i], dir, reason))
        {
         if(InpOneSignalPerBar)
            return;
        }
      else
        {
         // the touch happened but could not be traded: do not retry on every tick
         g_levels[i].needReset = true;
         g_levels[i].lastSignalTime = SignalBarTime(0);
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
   double breakBuf = Pts(InpBreakoutBufferPoints);
   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      if(!LevelArmed(g_levels[i]))
         continue;
      double lv = g_levels[i].prevPrice;        // level value on the bar that just closed
      int dir = 0;
      string reason = "";
      if(InpDirectionMode == LT_DIR_BOUNCE)
        {
         if(g_levels[i].role > 0 && l1 <= lv + g_zone && c1 > lv)
           {
            double ratio = (range > 0.0) ? (c1 - l1) / range : 1.0;
            if(ratio >= InpMinRejectionRatio)
               dir = 1;
           }
         else if(g_levels[i].role < 0 && h1 >= lv - g_zone && c1 < lv)
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
      if(TryOpen(g_levels[i], dir, reason))
        {
         if(InpOneSignalPerBar)
            return;
        }
      else
        {
         g_levels[i].needReset = true;
         g_levels[i].lastSignalTime = SignalBarTime(0);
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
   if(!EntryAllowed(dir, L, why))
     {
      LTLog(2, "pending on " + L.label + " not placed: " + why);
      return(false);
     }
   double price = PendingPrice(L, type);
   if(!PendingPriceValid(type, price))
      return(false);
   if(!EntrySpacingOK(dir, price))
      return(false);
   double sl = ComputeSL(dir, price, L.price);
   if(InpMaxSLPoints > 0 && MathAbs(price - sl) > Pts(InpMaxSLPoints))
      return(false);
   double tp = ComputeTP(dir, price, sl, L);
   EnforceStopDistances(dir, price, sl, tp);
   double lots = ComputeLots(price, sl);
   if(lots <= 0.0)
      return(false);
   if(!MarginOK(dir, lots, price))
      return(false);
   datetime exp = PendingExpiration();
   ENUM_ORDER_TYPE_TIME tt = (exp > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
   string comment = LevelComment(L.key);
   bool sent = false;
   switch(type)
     {
      case ORDER_TYPE_BUY_LIMIT:  sent = g_trade.BuyLimit(lots, price, _Symbol, sl, tp, tt, exp, comment);  break;
      case ORDER_TYPE_SELL_LIMIT: sent = g_trade.SellLimit(lots, price, _Symbol, sl, tp, tt, exp, comment); break;
      case ORDER_TYPE_BUY_STOP:   sent = g_trade.BuyStop(lots, price, _Symbol, sl, tp, tt, exp, comment);   break;
      case ORDER_TYPE_SELL_STOP:  sent = g_trade.SellStop(lots, price, _Symbol, sl, tp, tt, exp, comment);  break;
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
   double tp = ComputeTP(dir, price, sl, L);
   EnforceStopDistances(dir, price, sl, tp);
   ENUM_ORDER_TYPE_TIME tt = (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
   datetime exp = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
   if(!g_trade.OrderModify(L.pendingTicket, price, sl, tp, tt, exp))
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
      Notify("order #" + IntegerToString((long)L.pendingTicket) + " on " + L.label + " filled");
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
         bool mine = (LinkedKey(ticket) == g_levels[i].key)
                     || CommentMatchesKey(OrderGetString(ORDER_COMMENT), g_levels[i].key);
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
   //--- orphans and manual expiry
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
         if(InpPendingDeleteOrphans)
            DeletePending(ticket, "no matching level");
         continue;
        }
      if(InpPendingExpiryBars > 0 && !g_expirySupported)
        {
         datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         if(BarsSince(setup) >= InpPendingExpiryBars)
            DeletePending(ticket, "expired");
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
         bool wrong = (desired < 0) || (type != desired) || capReached
                      || (InpMaxPositionsPerLevel > 0 && CountLevelPositions(g_levels[i].key) >= InpMaxPositionsPerLevel);
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
         if(CommentMatchesKey(comment, g_levels[k].key))
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
   if(L.role == 0)
      return("wait side");
   if(InpMaxTradesPerLevel > 0 && L.trades >= InpMaxTradesPerLevel)
      return("done");
   if(L.needReset)
      return("used");
   if(InpCooldownBars > 0 && BarsSince(L.lastSignalTime) < InpCooldownBars)
      return("cooldown");
   if(L.pendingTicket != 0)
      return("order #" + IntegerToString((long)L.pendingTicket));
   return("ARMED");
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
        + "   zone: " + DoubleToString(g_zone / g_point, 0) + " pts   spread: " + IntegerToString(SpreadPoints())
        + "   ATR: " + (g_atr > 0.0 ? DoubleToString(g_atr / g_point, 0) : "-") + " pts\n";
   s += "Trading: " + (allowed ? "allowed" : ("BLOCKED - " + why))
        + (g_dayStopped ? "   DAILY LOSS STOP" : "") + "\n";
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
      s += "  " + PriceStr(g_levels[i].price) + "  " + roleTxt + "  " + (d >= 0 ? "+" : "") + DoubleToString(d, 0)
           + " pts  " + LevelStateName(g_levels[i]) + "  [" + SourceName(g_levels[i].source) + "] " + lbl + "\n";
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
   g_lastBarTime = 0;
   g_objDirty = true;
   g_lastEngineRun = 0;
   g_dayStart = 0;
   string why = "";
   if(!TradingAllowed(why))
      LTLog(0, "warning: " + why);
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
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   if(g_maHandle != INVALID_HANDLE)
      IndicatorRelease(g_maHandle);
   if(g_valHandle != INVALID_HANDLE)
      IndicatorRelease(g_valHandle);
   g_atrHandle = INVALID_HANDLE;
   g_maHandle  = INVALID_HANDLE;
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
      UpdateATR();
      UpdateZone();
     }
   if(g_zone <= 0.0)
      UpdateZone();

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

   //--- signals: roles are updated AFTER the checks so a check sees the side price came from
   if(InpEntryMode == LT_ENTRY_TOUCH)
     {
      CheckTouchSignals();
      UpdateLevelStates(g_tick.bid);
     }
   else if(InpEntryMode == LT_ENTRY_CONFIRM_CLOSE)
     {
      if(newBar && !firstRun)
         CheckBarSignals();
      if(newBar)
         UpdateLevelStates(iClose(_Symbol, g_sigTF, 1));
     }
   else
     {
      UpdateLevelStates(g_tick.bid);
      MaintainPendingOrders(newBar);
     }
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
