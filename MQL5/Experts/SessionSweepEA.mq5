//+------------------------------------------------------------------+
//|                                               SessionSweepEA.mq5 |
//|          Fades failed breakouts of the Asia / London / NY ranges |
//|                                                                  |
//|  1. While a session runs, the EA records its high and low.       |
//|  2. After the session ends, the range is armed.                  |
//|  3. Price breaks out of the range (above the high / below the    |
//|     low) and then CLOSES BACK INSIDE it within a few bars.       |
//|  4. The EA trades the reversal, never the break:                 |
//|        break of the HIGH that fails  ->  SELL                    |
//|        break of the LOW  that fails  ->  BUY                     |
//|     Stop-loss goes beyond the extreme of the failed break.       |
//|                                                                  |
//|  A break that holds (price stays outside too long or runs too    |
//|  far) is a real breakout and is NOT traded.                      |
//|  All session times are broker SERVER time.                       |
//|  Buffers and stops scale with the daily ATR, so the same inputs  |
//|  work on forex, gold (XAUUSD) and indices.                       |
//+------------------------------------------------------------------+
#property copyright   "steinihaf"
#property link        "https://github.com/steinihaf/steinihaf"
#property version     "1.11"
#property description "Session range reversal: when a session high/low is broken and price"
#property description "closes back inside the range, trade in the reversal direction."

#include <Trade/Trade.mqh>

#define SS_NAME      "SessionSweepEA"
#define SS_PREFIX    "SSEA_"          // prefix of every chart object this EA creates
#define SS_SESSIONS  3
#define SS_HIGH      0                // side index: session high
#define SS_LOW       1                // side index: session low

enum ENUM_SS_STATE
  {
   SS_ARMED  = 0,                     // level untouched, waiting for a break
   SS_BROKEN = 1,                     // price is beyond the level, waiting for the reversal
   SS_SPENT  = 2                      // traded, or the break held (real breakout)
  };

enum ENUM_SS_BREAK
  {
   SS_BREAK_WICK  = 0,                // Wick: any trade beyond the level counts as a break
   SS_BREAK_CLOSE = 1                 // Close: a bar must close beyond the level first
  };

enum ENUM_SS_PERMIT
  {
   SS_PERMIT_BOTH = 0,                // Buy and sell
   SS_PERMIT_BUY  = 1,                // Buy only (failed breaks of the low)
   SS_PERMIT_SELL = 2                 // Sell only (failed breaks of the high)
  };

enum ENUM_SS_LOT
  {
   SS_LOT_FIXED = 0,                  // Fixed lot
   SS_LOT_RISK  = 1                   // Risk percent of balance (from stop-loss distance)
  };

