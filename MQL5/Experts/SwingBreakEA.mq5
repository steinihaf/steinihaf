//+------------------------------------------------------------------+
//|                                                 SwingBreakEA.mq5 |
//|  PROTOTYPE. Trades the last swing high / low of the signal        |
//|  timeframe in one of two ways:                                    |
//|    Break: a bar closes clearly beyond the level -> trade WITH     |
//|           the break, stop back behind the level.                  |
//|    Sweep: price pokes beyond the level and a bar closes back      |
//|           inside -> trade the REVERSAL, stop beyond the poke.     |
//|  A swing high / low is confirmed once price has moved away from   |
//|  it by InpSwingATR x daily ATR (a zigzag). All distances scale    |
//|  with the daily ATR, so they adapt to the symbol and volatility.  |
//+------------------------------------------------------------------+
#property copyright   "steinihaf"
#property link        "https://github.com/steinihaf/steinihaf"
#property version     "0.10"
#property description "Prototype: trade the break (or the failed break) of the last swing high / low."

#include <Trade/Trade.mqh>

#define SB_NAME      "SwingBreakEA"
#define SB_PREFIX    "SWB_"           // prefix of every chart object this EA creates
#define SB_HIGH      0
#define SB_LOW       1

enum ENUM_SB_STATE
  {
   SB_ARMED  = 0,                     // level untouched
   SB_BROKEN = 1,                     // Sweep mode: price is beyond the level, waiting for the close back inside
   SB_SPENT  = 2                      // traded or given up
  };

enum ENUM_SB_MODE
  {
   SB_MODE_BREAK = 0,                 // Break: trade with a confirmed break of the level
   SB_MODE_SWEEP = 1                  // Sweep: trade the reversal after a failed break
  };

enum ENUM_SB_PERMIT
  {
   SB_PERMIT_BOTH = 0,                // Buy and sell
   SB_PERMIT_BUY  = 1,                // Buy only
   SB_PERMIT_SELL = 2                 // Sell only
  };

