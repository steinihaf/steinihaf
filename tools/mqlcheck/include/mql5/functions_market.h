// mqlcheck: MQL5 built-ins part 2 - series, indicators, objects, chart,
// trading, account, terminal. Inline stubs; only the signatures matter.
// Property/enum parameters are typed int/long on purpose so both enum
// constants and plain integers are accepted (generous).
#pragma once

//---------------------------------------------------------------- trade structs
struct MqlTradeRequest
  {
   ENUM_TRADE_REQUEST_ACTIONS action;
   ulong                      magic;
   ulong                      order;
   string                     symbol;
   double                     volume;
   double                     price;
   double                     stoplimit;
   double                     sl;
   double                     tp;
   ulong                      deviation;
   ENUM_ORDER_TYPE            type;
   ENUM_ORDER_TYPE_FILLING    type_filling;
   ENUM_ORDER_TYPE_TIME       type_time;
   datetime                   expiration;
   string                     comment;
   ulong                      position;
   ulong                      position_by;
  };
struct MqlTradeResult
  {
   uint   retcode;
   ulong  deal;
   ulong  order;
   double volume;
   double price;
   double bid;
   double ask;
   string comment;
   uint   request_id;
   int    retcode_external;
  };
struct MqlTradeCheckResult
  {
   uint   retcode;
   double balance, equity, profit, margin, margin_free, margin_level;
   string comment;
  };
struct MqlTradeTransaction
  {
   ulong                         deal;
   ulong                         order;
   string                        symbol;
   ENUM_TRADE_TRANSACTION_TYPE   type;
   ENUM_ORDER_TYPE               order_type;
   ENUM_ORDER_STATE              order_state;
   ENUM_DEAL_TYPE                deal_type;
   ENUM_ORDER_TYPE_TIME          time_type;
   datetime                      time_expiration;
   double                        price;
   double                        price_trigger;
   double                        price_sl;
   double                        price_tp;
   double                        volume;
   ulong                         position;
   ulong                         position_by;
  };

//---------------------------------------------------------------- timeseries access
inline int      Bars(const string &, int) { return 0; }
inline int      Bars(const string &, int, datetime, datetime) { return 0; }
inline int      iBars(const string &, int) { return 0; }
inline int      iBarShift(const string &, int, datetime, bool = false) { return 0; }
inline datetime iTime(const string &, int, int) { return 0; }
inline double   iOpen(const string &, int, int) { return 0; }
inline double   iHigh(const string &, int, int) { return 0; }
inline double   iLow(const string &, int, int) { return 0; }
inline double   iClose(const string &, int, int) { return 0; }
inline long     iVolume(const string &, int, int) { return 0; }
inline long     iTickVolume(const string &, int, int) { return 0; }
inline long     iRealVolume(const string &, int, int) { return 0; }
inline int      iSpread(const string &, int, int) { return 0; }
inline int      iHighest(const string &, int, int = MODE_HIGH, int = WHOLE_ARRAY, int = 0) { return 0; }
inline int      iLowest(const string &, int, int = MODE_LOW, int = WHOLE_ARRAY, int = 0) { return 0; }
inline long     SeriesInfoInteger(const string &, int, int) { return 0; }
inline bool     SeriesInfoInteger(const string &, int, int, long &) { return true; }

#define MQL_COPY3(NAME) \
   template<MQL_ARR(A)> inline int NAME(const string &, int, int, int, A &) { return 0; } \
   template<MQL_ARR(A)> inline int NAME(const string &, int, datetime, int, A &) { return 0; } \
   template<MQL_ARR(A)> inline int NAME(const string &, int, datetime, datetime, A &) { return 0; }
MQL_COPY3(CopyRates)
MQL_COPY3(CopyTime)
MQL_COPY3(CopyOpen)
MQL_COPY3(CopyHigh)
MQL_COPY3(CopyLow)
MQL_COPY3(CopyClose)
MQL_COPY3(CopyTickVolume)
MQL_COPY3(CopyRealVolume)
MQL_COPY3(CopySpread)
#undef MQL_COPY3
template<MQL_ARR(A)> inline int CopyTicks(const string &, A &, uint = 0, ulong = 0, uint = 0) { return 0; }
template<MQL_ARR(A)> inline int CopyTicksRange(const string &, A &, uint = 0, long = 0, long = 0) { return 0; }
#define COPY_TICKS_ALL 0
#define COPY_TICKS_INFO 1
#define COPY_TICKS_TRADE 2
#define TICK_FLAG_BID 2
#define TICK_FLAG_ASK 4
#define TICK_FLAG_LAST 8
#define TICK_FLAG_VOLUME 16
#define TICK_FLAG_BUY 32
#define TICK_FLAG_SELL 64