enum ENUM_SS_TP
  {
   SS_TP_RR       = 0,                // R multiple of the stop-loss distance
   SS_TP_MIDDLE   = 1,                // Middle of the session range
   SS_TP_OPPOSITE = 2,                // Opposite side of the session range
   SS_TP_NONE     = 3                 // No take-profit
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Sessions (broker server time, HH:MM) ==="
input bool   InpAsiaEnable        = true;           // Trade the Asian session range
input string InpAsiaStart         = "02:00";        // Asia start
input string InpAsiaEnd           = "10:00";        // Asia end
input bool   InpLondonEnable      = true;           // Trade the London session range
input string InpLondonStart       = "10:00";        // London start
input string InpLondonEnd         = "16:30";        // London end
input bool   InpNYEnable          = true;           // Trade the New York session range
input string InpNYStart           = "16:30";        // New York start
input string InpNYEnd             = "23:00";        // New York end
input int    InpRangeValidHours   = 10;             // Range is tradable for N hours after the session ends (0 = until it starts again)
input int    InpMinSessionBars    = 4;              // Minimum bars inside a session to accept its range
input int    InpMinRangePoints    = 0;              // Skip ranges smaller than N points (0 = off)
input int    InpMaxRangePoints    = 0;              // Skip ranges larger than N points (0 = off)

input group "=== Break and reversal ==="
input ENUM_TIMEFRAMES InpSignalTF = PERIOD_CURRENT; // Signal timeframe (Current = chart)
input ENUM_SS_BREAK InpBreakMode  = SS_BREAK_WICK;  // What counts as a break
input int    InpATRPeriod         = 14;             // Daily ATR period (scales the buffers to the symbol: forex, gold, indices)
input double InpBreakBufferATR    = 0.01;           // Break buffer: price must exceed the level by N x daily ATR
input int    InpBreakBufferPoints = 0;              // ...and by at least N points (the larger of the two is used)
input double InpReentryBufferATR  = 0.0;            // Re-entry buffer: bar must close back inside by N x daily ATR
input int    InpReentryBufferPoints = 0;            // ...and by at least N points
input int    InpMaxBarsOutside    = 6;              // Reversal must come within N bars of the break (else: real breakout, no trade)
input double InpMaxSweepPercent   = 50.0;           // Break may run at most N% of the range beyond the level (0 = off)
input ENUM_SS_PERMIT InpPermit    = SS_PERMIT_BOTH; // Allowed directions

input group "=== Risk ==="
input ENUM_SS_LOT InpLotMode      = SS_LOT_RISK;    // Lot sizing
input double InpFixedLot          = 0.10;           // Fixed lot
input double InpRiskPercent       = 0.5;            // Risk per trade (% of balance)
input double InpSLBufferATR       = 0.03;           // Stop-loss buffer beyond the break extreme: N x daily ATR
input int    InpSLBufferPoints    = 0;              // ...and at least N points
input double InpMinSLATR          = 0.06;           // Minimum stop distance: N x daily ATR (stop is widened to this)
input int    InpMinSLPoints       = 0;              // ...and at least N points
input double InpMaxSLATR          = 0.0;            // Skip the trade if the stop is wider than N x daily ATR (0 = off)
input int    InpMaxSLPoints       = 0;              // Skip the trade if the stop is wider than N points (0 = off)
input ENUM_SS_TP InpTPMode        = SS_TP_RR;       // Take-profit
input double InpTPRR              = 2.0;            // Take-profit R multiple (R mode)
input double InpMinRR             = 1.0;            // Middle / Opposite: skip when reward / risk is below N (0 = off)
input double InpBreakEvenRR       = 1.0;            // Move stop to break-even after N x R profit (0 = off)
input double InpBreakEvenLockR    = 0.05;           // Break-even lock: stop goes N x R beyond the entry

input group "=== Limits ==="
input int    InpMaxSpreadPoints   = 0;              // Max spread (points, 0 = off)
input double InpMaxSpreadPercentOfSL = 15.0;        // Max spread as % of the stop distance (0 = off)
input int    InpMaxOpenPositions  = 1;              // Open positions at once (this EA, this symbol)
input int    InpMaxTradesPerDay   = 3;              // Max new trades per day (0 = off)
input double InpMaxDailyLossPercent = 2.0;          // Stop for the day after losing N% of balance (0 = off)
input string InpCloseTime         = "";             // Close all and stop trading at HH:MM server time (empty = off)

input group "=== General ==="
input long   InpMagic             = 20261124;       // Magic number
input int    InpDeviationPoints   = 0;              // Max slippage (points, 0 = auto: 2 x spread, at least 10)
input bool   InpDraw              = true;           // Draw session boxes, levels and signals
input bool   InpAlerts            = false;          // Alert on every signal
input bool   InpDashboard         = true;           // Show status on the chart
input bool   InpVerbose           = false;          // Log skipped signals and state changes

//+------------------------------------------------------------------+
//| State                                                            |
//+------------------------------------------------------------------+
struct SSession
  {
   string            name;
   bool              enabled;
   int               startMin;        // minutes after server midnight
   int               durMin;          // session length in minutes
   color             clr;
   datetime          rs;              // start of the tracked (last completed) session
   datetime          re;              // its end = first moment the range is tradable
   datetime          expiry;          // range no longer tradable from here
   bool              valid;           // range passed the size filters
   double            hi;
   double            lo;
   int               state[2];        // ENUM_SS_STATE per side
   int               bars[2];         // bars since the break
   double            ext[2];          // extreme reached beyond the level
   datetime          lastBar;         // last closed bar fed to the state machine
  };

SSession        g_s[SS_SESSIONS];
CTrade          g_trade;
ENUM_TIMEFRAMES g_tf        = PERIOD_CURRENT;
datetime        g_lastBar   = 0;
int             g_closeMin  = -1;
int             g_atrHandle = INVALID_HANDLE;
double          g_atr       = 0.0;      // last completed daily ATR, 0 until history is ready
string          g_lastNote  = "";

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
void Note(const string msg, const bool always = false)
  {
   g_lastNote = TimeToString(TimeCurrent(), TIME_MINUTES) + "  " + msg;
   if(always || InpVerbose)
      Print(SS_NAME, ": ", msg);
  }

double Pts(const int points)        { return points * _Point; }

// A distance that scales with the symbol: the larger of N points and a fraction of the daily ATR.
double Dist(const int points, const double atrFraction)
  {
   return MathMax(points * _Point, g_atr * atrFraction);
  }

void RefreshATR()
  {
   double buf[];
   if(g_atrHandle != INVALID_HANDLE && CopyBuffer(g_atrHandle, 0, 1, 1, buf) == 1 && buf[0] > 0.0)
      g_atr = buf[0];
  }
string PriceStr(const double p)     { return DoubleToString(p, _Digits); }

double RoundToTick(const double price)
  {
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      return NormalizeDouble(price, _Digits);
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
  }

// "HH:MM" -> minutes after midnight, -1 when malformed
int ParseHHMM(const string text)
  {
   string parts[];
   if(StringSplit(text, ':', parts) != 2)
      return -1;
   int h = (int)StringToInteger(parts[0]);
   int m = (int)StringToInteger(parts[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return -1;
   return h * 60 + m;
  }

bool SetupSession(const int i, const string name, const bool enabled,
                  const string startText, const string endText, const color clr)
  {
   g_s[i].name    = name;
   g_s[i].enabled = enabled;
   g_s[i].clr     = clr;
   g_s[i].rs      = 0;
   g_s[i].re      = 0;
   g_s[i].expiry  = 0;
   g_s[i].valid   = false;
   g_s[i].lastBar = 0;
   int a = ParseHHMM(startText), b = ParseHHMM(endText);
   if(a < 0 || b < 0 || a == b)
     {
      if(enabled)
         Print(SS_NAME, ": bad ", name, " session time '", startText, "' - '", endText, "' (use HH:MM)");
      return !enabled;
     }
   g_s[i].startMin = a;
   g_s[i].durMin   = (b - a + 1440) % 1440;      // sessions may wrap past midnight
   return true;
  }

int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         n++;
     }
   return n;
  }

// Today's entries and closed profit for this EA; "comment"/"since" look for one specific signal.
void DayStats(int &trades, double &profit, const string comment, const datetime since, bool &seen)
  {
   trades = 0;
   profit = 0.0;
   seen   = false;
   datetime now = TimeCurrent();
   datetime day = now - now % 86400;
   datetime from = (since > 0 && since < day) ? since : day;
   if(!HistorySelect(from, now + 60))
      return;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic)
         continue;
      datetime t = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
        {
         if(t >= day)
            trades++;
         if(since > 0 && t >= since && HistoryDealGetString(deal, DEAL_COMMENT) == comment)
            seen = true;
        }
      else
         if(t >= day)
            profit += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP)
                      + HistoryDealGetDouble(deal, DEAL_COMMISSION);
     }
  }

