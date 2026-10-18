//+------------------------------------------------------------------+
//|                                                         good.mq5 |
//|            mqlcheck sample: a small EA that must pass the check  |
//+------------------------------------------------------------------+
#property copyright   "mqlcheck"
#property link        "https://github.com/steinihaf/steinihaf"
#property version     "1.00"
#property description "Exercises the MQL5 constructs the mqlcheck shim must accept."
#property strict

#include <Trade\Trade.mqh>
#include <Trade/PositionInfo.mqh>

#define SAMPLE_NAME   "mqlcheck-sample"
#define SAMPLE_PREFIX "MQC_"
#define SAMPLE_MAX    8

//--- user enums used as inputs
enum ENUM_SAMPLE_MODE
  {
   SAMPLE_MODE_TOUCH   = 0,   // Touch
   SAMPLE_MODE_PENDING = 1    // Pending orders
  };

input group "=== General ==="
input ENUM_SAMPLE_MODE InpMode      = SAMPLE_MODE_TOUCH;   // Entry mode
input ENUM_TIMEFRAMES  InpTF        = PERIOD_H1;           // Signal timeframe
input ENUM_MA_METHOD   InpMAMethod  = MODE_EMA;            // MA method
input double           InpLots      = 0.10;                // Lots
input int              InpStopPts   = 300;                 // Stop-loss (points)
input ulong            InpMagic     = 777001;              // Magic number
sinput string          InpComment   = "mqc";               // Order comment
input color            InpLineColor = clrDodgerBlue;       // Line color
input datetime         InpStart     = D'2024.01.01 00:00'; // Start date
input bool             InpUseFile   = false;               // Write a log file
input group "=== Custom indicator ==="
input string           InpIndName   = "Examples\\ZigZag";  // Indicator path
input int              InpDepth     = 12;                  // ZigZag depth

//--- structures: string members, methods, struct assignment
struct SLevel
  {
   string   name;
   double   price;
   datetime time;
   color    clr;
   int      hits;
   void     Clear() { name = ""; price = 0.0; time = 0; clr = clrWhite; hits = 0; }
   void     CopyStateFrom(const SLevel &o) { hits = o.hits; }
  };

struct SStats
  {
   int    trades;
   double profit;
   double history[SAMPLE_MAX];   // fixed array in a struct
  };

//--- globals, dynamic and fixed arrays
CTrade          g_trade;
CPositionInfo   g_pos;
SLevel          g_levels[];
double          g_buf[], g_buf2[];
string          g_names[];
int             g_fixed[16];
double          g_grid[3][4];
datetime        g_times[];
SStats          g_stats;
int             g_handle = INVALID_HANDLE;
int             g_atr    = INVALID_HANDLE;
MqlTick         g_tick;
const string    g_labels[3] = { "DVAH", "DPOC", "DVAL" };

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string PriceStr(const double p)
  {
   return(DoubleToString(p, _Digits));
  }

void AddLevel(SLevel &arr[], const SLevel &L)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = L;
  }

int FindLevel(const SLevel &arr[], const string name)
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i].name == name)
         return(i);
   return(-1);
  }

string ModeName(const ENUM_SAMPLE_MODE mode)
  {
   string s = EnumToString(mode);
   StringReplace(s, "SAMPLE_MODE_", "");
   StringToLower(s);
   return(s);
  }

void SplitList(const string list, string &out[])
  {
   ArrayResize(out, 0);
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

//+------------------------------------------------------------------+
//| Object scanning                                                  |
//+------------------------------------------------------------------+
void ScanObjects(SLevel &out[])
  {
   ArrayResize(out, 0);
   for(int k = 0; k < 2; k++)
     {
      int type  = (k == 0) ? OBJ_HLINE : OBJ_TREND;
      int total = ObjectsTotal(0, 0, type);
      for(int i = 0; i < total; i++)
        {
         string name = ObjectName(0, i, 0, type);
         if(name == "" || StringFind(name, SAMPLE_PREFIX) == 0)
            continue;
         if(ObjectGetInteger(0, name, OBJPROP_HIDDEN) != 0)
            continue;
         color c = (color)ObjectGetInteger(0, name, OBJPROP_COLOR);
         SLevel L;
         L.Clear();
         L.name = name;
         L.clr  = c;
         L.time = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
         if(k == 0)
            L.price = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
         else
           {
            double p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
            double p2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
            L.price = ObjectGetValueByTime(0, name, TimeCurrent(), 0);
            if(L.price <= 0.0)
               L.price = (p1 + p2) / 2.0;
           }
         if(L.price <= 0.0)
            continue;
         int old = FindLevel(g_levels, name);
         if(old >= 0)
            L.CopyStateFrom(g_levels[old]);
         AddLevel(out, L);
        }
     }
  }

void DrawLevel(const SLevel &L)
  {
   string name = SAMPLE_PREFIX + L.name;
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, L.price))
         return;
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
     }
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, L.price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, (L.hits > 0) ? clrLime : InpLineColor);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, L.name + " " + PriceStr(L.price) + " hits=" + (string)L.hits);
   string tl = SAMPLE_PREFIX + "TL_" + L.name;
   ObjectCreate(0, tl, OBJ_TREND, 0, L.time, L.price, TimeCurrent(), L.price);
   ObjectMove(0, tl, 1, TimeCurrent(), L.price);
  }