//---------------------------------------------------------------- symbols
inline bool   SymbolInfoTick(const string &, MqlTick &) { return true; }
inline double SymbolInfoDouble(const string &, int) { return 0; }
inline bool   SymbolInfoDouble(const string &, int, double &) { return true; }
inline long   SymbolInfoInteger(const string &, int) { return 0; }
inline bool   SymbolInfoInteger(const string &, int, long &) { return true; }
inline string SymbolInfoString(const string &, int) { return ""; }
inline bool   SymbolInfoString(const string &, int, string &) { return true; }
inline bool   SymbolInfoMarginRate(const string &, int, double &, double &) { return true; }
inline bool   SymbolInfoSessionQuote(const string &, int, uint, datetime &, datetime &) { return true; }
inline bool   SymbolInfoSessionTrade(const string &, int, uint, datetime &, datetime &) { return true; }
inline bool   SymbolSelect(const string &, bool) { return true; }
inline bool   SymbolExist(const string &, bool &) { return true; }
inline int    SymbolsTotal(bool) { return 0; }
inline string SymbolName(int, bool) { return ""; }
inline bool   SymbolIsSynchronized(const string &) { return true; }
inline bool   MarketBookAdd(const string &) { return true; }
inline bool   MarketBookRelease(const string &) { return true; }
template<MQL_ARR(A)> inline bool MarketBookGet(const string &, A &) { return true; }

//---------------------------------------------------------------- indicators
template<class... P> inline int iCustom(const string &, int, const string &, const P &...) { return 0; }
inline int iAC(const string &, int) { return 0; }
inline int iAD(const string &, int, int) { return 0; }
inline int iADX(const string &, int, int) { return 0; }
inline int iADXWilder(const string &, int, int) { return 0; }
inline int iAlligator(const string &, int, int, int, int, int, int, int, int, int) { return 0; }
inline int iAMA(const string &, int, int, int, int, int, int) { return 0; }
inline int iAO(const string &, int) { return 0; }
inline int iATR(const string &, int, int) { return 0; }
inline int iBearsPower(const string &, int, int) { return 0; }
inline int iBands(const string &, int, int, int, double, int) { return 0; }
inline int iBullsPower(const string &, int, int) { return 0; }
inline int iCCI(const string &, int, int, int) { return 0; }
inline int iChaikin(const string &, int, int, int, int, int) { return 0; }
inline int iDEMA(const string &, int, int, int, int) { return 0; }
inline int iDeMarker(const string &, int, int) { return 0; }
inline int iEnvelopes(const string &, int, int, int, int, int, double) { return 0; }
inline int iForce(const string &, int, int, int, int) { return 0; }
inline int iFractals(const string &, int) { return 0; }
inline int iFrAMA(const string &, int, int, int, int) { return 0; }
inline int iGator(const string &, int, int, int, int, int, int, int, int, int) { return 0; }
inline int iIchimoku(const string &, int, int, int, int) { return 0; }
inline int iBWMFI(const string &, int, int) { return 0; }
inline int iMomentum(const string &, int, int, int) { return 0; }
inline int iMFI(const string &, int, int, int) { return 0; }
inline int iMA(const string &, int, int, int, int, int) { return 0; }
inline int iOsMA(const string &, int, int, int, int, int) { return 0; }
inline int iMACD(const string &, int, int, int, int, int) { return 0; }
inline int iOBV(const string &, int, int) { return 0; }
inline int iSAR(const string &, int, double, double) { return 0; }
inline int iRSI(const string &, int, int, int) { return 0; }
inline int iRVI(const string &, int, int) { return 0; }
inline int iStdDev(const string &, int, int, int, int, int) { return 0; }
inline int iStochastic(const string &, int, int, int, int, int, int) { return 0; }
inline int iTEMA(const string &, int, int, int, int) { return 0; }
inline int iTriX(const string &, int, int, int) { return 0; }
inline int iWPR(const string &, int, int) { return 0; }
inline int iVIDyA(const string &, int, int, int, int, int) { return 0; }
inline int iVolumes(const string &, int, int) { return 0; }
template<MQL_ARR(A)> inline int IndicatorCreate(const string &, int, int, int = 0, const A & = A()) { return 0; }
inline int  IndicatorCreate(const string &, int, int) { return 0; }
template<MQL_ARR(A)> inline int IndicatorParameters(int, int &, A &) { return 0; }
inline bool IndicatorRelease(int) { return true; }
inline int  BarsCalculated(int) { return 0; }
template<MQL_ARR(A)> inline int CopyBuffer(int, int, int, int, A &) { return 0; }
template<MQL_ARR(A)> inline int CopyBuffer(int, int, datetime, int, A &) { return 0; }
template<MQL_ARR(A)> inline int CopyBuffer(int, int, datetime, datetime, A &) { return 0; }
// custom-indicator side
template<MQL_ARR(A)> inline bool SetIndexBuffer(int, A &, int = INDICATOR_DATA) { return true; }
inline bool IndicatorSetDouble(int, double) { return true; }
inline bool IndicatorSetDouble(int, int, double) { return true; }
inline bool IndicatorSetInteger(int, long) { return true; }
inline bool IndicatorSetInteger(int, int, long) { return true; }
inline bool IndicatorSetString(int, const string &) { return true; }
inline bool IndicatorSetString(int, int, const string &) { return true; }
inline bool PlotIndexSetDouble(int, int, double) { return true; }
inline bool PlotIndexSetInteger(int, int, long) { return true; }
inline bool PlotIndexSetInteger(int, int, int, long) { return true; }
inline bool PlotIndexSetString(int, int, const string &) { return true; }
inline long PlotIndexGetInteger(int, int, int = 0) { return 0; }