double LotsFor(const ENUM_ORDER_TYPE type, const double entry, const double sl)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0)
      step = vmin;
   double lots = InpFixedLot;
   if(InpLotMode == SS_LOT_RISK)
     {
      double lossPerLot = 0.0, calc = 0.0;
      if(OrderCalcProfit(type, _Symbol, 1.0, entry, sl, calc) && calc < 0.0)
         lossPerLot = -calc;
      else
        {
         double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
         if(tickSize > 0.0)
            lossPerLot = MathAbs(entry - sl) / tickSize * tickValue;
        }
      if(lossPerLot <= 0.0)
         return 0.0;
      lots = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0 / lossPerLot;
     }
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < vmin)
      return 0.0;                                  // never risk more than asked for
   if(lots > vmax)
      lots = vmax;
   return NormalizeDouble(lots, 8);
  }

//+------------------------------------------------------------------+
//| Drawing                                                          |
//+------------------------------------------------------------------+
void DrawSession(const SSession &S)
  {
   if(!InpDraw)
      return;
   string id = SS_PREFIX + S.name + "_" + IntegerToString((long)S.rs);
   string box = id + "_box";
   if(ObjectFind(0, box) < 0)
      ObjectCreate(0, box, OBJ_RECTANGLE, 0, S.rs, S.hi, S.re, S.lo);
   ObjectSetInteger(0, box, OBJPROP_COLOR, S.clr);
   ObjectSetInteger(0, box, OBJPROP_FILL, false);
   ObjectSetInteger(0, box, OBJPROP_BACK, true);
   ObjectSetInteger(0, box, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, box, OBJPROP_TOOLTIP, S.name + " range " + PriceStr(S.lo) + " - " + PriceStr(S.hi));
   for(int side = 0; side < 2; side++)
     {
      string line = id + (side == SS_HIGH ? "_hi" : "_lo");
      double price = (side == SS_HIGH) ? S.hi : S.lo;
      if(ObjectFind(0, line) < 0)
         ObjectCreate(0, line, OBJ_TREND, 0, S.re, price, S.expiry, price);
      ObjectSetInteger(0, line, OBJPROP_COLOR, S.clr);
      ObjectSetInteger(0, line, OBJPROP_STYLE, S.valid ? STYLE_DASH : STYLE_DOT);
      ObjectSetInteger(0, line, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, line, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, line, OBJPROP_TOOLTIP, S.name + (side == SS_HIGH ? " high " : " low ") + PriceStr(price));
     }
  }