//+------------------------------------------------------------------+
//| Trading                                                          |
//+------------------------------------------------------------------+
bool OurPosition()
  {
   return(PositionGetInteger(POSITION_MAGIC) == (long)InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol);
  }

int CountOpen(int &buys, int &sells)
  {
   buys = 0;
   sells = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !OurPosition())
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         buys++;
      else
         sells++;
     }
   return(buys + sells);
  }

bool PlacePending(SLevel &L, const int dir)
  {
   double off   = InpStopPts * _Point;
   double price = NormalizeDouble(dir > 0 ? L.price + off : L.price - off, _Digits);
   double sl    = dir > 0 ? price - 2 * off : price + 2 * off;
   double tp    = dir > 0 ? price + 3 * off : price - 3 * off;
   datetime exp = TimeCurrent() + (datetime)(24 * PeriodSeconds(InpTF));
   ENUM_ORDER_TYPE_TIME tt = (exp > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
   string comment = InpComment + "|" + L.name;
   bool sent = (dir > 0) ? g_trade.BuyStop(InpLots, price, _Symbol, sl, tp, tt, exp, comment)
               : g_trade.SellLimit(InpLots, price, _Symbol, sl, tp, tt, exp, comment);
   uint rc = g_trade.ResultRetcode();
   if(!sent || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED))
     {
      PrintFormat("%s: pending on %s failed: %u %s", SAMPLE_NAME, L.name, rc, g_trade.ResultRetcodeDescription());
      return(false);
     }
   L.hits++;
   Print(SAMPLE_NAME, ": placed ", EnumToString(dir > 0 ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_LIMIT),
         " #", IntegerToString((long)g_trade.ResultOrder()), " @ ", PriceStr(price));
   return(true);
  }

bool OpenMarket(SLevel &L, const int dir)
  {
   double entry = dir > 0 ? g_tick.ask : g_tick.bid;
   double sl    = dir > 0 ? entry - InpStopPts * _Point : entry + InpStopPts * _Point;
   double margin = 0.0;
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcMargin(type, _Symbol, InpLots, entry, margin) && margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
      return(false);
   bool ok = (dir > 0) ? g_trade.Buy(InpLots, _Symbol, 0.0, sl, 0.0, InpComment)
             : g_trade.Sell(InpLots, _Symbol, 0.0, sl, 0.0, InpComment);
   string msg = (dir > 0 ? "BUY " : "SELL ") + DoubleToString(InpLots, 2) + " on " + L.name
                + " (" + (ok ? "ok" : "failed") + ", rc=" + IntegerToString((int)g_trade.ResultRetcode()) + ")";
   Print(msg);
   if(ok)
     {
      L.hits++;
      g_stats.trades++;
      if(g_stats.trades < SAMPLE_MAX)
         g_stats.history[g_stats.trades] = entry;
     }
   return(ok);
  }

void ManagePositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i) || g_pos.Magic() != (long)InpMagic || g_pos.Symbol() != _Symbol)
         continue;
      bool   isBuy = (g_pos.PositionType() == POSITION_TYPE_BUY);
      double open  = g_pos.PriceOpen();
      double sl    = g_pos.StopLoss();
      double cur   = isBuy ? g_tick.bid : g_tick.ask;
      double be    = isBuy ? open + 20 * _Point : open - 20 * _Point;
      if(MathAbs(cur - open) > InpStopPts * _Point && (isBuy ? sl < be : (sl == 0.0 || sl > be)))
         if(!g_trade.PositionModify(g_pos.Ticket(), be, g_pos.TakeProfit()))
            Print("modify #", g_pos.Ticket(), " failed: ", g_trade.ResultRetcodeDescription());
     }
   if(HistorySelect(InpStart, TimeCurrent()))
     {
      g_stats.profit = 0.0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 || HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)InpMagic)
            continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            g_stats.profit += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP);
        }
     }
  }

//+------------------------------------------------------------------+
//| Files and terminal global variables                              |
//+------------------------------------------------------------------+
void WriteLog(const string line)
  {
   if(!InpUseFile)
      return;
   string fname = SAMPLE_NAME + "_" + _Symbol + ".log";
   int h = FileOpen(fname, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      Print("cannot open ", fname, " error ", GetLastError());
      return;
     }
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), line);
   FileWriteString(h, "\n");
   FileClose(h);
   string gv = SAMPLE_PREFIX + _Symbol + "_count";
   double cnt = GlobalVariableCheck(gv) ? GlobalVariableGet(gv) : 0.0;
   GlobalVariableSet(gv, cnt + 1);
   if(cnt > 1000)
      GlobalVariableDel(gv);
  }