//---------------------------------------------------------------- objects
inline int    ObjectsTotal(long, int = -1, int = -1) { return 0; }
inline string ObjectName(long, int, int = -1, int = -1) { return ""; }
inline int    ObjectFind(long, const string &) { return -1; }
inline bool   ObjectCreate(long, const string &, int, int, datetime, double) { return true; }
template<class... A> inline bool ObjectCreate(long, const string &, int, int, datetime, double, datetime, double, const A &...) { return true; }
inline bool   ObjectDelete(long, const string &) { return true; }
inline int    ObjectsDeleteAll(long, int = -1, int = -1) { return 0; }
inline int    ObjectsDeleteAll(long, const string &, int = -1, int = -1) { return 0; }
inline bool   ObjectMove(long, const string &, int, datetime, double) { return true; }
inline long   ObjectGetInteger(long, const string &, int, int = 0) { return 0; }
inline bool   ObjectGetInteger(long, const string &, int, int, long &) { return true; }
inline double ObjectGetDouble(long, const string &, int, int = 0) { return 0; }
inline bool   ObjectGetDouble(long, const string &, int, int, double &) { return true; }
inline string ObjectGetString(long, const string &, int, int = 0) { return ""; }
inline bool   ObjectGetString(long, const string &, int, int, string &) { return true; }
inline bool   ObjectSetInteger(long, const string &, int, long) { return true; }
inline bool   ObjectSetInteger(long, const string &, int, int, long) { return true; }
inline bool   ObjectSetDouble(long, const string &, int, double) { return true; }
inline bool   ObjectSetDouble(long, const string &, int, int, double) { return true; }
inline bool   ObjectSetString(long, const string &, int, const string &) { return true; }
inline bool   ObjectSetString(long, const string &, int, int, const string &) { return true; }
inline double   ObjectGetValueByTime(long, const string &, datetime, int = 0) { return 0; }
inline datetime ObjectGetTimeByValue(long, const string &, double, int = 0) { return 0; }
inline double   ObjectGetValueByShift(const string &, int) { return 0; }     // MQL4-ism, tolerated
inline int      ObjectGetShiftByValue(const string &, double) { return 0; }  // MQL4-ism, tolerated
inline bool   TextSetFont(const string &, int, uint = 0, int = 0) { return true; }
template<MQL_ARR(A)> inline bool TextOut(const string &, int, int, uint, A &, uint, uint, uint, int = 0) { return true; }
inline bool   TextGetSize(const string &, uint &, uint &) { return true; }
template<MQL_ARR(A)> inline bool ResourceCreate(const string &, const A &, uint, uint, uint, uint, uint, int) { return true; }
inline bool   ResourceCreate(const string &, const string &) { return true; }
inline bool   ResourceFree(const string &) { return true; }
template<MQL_ARR(A)> inline bool ResourceReadImage(const string &, A &, uint &, uint &) { return true; }
inline bool   ResourceSave(const string &, const string &) { return true; }
#define COLOR_FORMAT_XRGB_NOALPHA 0
#define COLOR_FORMAT_ARGB_RAW 1
#define COLOR_FORMAT_ARGB_NORMALIZE 2