enum ENUM_SB_LOT
  {
   SB_LOT_FIXED = 0,                  // Fixed lot
   SB_LOT_RISK  = 1                   // Risk percent of balance (from stop-loss distance)
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Swings ==="
input ENUM_TIMEFRAMES InpSignalTF = PERIOD_H1;        // Signal timeframe (Current = chart)
input int    InpATRPeriod         = 14;               // Daily ATR period
input double InpSwingATR          = 0.5;              // Swing size: a high / low counts once price moved N x daily ATR away (M15 0.25, H1 0.5, H4 1.0)
input int    InpHistoryBars       = 500;              // Bars read at start to find the current swings

input group "=== Entry ==="
input ENUM_SB_MODE InpMode        = SB_MODE_BREAK;    // What to trade
input double InpBreakConfirm      = 0.5;              // Break mode: bar must close beyond the level by N x swing size
input double InpBreakBufferATR    = 0.01;             // Sweep mode: price must exceed the level by N x daily ATR
input double InpReentryBufferATR  = 0.0;              // Sweep mode: bar must close back inside by N x daily ATR
input int    InpMaxBarsOutside    = 6;                // Sweep mode: reversal must come within N bars of the break
input double InpMaxOvershoot      = 1.0;              // Sweep mode: no trade if price ran more than N x swing size beyond the level (0 = off)
input ENUM_SB_PERMIT InpPermit    = SB_PERMIT_BOTH;   // Allowed directions

input group "=== Risk ==="
input ENUM_SB_LOT InpLotMode      = SB_LOT_RISK;      // Lot sizing
input double InpFixedLot          = 0.01;             // Fixed lot
input double InpRiskPercent       = 0.5;              // Risk per trade (% of balance)
input double InpSLBufferATR       = 0.03;             // Stop buffer: N x daily ATR behind the level (Break) or beyond the poke (Sweep)
input double InpMinSLATR          = 0.06;             // Minimum stop distance: N x daily ATR
input double InpMaxSLATR          = 0.0;              // Skip the trade if the stop is wider than N x daily ATR (0 = off)
input double InpTPRR              = 2.0;              // Take-profit as a multiple of the stop distance (0 = none)
input double InpBreakEvenRR       = 1.0;              // Move stop to break-even after N x R profit (0 = off)
input double InpBreakEvenLockR    = 0.05;             // Break-even lock: stop goes N x R beyond the entry

input group "=== Limits ==="
input double InpMaxSpreadPercentOfSL = 15.0;          // Max spread as % of the stop distance (0 = off)
input int    InpMaxOpenPositions  = 1;                // Open positions at once (this EA, this symbol)
input int    InpMaxTradesPerDay   = 3;                // Max new trades per day (0 = off)
input double InpMaxDailyLossPercent = 2.0;            // Stop for the day after losing N% of balance (0 = off)
input string InpCloseTime         = "";               // Close all and stop trading at HH:MM server time (empty = off)

input group "=== General ==="
input long   InpMagic             = 20261126;         // Magic number
input int    InpDeviationPoints   = 0;                // Max slippage (points, 0 = auto: 2 x spread, at least 10)
input bool   InpDraw              = true;             // Draw swing levels and signals
input bool   InpAlerts            = false;            // Alert on every signal
input bool   InpDashboard         = true;             // Show status on the chart
input bool   InpVerbose           = false;            // Log skipped signals and state changes

//+------------------------------------------------------------------+
//| State                                                            |
//+------------------------------------------------------------------+
struct SLevel
  {
   bool              active;          // a swing has been confirmed on this side
   double            price;           // the swing high / low
   datetime          pivot;           // time of the bar that made it
   int               state;           // ENUM_SB_STATE
   int               bars;            // Sweep mode: bars since the break
   double            ext;             // Sweep mode: extreme reached beyond the level
  };

SLevel          g_lv[2];
CTrade          g_trade;
ENUM_TIMEFRAMES g_tf        = PERIOD_H1;
datetime        g_lastBar   = 0;      // open time of the bar in progress
datetime        g_lastDone  = 0;      // last closed bar fed to the logic
bool            g_ready     = false;  // history has been replayed
int             g_closeMin  = -1;
int             g_atrHandle = INVALID_HANDLE;
double          g_atr       = 0.0;    // last completed daily ATR
string          g_lastNote  = "";
// zigzag: direction of the leg in progress and its running extremes
int             g_dir       = 0;
double          g_ehi       = 0.0;
double          g_elo       = 0.0;
datetime        g_ehiT      = 0;
datetime        g_eloT      = 0;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
void Note(const string msg, const bool always = false)
  {
   g_lastNote = TimeToString(TimeCurrent(), TIME_MINUTES) + "  " + msg;
   if(always || InpVerbose)
      Print(SB_NAME, ": ", msg);
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

// Today's entries and closed profit of this EA on this symbol.
void DayStats(int &trades, double &profit)
  {
   trades = 0;
   profit = 0.0;
   datetime now = TimeCurrent();
   datetime day = now - now % 86400;
   if(!HistorySelect(day, now + 60))
      return;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
         trades++;
      else
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
   if(InpLotMode == SB_LOT_RISK)
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
string LevelName(const int side, const datetime pivot)
  {
   return SB_PREFIX + (side == SB_HIGH ? "hi_" : "lo_") + IntegerToString((long)pivot);
  }

void DrawLevel(const int side)
  {
   if(!InpDraw || !g_lv[side].active)
      return;
   string name = LevelName(side, g_lv[side].pivot);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, g_lv[side].pivot, g_lv[side].price,
                   g_lv[side].pivot + PeriodSeconds(g_tf), g_lv[side].price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, side == SB_HIGH ? clrTomato : clrDodgerBlue);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, (side == SB_HIGH ? "swing high " : "swing low ") + PriceStr(g_lv[side].price));
  }

// An old level stops being drawn as a ray once a newer swing replaces it.
void RetireLevel(const int side, const datetime until)
  {
   if(!InpDraw || !g_lv[side].active)
      return;
   string name = LevelName(side, g_lv[side].pivot);
   if(ObjectFind(0, name) < 0)
      return;
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectMove(0, name, 1, until, g_lv[side].price);
  }

void DrawSignal(const bool sell, const datetime t, const double price, const bool traded)
  {
   if(!InpDraw)
      return;
   string name = SB_PREFIX + "sig_" + IntegerToString((long)t) + (sell ? "_S" : "_B");
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, sell ? OBJ_ARROW_SELL : OBJ_ARROW_BUY, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, traded ? (sell ? clrTomato : clrDodgerBlue) : clrGray);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| Trade execution                                                  |
//+------------------------------------------------------------------+
// stopRef = the price the stop goes behind: the level itself (Break) or the extreme of the poke (Sweep).
bool OpenTrade(const bool sell, const double stopRef, const string comment, const string what)
  {
   if((sell && InpPermit == SB_PERMIT_BUY) || (!sell && InpPermit == SB_PERMIT_SELL))
     { Note(what + " skipped: direction not allowed"); return false; }

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(g_closeMin >= 0 && dt.hour * 60 + dt.min >= g_closeMin)
     { Note(what + " skipped: after close time"); return false; }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     { Note(what + " skipped: algo trading is disabled", true); return false; }
   if(g_atr <= 0.0)
     { Note(what + " skipped: daily ATR is not available yet", true); return false; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;

   if(CountPositions() >= InpMaxOpenPositions)
     { Note(what + " skipped: max open positions"); return false; }

   int trades; double dayProfit;
   DayStats(trades, dayProfit);
   if(InpMaxTradesPerDay > 0 && trades >= InpMaxTradesPerDay)
     { Note(what + " skipped: max trades per day"); return false; }
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(InpMaxDailyLossPercent > 0.0 && dayProfit <= -(balance - dayProfit) * InpMaxDailyLossPercent / 100.0)
     { Note(what + " skipped: daily loss limit reached"); return false; }

   // A sell stop is hit by the ask, so add the spread on that side.
   double entry = sell ? bid : ask;
   double slBuf = g_atr * InpSLBufferATR;
   double sl    = sell ? stopRef + slBuf + spread : stopRef - slBuf;
   double minDist = MathMax(g_atr * InpMinSLATR,
                            (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point + spread);
   if(MathAbs(sl - entry) < minDist || (sell && sl <= entry) || (!sell && sl >= entry))
      sl = sell ? entry + minDist : entry - minDist;
   sl = RoundToTick(sl);
   double risk = MathAbs(sl - entry);
   if(InpMaxSLATR > 0.0 && risk > g_atr * InpMaxSLATR)
     { Note(what + " skipped: stop " + DoubleToString(risk / _Point, 0) + " points is too wide"); return false; }
   if(InpMaxSpreadPercentOfSL > 0.0 && spread > risk * InpMaxSpreadPercentOfSL / 100.0)
     { Note(what + " skipped: spread is " + DoubleToString(spread / risk * 100.0, 0) + "% of the stop"); return false; }

   double tp = 0.0;
   if(InpTPRR > 0.0)
      tp = RoundToTick(sell ? entry - risk * InpTPRR : entry + risk * InpTPRR);

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
//| Swing levels and the entry logic                                 |
//+------------------------------------------------------------------+
void Signal(const int side, const bool sell, const double stopRef, const MqlRates &bar, const bool live, const string why)
  {
   if(!live)
      return;                                        // history only rebuilds the state
   string what = (side == SB_HIGH ? "swing high " : "swing low ") + PriceStr(g_lv[side].price) + " " + why
                 + " -> " + (sell ? "SELL" : "BUY");
   string comment = (InpMode == SB_MODE_BREAK ? "SWB break " : "SWB sweep ") + (side == SB_HIGH ? "H" : "L");
   bool traded = OpenTrade(sell, stopRef, comment, what);
   DrawSignal(sell, bar.time, sell ? bar.high : bar.low, traded);
   if(InpAlerts)
      Alert(SB_NAME, " ", _Symbol, ": ", what, traded ? "" : " (not traded)");
  }

// Feeds one closed bar to one level. "live" bars may trade.
void ProcessLevel(const int side, const MqlRates &bar, const bool live)
  {
   if(!g_lv[side].active || g_lv[side].state == SB_SPENT)
      return;
   bool   high  = (side == SB_HIGH);
   double level = g_lv[side].price;
   double swing = g_atr * InpSwingATR;

   if(InpMode == SB_MODE_BREAK)
     {
      // Trade with the break once a bar has closed clearly beyond the level; stop back behind the level.
      double need = swing * InpBreakConfirm;
      bool through = high ? bar.close > level + need : bar.close < level - need;
      if(!through)
         return;
      g_lv[side].state = SB_SPENT;
      Signal(side, !high, level, bar, live, "broken");
      return;
     }

   // Sweep mode: break by a wick, then a close back inside the level.
   if(g_lv[side].state == SB_ARMED)
     {
      double brkBuf = g_atr * InpBreakBufferATR;
      bool broke = high ? bar.high > level + brkBuf : bar.low < level - brkBuf;
      if(!broke)
         return;
      g_lv[side].state = SB_BROKEN;
      g_lv[side].bars  = 0;
      g_lv[side].ext   = high ? bar.high : bar.low;
     }
   else
     {
      g_lv[side].bars++;
      g_lv[side].ext = high ? MathMax(g_lv[side].ext, bar.high) : MathMin(g_lv[side].ext, bar.low);
     }

   double over = MathAbs(g_lv[side].ext - level);
   if(InpMaxOvershoot > 0.0 && over > swing * InpMaxOvershoot)
     {
      g_lv[side].state = SB_SPENT;                   // ran too far: a real break, not a sweep
      return;
     }
   double reBuf = g_atr * InpReentryBufferATR;
   bool back = high ? bar.close < level - reBuf : bar.close > level + reBuf;
   if(back)
     {
      g_lv[side].state = SB_SPENT;
      Signal(side, high, g_lv[side].ext, bar, live, "swept");
      return;
     }
   if(g_lv[side].bars >= InpMaxBarsOutside)
      g_lv[side].state = SB_SPENT;
  }

void SetLevel(const int side, const double price, const datetime pivot, const datetime confirmed)
  {
   RetireLevel(side, confirmed);
   g_lv[side].active = true;
   g_lv[side].price  = price;
   g_lv[side].pivot  = pivot;
   g_lv[side].state  = SB_ARMED;
   g_lv[side].bars   = 0;
   g_lv[side].ext    = 0.0;
   DrawLevel(side);
  }

// Zigzag: a high is confirmed once price has fallen InpSwingATR x daily ATR from it, and the reverse for a low.
void UpdateSwings(const MqlRates &bar)
  {
   double thr = g_atr * InpSwingATR;
   if(thr <= 0.0)
      return;
   if(g_dir == 0)
     {
      if(g_ehiT == 0 || bar.high > g_ehi) { g_ehi = bar.high; g_ehiT = bar.time; }
      if(g_eloT == 0 || bar.low < g_elo)  { g_elo = bar.low;  g_eloT = bar.time; }
      if(g_ehi - bar.low >= thr && bar.high < g_ehi)
        {
         SetLevel(SB_HIGH, g_ehi, g_ehiT, bar.time);
         g_dir = -1; g_elo = bar.low; g_eloT = bar.time;
        }
      else
         if(bar.high - g_elo >= thr && bar.low > g_elo)
           {
            SetLevel(SB_LOW, g_elo, g_eloT, bar.time);
            g_dir = 1; g_ehi = bar.high; g_ehiT = bar.time;
           }
      return;
     }
   if(g_dir == 1)
     {
      if(bar.high > g_ehi) { g_ehi = bar.high; g_ehiT = bar.time; }
      else
         if(g_ehi - bar.low >= thr)
           {
            SetLevel(SB_HIGH, g_ehi, g_ehiT, bar.time);
            g_dir = -1; g_elo = bar.low; g_eloT = bar.time;
           }
      return;
     }
   if(bar.low < g_elo) { g_elo = bar.low; g_eloT = bar.time; }
   else
      if(bar.high - g_elo >= thr)
        {
         SetLevel(SB_LOW, g_elo, g_eloT, bar.time);
         g_dir = 1; g_ehi = bar.high; g_ehiT = bar.time;
        }
  }

void ProcessBar(const MqlRates &bar, const bool live)
  {
   ProcessLevel(SB_HIGH, bar, live);                 // levels confirmed before this bar
   ProcessLevel(SB_LOW, bar, live);
   UpdateSwings(bar);                                // this bar may confirm a new swing for the next bars
   g_lastDone = bar.time;
  }

string StateText(const int side)
  {
   if(!g_lv[side].active)
      return "none yet";
   string s = PriceStr(g_lv[side].price);
   if(g_lv[side].state == SB_ARMED)
      return s + " [armed]";
   if(g_lv[side].state == SB_BROKEN)
      return s + " [BROKEN - waiting for the close back inside]";
   return s + " [done]";
  }

void Dashboard()
  {
   if(!InpDashboard)
      return;
   string text = SB_NAME + " (prototype)  " + _Symbol + " " + EnumToString(g_tf) + "   mode "
                 + (InpMode == SB_MODE_BREAK ? "Break" : "Sweep") + "   daily ATR "
                 + (g_atr > 0.0 ? PriceStr(g_atr) : "not ready") + "   swing size "
                 + PriceStr(g_atr * InpSwingATR) + "\n";
   text += "last swing high " + StateText(SB_HIGH) + "\n";
   text += "last swing low  " + StateText(SB_LOW) + "\n";
   text += g_lastNote;
   Comment(text);
  }

//+------------------------------------------------------------------+
//| Event handlers                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_tf = (InpSignalTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : InpSignalTF;
   g_closeMin = -1;
   if(InpCloseTime != "")
     {
      g_closeMin = ParseHHMM(InpCloseTime);
      if(g_closeMin < 0)
        {
         Print(SB_NAME, ": bad InpCloseTime '", InpCloseTime, "' (use HH:MM)");
         return INIT_PARAMETERS_INCORRECT;
        }
     }
   if(InpSwingATR <= 0.0 || InpBreakConfirm < 0.0 || InpMaxBarsOutside < 1 || InpMaxOpenPositions < 1 || InpHistoryBars < 10)
     {
      Print(SB_NAME, ": InpSwingATR must be above 0, InpBreakConfirm at least 0, InpMaxBarsOutside and ",
            "InpMaxOpenPositions at least 1, InpHistoryBars at least 10");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   if(InpDeviationPoints > 0)
      g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_atrHandle = iATR(_Symbol, PERIOD_D1, MathMax(InpATRPeriod, 1));
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print(SB_NAME, ": the daily ATR indicator could not be created");
      return INIT_FAILED;
     }
   g_atr = 0.0;
   g_lastBar = 0;
   g_lastDone = 0;
   g_ready = false;
   g_dir = 0;
   g_ehiT = 0;
   g_eloT = 0;
   for(int side = 0; side < 2; side++)
     {
      g_lv[side].active = false;
      g_lv[side].state  = SB_SPENT;
     }
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
      ObjectsDeleteAll(0, SB_PREFIX);
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
   RefreshATR();
   if(g_atr <= 0.0)
      return;                                        // try again on the next tick
   MqlRates r[];
   if(!g_ready)
     {
      // Rebuild the swings from history; nothing is traded on these bars.
      int n = CopyRates(_Symbol, g_tf, 1, InpHistoryBars, r);
      if(n < 10)
         return;
      for(int i = 0; i < n; i++)
         ProcessBar(r[i], false);
      g_ready = true;
      g_lastBar = now;
      Note("ready: " + IntegerToString(n) + " bars of history read", true);
      Dashboard();
      return;
     }
   g_lastBar = now;
   int n = CopyRates(_Symbol, g_tf, g_lastDone + 1, lastClosed, r);
   for(int i = 0; i < n; i++)
     {
      if(r[i].time <= g_lastDone || r[i].time > lastClosed)
         continue;
      ProcessBar(r[i], r[i].time == lastClosed);     // only the bar that just closed may trade
     }
   Dashboard();
  }
//+------------------------------------------------------------------+