void DrawSignal(const SSession &S, const int side, const datetime t, const double price, const bool traded)
  {
   if(!InpDraw)
      return;
   string name = SS_PREFIX + "sig_" + S.name + "_" + IntegerToString((long)t) + (side == SS_HIGH ? "_S" : "_B");
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, side == SS_HIGH ? OBJ_ARROW_SELL : OBJ_ARROW_BUY, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, traded ? (side == SS_HIGH ? clrTomato : clrDodgerBlue) : clrGray);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| Trade execution                                                  |
//+------------------------------------------------------------------+
// side = the level whose break failed. High -> sell, Low -> buy.
bool OpenReversal(const SSession &S, const int side, const double extreme)
  {
   bool   sell    = (side == SS_HIGH);
   string comment = "SS " + S.name + (sell ? " H" : " L");
   string what    = S.name + (sell ? " high" : " low") + " failed break -> " + (sell ? "SELL" : "BUY");

   if((sell && InpPermit == SS_PERMIT_BUY) || (!sell && InpPermit == SS_PERMIT_SELL))
     { Note(what + " skipped: direction not allowed"); return false; }

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(g_closeMin >= 0 && dt.hour * 60 + dt.min >= g_closeMin)
     { Note(what + " skipped: after close time"); return false; }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     { Note(what + " skipped: algo trading is disabled", true); return false; }

   // Without the daily ATR every ATR-based buffer and the minimum stop would be zero.
   if(g_atr <= 0.0)
      RefreshATR();
   if(g_atr <= 0.0 && (InpBreakBufferATR > 0.0 || InpReentryBufferATR > 0.0 || InpSLBufferATR > 0.0
                       || InpMinSLATR > 0.0 || InpMaxSLATR > 0.0))
     { Note(what + " skipped: daily ATR is not available yet", true); return false; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   if(InpMaxSpreadPoints > 0 && spread > Pts(InpMaxSpreadPoints))
     { Note(what + " skipped: spread " + DoubleToString(spread / _Point, 0) + " points"); return false; }

   if(CountPositions() >= InpMaxOpenPositions)
     { Note(what + " skipped: max open positions"); return false; }

   int trades; double dayProfit; bool seen;
   DayStats(trades, dayProfit, comment, S.re, seen);
   if(seen)
     { Note(what + " skipped: already traded"); return false; }
   if(InpMaxTradesPerDay > 0 && trades >= InpMaxTradesPerDay)
     { Note(what + " skipped: max trades per day"); return false; }
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(InpMaxDailyLossPercent > 0.0 && dayProfit <= -(balance - dayProfit) * InpMaxDailyLossPercent / 100.0)
     { Note(what + " skipped: daily loss limit reached"); return false; }

   // Stop beyond the extreme of the failed break. A sell stop is hit by the ask, so add the spread.
   double entry = sell ? bid : ask;
   double slBuf = Dist(InpSLBufferPoints, InpSLBufferATR);
   double sl    = sell ? extreme + slBuf + spread : extreme - slBuf;
   double minDist = MathMax(Dist(InpMinSLPoints, InpMinSLATR),
                            (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point + spread);
   if(MathAbs(sl - entry) < minDist || (sell && sl <= entry) || (!sell && sl >= entry))
      sl = sell ? entry + minDist : entry - minDist;
   sl = RoundToTick(sl);
   double risk = MathAbs(sl - entry);
   if((InpMaxSLPoints > 0 && risk > Pts(InpMaxSLPoints)) || (InpMaxSLATR > 0.0 && g_atr > 0.0 && risk > g_atr * InpMaxSLATR))
     { Note(what + " skipped: stop " + DoubleToString(risk / _Point, 0) + " points is too wide"); return false; }
   if(InpMaxSpreadPercentOfSL > 0.0 && spread > risk * InpMaxSpreadPercentOfSL / 100.0)
     { Note(what + " skipped: spread is " + DoubleToString(spread / risk * 100.0, 0) + "% of the stop"); return false; }

   double tp = 0.0;
   if(InpTPMode == SS_TP_RR)
      tp = sell ? entry - risk * InpTPRR : entry + risk * InpTPRR;
   else
      if(InpTPMode == SS_TP_MIDDLE || InpTPMode == SS_TP_OPPOSITE)
        {
         tp = (InpTPMode == SS_TP_MIDDLE) ? (S.hi + S.lo) / 2.0 : (sell ? S.lo : S.hi);
         double reward = sell ? entry - tp : tp - entry;
         if(reward <= 0.0 || (InpMinRR > 0.0 && reward < risk * InpMinRR))
           { Note(what + " skipped: target too close (" + DoubleToString(reward / risk, 2) + " R)"); return false; }
        }
   if(tp != 0.0)
      tp = RoundToTick(tp);

   ENUM_ORDER_TYPE type = sell ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double lots = LotsFor(type, entry, sl);
   if(lots <= 0.0)
     { Note(what + " skipped: lot size below the symbol minimum for this risk", true); return false; }

   if(InpDeviationPoints <= 0)
      g_trade.SetDeviationInPoints((ulong)MathMax(10.0, 2.0 * spread / _Point));
   bool ok = sell ? g_trade.Sell(lots, _Symbol, 0.0, sl, tp, comment)
                  : g_trade.Buy(lots, _Symbol, 0.0, sl, tp, comment);
   uint rc = g_trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL))
     {
      Note(what + " order failed: " + IntegerToString((int)rc) + " " + g_trade.ResultRetcodeDescription(), true);
      return false;
     }
   Note(what + "  " + DoubleToString(lots, 2) + " lots, sl " + PriceStr(sl) + ", tp " + PriceStr(tp), true);
   return true;
  }