//---------------------------------------------------------------- chart
inline long   ChartID() { return 0; }
inline long   ChartGetInteger(long, int, int = 0) { return 0; }
inline bool   ChartGetInteger(long, int, int, long &) { return true; }
inline double ChartGetDouble(long, int, int = 0) { return 0; }
inline bool   ChartGetDouble(long, int, int, double &) { return true; }
inline string ChartGetString(long, int) { return ""; }
inline bool   ChartGetString(long, int, string &) { return true; }
inline bool   ChartSetInteger(long, int, long) { return true; }
inline bool   ChartSetInteger(long, int, int, long) { return true; }
inline bool   ChartSetDouble(long, int, double) { return true; }
inline bool   ChartSetString(long, int, const string &) { return true; }
inline void   ChartRedraw(long = 0) {}
inline int    ChartWindowFind() { return 0; }
inline int    ChartWindowFind(long, const string &) { return 0; }
inline ENUM_TIMEFRAMES ChartPeriod(long = 0) { return PERIOD_CURRENT; }
inline string ChartSymbol(long = 0) { return ""; }
inline double ChartPriceOnDropped() { return 0; }
inline datetime ChartTimeOnDropped() { return 0; }
inline int    ChartWindowOnDropped() { return 0; }
inline int    ChartXOnDropped() { return 0; }
inline int    ChartYOnDropped() { return 0; }
inline long   ChartOpen(const string &, int) { return 0; }
inline bool   ChartClose(long = 0) { return true; }
inline long   ChartFirst() { return 0; }
inline long   ChartNext(long) { return -1; }
inline bool   ChartSetSymbolPeriod(long, const string &, int) { return true; }
inline bool   ChartNavigate(long, int, int = 0) { return true; }
inline bool   ChartApplyTemplate(long, const string &) { return true; }
inline bool   ChartSaveTemplate(long, const string &) { return true; }
inline bool   ChartScreenShot(long, const string &, int, int, int = -1) { return true; }
inline bool   ChartIndicatorAdd(long, int, int) { return true; }
inline bool   ChartIndicatorDelete(long, int, const string &) { return true; }
inline int    ChartIndicatorGet(long, int, const string &) { return 0; }
inline string ChartIndicatorName(long, int, int) { return ""; }
inline int    ChartIndicatorsTotal(long, int) { return 0; }
inline bool   ChartTimePriceToXY(long, int, datetime, double, int &, int &) { return true; }
inline bool   ChartXYToTimePrice(long, int, int, int &, datetime &, double &) { return true; }