//+------------------------------------------------------------------+
//| Expert event handlers                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetMarginMode();
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   g_trade.SetTypeFilling((filling & SYMBOL_FILLING_FOK) != 0 ? ORDER_FILLING_FOK : ORDER_FILLING_IOC);

   g_atr = iATR(_Symbol, InpTF, 14);
   g_handle = iCustom(_Symbol, InpTF, InpIndName, InpDepth, 5, 3);
   if(g_handle == INVALID_HANDLE || g_atr == INVALID_HANDLE)
     {
      Print(SAMPLE_NAME, ": indicator handle failed (", GetLastError(), ")");
      return(INIT_FAILED);
     }
   ArraySetAsSeries(g_buf, true);
   ArraySetAsSeries(g_times, true);
   ArrayInitialize(g_fixed, 0);
   ArrayInitialize(g_grid, 0.0);
   g_stats.trades = 0;
   g_stats.profit = 0.0;
   SplitList("a;b;c", g_names);
   if(ArraySize(g_names) != 3)
      return(INIT_PARAMETERS_INCORRECT);
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
   EventSetTimer(1);
   Print(SAMPLE_NAME, " initialised on ", _Symbol, " ", EnumToString((ENUM_TIMEFRAMES)_Period), " mode=", ModeName(InpMode));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_handle != INVALID_HANDLE)
      IndicatorRelease(g_handle);
   if(g_atr != INVALID_HANDLE)
      IndicatorRelease(g_atr);
   ObjectsDeleteAll(0, SAMPLE_PREFIX);
   Comment("");
   ChartRedraw();
   Print(SAMPLE_NAME, " removed, reason ", reason);
  }

void OnTick()
  {
   if(!SymbolInfoTick(_Symbol, g_tick))
      return;
   if(CopyBuffer(g_handle, 0, 0, 3, g_buf) < 3 || CopyTime(_Symbol, InpTF, 0, 3, g_times) < 3)
      return;
   double atr[];
   ArraySetAsSeries(atr, true);
   double atrValue = (CopyBuffer(g_atr, 0, 1, 1, atr) == 1) ? atr[0] : 0.0;
   MqlRates rates[];
   if(CopyRates(_Symbol, InpTF, 0, 10, rates) < 10)
      return;
   double zone = MathMax(InpStopPts * _Point, atrValue * 0.5);

   SLevel fresh[];
   ScanObjects(fresh);
   ArrayResize(g_levels, ArraySize(fresh));
   for(int i = 0; i < ArraySize(fresh); i++)
      g_levels[i] = fresh[i];

   int buys = 0, sells = 0;
   int open = CountOpen(buys, sells);
   for(int i = 0; i < ArraySize(g_levels) && open < 2; i++)
     {
      double d = g_tick.bid - g_levels[i].price;
      if(MathAbs(d) > zone)
         continue;
      int dir = (d > 0) ? 1 : -1;
      bool done = (InpMode == SAMPLE_MODE_PENDING) ? PlacePending(g_levels[i], dir) : OpenMarket(g_levels[i], dir);
      if(done)
        {
         open++;
         WriteLog("trade on " + g_levels[i].name + " at " + PriceStr(g_levels[i].price));
        }
      DrawLevel(g_levels[i]);
     }
   ManagePositions();

   string s = SAMPLE_NAME + "  " + _Symbol + "\n";
   s += "levels: " + IntegerToString(ArraySize(g_levels)) + "  open: " + (string)open
        + "  zone: " + DoubleToString(zone / _Point, 0) + " pts  bar: " + TimeToString(g_times[0], TIME_DATE | TIME_MINUTES) + "\n";
   s += "P/L: " + DoubleToString(g_stats.profit, 2) + "  " + (g_stats.profit >= 0 ? "ok" : "drawdown") + "\n";
   for(int i = 0; i < MathMin(ArraySize(g_levels), 5); i++)
      s += "  " + g_labels[i % 3] + " " + PriceStr(g_levels[i].price) + " " + ((g_levels[i].hits > 0) ? "used" : "armed") + "\n";
   Comment(s);
  }

void OnTimer()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   ChartRedraw();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CREATE || id == CHARTEVENT_OBJECT_DELETE || id == CHARTEVENT_OBJECT_DRAG)
      Print("object event ", id, " on ", sparam);
   if(id == CHARTEVENT_CLICK)
      PrintFormat("click at x=%d y=%d", (int)lparam, (int)dparam);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal_type == DEAL_TYPE_BUY)
      Print("deal ", trans.deal, " on ", trans.symbol, " vol ", DoubleToString(trans.volume, 2), " rc ", result.retcode);
  }
//+------------------------------------------------------------------+