void ManagePositions()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   bool closeAll = (g_closeMin >= 0 && dt.hour * 60 + dt.min >= g_closeMin);
   if(!closeAll && InpBreakEvenRR <= 0.0)
      return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(closeAll)
        {
         g_trade.PositionClose(ticket);
         continue;
        }
      bool   buy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      if(sl == 0.0 || (buy && sl >= open) || (!buy && sl <= open))
         continue;                                   // no stop, or already at break-even
      double risk  = MathAbs(open - sl);
      double price = buy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double gain  = buy ? price - open : open - price;
      if(gain < risk * InpBreakEvenRR)
         continue;
      double newSL = RoundToTick(buy ? open + risk * InpBreakEvenLockR : open - risk * InpBreakEvenLockR);
      double stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      if((buy && newSL > price - stops) || (!buy && newSL < price + stops))
         continue;
      if(g_trade.PositionModify(ticket, newSL, tp))
         Note("stop moved to break-even on #" + IntegerToString((long)ticket), true);
     }
  }

//+------------------------------------------------------------------+
//| Session tracking and the break / reversal state machine          |
//+------------------------------------------------------------------+
// Finds the most recent session that has fully ended before "now" and has bars.
bool FindLastSession(const SSession &S, const datetime now, datetime &rs, datetime &re, double &hi, double &lo)
  {
   datetime day = now - now % 86400;
   for(int k = 0; k < 10; k++)
     {
      rs = day - k * 86400 + S.startMin * 60;
      re = rs + S.durMin * 60;
      if(re > now)
         continue;
      MqlRates r[];
      int n = CopyRates(_Symbol, g_tf, rs, re - 1, r);
      if(n < MathMax(InpMinSessionBars, 1))
         continue;                                   // weekend / holiday / too little history
      hi = r[0].high;
      lo = r[0].low;
      for(int i = 1; i < n; i++)
        {
         hi = MathMax(hi, r[i].high);
         lo = MathMin(lo, r[i].low);
        }
      return true;
     }
   return false;
  }