//---------------------------------------------------------------- trading
inline bool   OrderSend(const MqlTradeRequest &, MqlTradeResult &) { return true; }
inline bool   OrderSendAsync(const MqlTradeRequest &, MqlTradeResult &) { return true; }
inline bool   OrderCheck(const MqlTradeRequest &, MqlTradeCheckResult &) { return true; }
inline bool   OrderCalcMargin(int, const string &, double, double, double &) { return true; }
inline bool   OrderCalcProfit(int, const string &, double, double, double, double &) { return true; }
inline int    PositionsTotal() { return 0; }
inline ulong  PositionGetTicket(int) { return 0; }
inline string PositionGetSymbol(int) { return ""; }
inline bool   PositionSelect(const string &) { return true; }
inline bool   PositionSelectByTicket(ulong) { return true; }
inline long   PositionGetInteger(int) { return 0; }
inline bool   PositionGetInteger(int, long &) { return true; }
inline double PositionGetDouble(int) { return 0; }
inline bool   PositionGetDouble(int, double &) { return true; }
inline string PositionGetString(int) { return ""; }
inline bool   PositionGetString(int, string &) { return true; }
inline int    OrdersTotal() { return 0; }
inline ulong  OrderGetTicket(int) { return 0; }
inline bool   OrderSelect(ulong) { return true; }
inline long   OrderGetInteger(int) { return 0; }
inline bool   OrderGetInteger(int, long &) { return true; }
inline double OrderGetDouble(int) { return 0; }
inline bool   OrderGetDouble(int, double &) { return true; }
inline string OrderGetString(int) { return ""; }
inline bool   OrderGetString(int, string &) { return true; }
inline bool   HistorySelect(datetime, datetime) { return true; }
inline bool   HistorySelectByPosition(long) { return true; }
inline bool   HistoryOrderSelect(ulong) { return true; }
inline int    HistoryOrdersTotal() { return 0; }
inline ulong  HistoryOrderGetTicket(int) { return 0; }
inline long   HistoryOrderGetInteger(ulong, int) { return 0; }
inline bool   HistoryOrderGetInteger(ulong, int, long &) { return true; }
inline double HistoryOrderGetDouble(ulong, int) { return 0; }
inline bool   HistoryOrderGetDouble(ulong, int, double &) { return true; }
inline string HistoryOrderGetString(ulong, int) { return ""; }
inline bool   HistoryOrderGetString(ulong, int, string &) { return true; }
inline bool   HistoryDealSelect(ulong) { return true; }
inline int    HistoryDealsTotal() { return 0; }
inline ulong  HistoryDealGetTicket(int) { return 0; }
inline long   HistoryDealGetInteger(ulong, int) { return 0; }
inline bool   HistoryDealGetInteger(ulong, int, long &) { return true; }
inline double HistoryDealGetDouble(ulong, int) { return 0; }
inline bool   HistoryDealGetDouble(ulong, int, double &) { return true; }
inline string HistoryDealGetString(ulong, int) { return ""; }
inline bool   HistoryDealGetString(ulong, int, string &) { return true; }

//---------------------------------------------------------------- account / terminal
inline double AccountInfoDouble(int) { return 0; }
inline long   AccountInfoInteger(int) { return 0; }
inline string AccountInfoString(int) { return ""; }
inline int    TerminalInfoInteger(int) { return 0; }
inline double TerminalInfoDouble(int) { return 0; }
inline string TerminalInfoString(int) { return ""; }
inline int    MQLInfoInteger(int) { return 0; }
inline string MQLInfoString(int) { return ""; }
inline bool   MQLInfoIntegerSet(int, int) { return true; }
inline bool   TerminalInfoIntegerSet(int, int) { return true; }
inline bool   IsTesting() { return false; }      // MQL4-isms, tolerated
inline bool   IsOptimization() { return false; }
inline bool   IsVisualMode() { return false; }
inline bool   IsTradeAllowed() { return true; }
inline bool   IsConnected() { return true; }
inline bool   IsDemo() { return false; }
inline bool   IsExpertEnabled() { return true; }
inline bool   RefreshRates() { return true; }
inline bool   FrameAdd(const string &, long, double, const string &) { return true; }
inline bool   FrameNext(ulong &, string &, long &, double &) { return false; }
template<MQL_ARR(A)> inline bool FrameNext(ulong &, string &, long &, double &, A &) { return false; }
inline bool   FrameFirst() { return true; }
inline bool   FrameFilter(const string &, long) { return true; }
inline bool   FrameInputs(ulong, MqlArray<string> &, uint &) { return true; }
inline bool   ParameterGetRange(const string &, bool &, long &, long &, long &, long &) { return true; }
inline bool   ParameterGetRange(const string &, bool &, double &, double &, double &, double &) { return true; }
inline bool   ParameterSetRange(const string &, bool, long, long, long, long) { return true; }
inline bool   ParameterSetRange(const string &, bool, double, double, double, double) { return true; }
inline int    WebRequest(const string &, const string &, const string &, int, const MqlArray<char> &, MqlArray<char> &, string &) { return 0; }
inline int    WebRequest(const string &, const string &, const string &, const string &, int, const MqlArray<char> &, int, MqlArray<char> &, string &) { return 0; }
inline bool   SocketCreate(uint = 0) { return true; }
inline uint   CryptEncode(int, const MqlArray<uchar> &, const MqlArray<uchar> &, MqlArray<uchar> &) { return 0; }
inline uint   CryptDecode(int, const MqlArray<uchar> &, const MqlArray<uchar> &, MqlArray<uchar> &) { return 0; }
enum ENUM_CRYPT_METHOD { CRYPT_BASE64, CRYPT_AES128, CRYPT_AES256, CRYPT_DES, CRYPT_HASH_SHA1, CRYPT_HASH_SHA256, CRYPT_HASH_MD5, CRYPT_ARCH_ZIP };