// Feeds one closed bar to both sides of a session range. "live" bars may trade,
// older bars only rebuild the state after a restart.
void ProcessBar(SSession &S, const MqlRates &bar, const bool live)
  {
   double range = S.hi - S.lo;
   for(int side = 0; side < 2; side++)
     {
      if(S.state[side] == SS_SPENT)
         continue;
      bool   high  = (side == SS_HIGH);
      double level = high ? S.hi : S.lo;
      string tag   = S.name + (high ? " high " : " low ") + PriceStr(level);

      if(S.state[side] == SS_ARMED)
        {
         double probe = (InpBreakMode == SS_BREAK_CLOSE) ? bar.close : (high ? bar.high : bar.low);
         double brkBuf = Dist(InpBreakBufferPoints, InpBreakBufferATR);
         bool broke = high ? probe > level + brkBuf : probe < level - brkBuf;
         if(!broke)
            continue;
         S.state[side] = SS_BROKEN;
         S.bars[side]  = 0;
         S.ext[side]   = high ? bar.high : bar.low;
         if(live)
            Note(tag + " broken, waiting for the reversal");
        }
      else
        {
         S.bars[side]++;
         S.ext[side] = high ? MathMax(S.ext[side], bar.high) : MathMin(S.ext[side], bar.low);
        }

      // A break that runs too far is a real breakout: stand aside.
      double depth = MathAbs(S.ext[side] - level);
      if(InpMaxSweepPercent > 0.0 && depth > range * InpMaxSweepPercent / 100.0)
        {
         S.state[side] = SS_SPENT;
         if(live)
            Note(tag + " breakout ran too far, no reversal trade");
         continue;
        }

      double reBuf = Dist(InpReentryBufferPoints, InpReentryBufferATR);
      bool back = high ? bar.close < level - reBuf : bar.close > level + reBuf;
      if(back)
        {
         S.state[side] = SS_SPENT;                   // one reversal per side per session range
         if(live)
           {
            bool traded = OpenReversal(S, side, S.ext[side]);
            DrawSignal(S, side, bar.time, high ? bar.high : bar.low, traded);
            if(InpAlerts)
               Alert(SS_NAME, " ", _Symbol, ": ", tag, " break failed -> ", high ? "SELL" : "BUY",
                     traded ? "" : " (not traded)");
           }
         continue;
        }
      if(S.bars[side] >= InpMaxBarsOutside)
        {
         S.state[side] = SS_SPENT;
         if(live)
            Note(tag + " break held for " + IntegerToString(InpMaxBarsOutside) + " bars, no reversal trade");
        }
     }
  }

void UpdateSession(SSession &S, const datetime now, const datetime lastClosed)
  {
   if(!S.enabled)
      return;
   datetime rs, re;
   double hi, lo;
   if(!FindLastSession(S, now, rs, re, hi, lo))
      return;
   if(rs != S.rs)
     {
      S.rs = rs;
      S.re = re;
      S.hi = hi;
      S.lo = lo;
      S.expiry = (InpRangeValidHours > 0) ? re + InpRangeValidHours * 3600 : rs + 86400;
      double size = (hi - lo) / _Point;
      S.valid = !((InpMinRangePoints > 0 && size < InpMinRangePoints) ||
                  (InpMaxRangePoints > 0 && size > InpMaxRangePoints));
      for(int side = 0; side < 2; side++)
        {
         S.state[side] = S.valid ? SS_ARMED : SS_SPENT;
         S.bars[side]  = 0;
         S.ext[side]   = 0.0;
        }
      S.lastBar = re - 1;
      DrawSession(S);
      Note(S.name + " range " + PriceStr(lo) + " - " + PriceStr(hi) + " (" + DoubleToString(size, 0) + " points)"
           + (S.valid ? "" : " rejected by the size filter"));
     }
   if(!S.valid || S.lastBar >= lastClosed)
      return;
   MqlRates r[];
   int n = CopyRates(_Symbol, g_tf, S.lastBar + 1, lastClosed, r);
   for(int i = 0; i < n; i++)
     {
      if(r[i].time <= S.lastBar || r[i].time > lastClosed)
         continue;
      S.lastBar = r[i].time;
      if(r[i].time >= S.expiry)
         continue;
      ProcessBar(S, r[i], r[i].time == lastClosed);
     }
  }

string StateText(const int state)
  {
   if(state == SS_ARMED)
      return "armed";
   if(state == SS_BROKEN)
      return "BROKEN - waiting for reversal";
   return "done";
  }

void Dashboard()
  {
   if(!InpDashboard)
      return;
   datetime now = TimeCurrent();
   string text = SS_NAME + "  " + _Symbol + " " + EnumToString(g_tf) + "   daily ATR "
                 + (g_atr > 0.0 ? PriceStr(g_atr) : "not ready (point buffers only)") + "\n";
   for(int i = 0; i < SS_SESSIONS; i++)
     {
      if(!g_s[i].enabled)
         continue;
      text += g_s[i].name + ": ";
      if(g_s[i].rs == 0)
         text += "no completed session yet\n";
      else
         if(!g_s[i].valid)
            text += "range rejected by the size filter\n";
         else
            if(now >= g_s[i].expiry)
               text += "range expired\n";
            else
               text += "high " + PriceStr(g_s[i].hi) + " [" + StateText(g_s[i].state[SS_HIGH]) + "]   low "
                       + PriceStr(g_s[i].lo) + " [" + StateText(g_s[i].state[SS_LOW]) + "]\n";
     }
   text += g_lastNote;
   Comment(text);
  }

//+------------------------------------------------------------------+
//| Event handlers                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_tf = (InpSignalTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : InpSignalTF;
   if(PeriodSeconds(g_tf) > 3600)
      Print(SS_NAME, ": signal timeframe ", EnumToString(g_tf), " is coarse for session ranges; M5 - M30 works best");

   bool ok = SetupSession(0, "Asia", InpAsiaEnable, InpAsiaStart, InpAsiaEnd, clrGoldenrod);
   ok = SetupSession(1, "London", InpLondonEnable, InpLondonStart, InpLondonEnd, clrSteelBlue) && ok;
   ok = SetupSession(2, "NewYork", InpNYEnable, InpNYStart, InpNYEnd, clrIndianRed) && ok;
   if(!ok)
      return INIT_PARAMETERS_INCORRECT;
   if(!InpAsiaEnable && !InpLondonEnable && !InpNYEnable)
     {
      Print(SS_NAME, ": no session is enabled");
      return INIT_PARAMETERS_INCORRECT;
     }
   g_closeMin = -1;
   if(InpCloseTime != "")
     {
      g_closeMin = ParseHHMM(InpCloseTime);
      if(g_closeMin < 0)
        {
         Print(SS_NAME, ": bad InpCloseTime '", InpCloseTime, "' (use HH:MM)");
         return INIT_PARAMETERS_INCORRECT;
        }
     }
   if(InpMaxBarsOutside < 1 || InpMaxOpenPositions < 1)
     {
      Print(SS_NAME, ": InpMaxBarsOutside and InpMaxOpenPositions must be at least 1");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   if(InpDeviationPoints > 0)
      g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_atrHandle = iATR(_Symbol, PERIOD_D1, MathMax(InpATRPeriod, 1));
   if(g_atrHandle == INVALID_HANDLE)
      Print(SS_NAME, ": daily ATR is unavailable, only the point-based buffers are used");
   g_atr = 0.0;
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_lastBar = 0;
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(InpDashboard)
      Comment("");
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   g_atrHandle = INVALID_HANDLE;
   if(!MQLInfoInteger(MQL_TESTER))
      ObjectsDeleteAll(0, SS_PREFIX);
  }

void OnTick()
  {
   ManagePositions();

   datetime now = iTime(_Symbol, g_tf, 0);
   if(now == 0 || now == g_lastBar)
      return;
   datetime lastClosed = iTime(_Symbol, g_tf, 1);
   if(lastClosed == 0)
      return;
   g_lastBar = now;
   RefreshATR();

   for(int i = 0; i < SS_SESSIONS; i++)
      UpdateSession(g_s[i], now, lastClosed);
   Dashboard();
  }
//+------------------------------------------------------------------+
