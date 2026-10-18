// mqlcheck stand-in for <Trade\SymbolInfo.mqh> (CSymbolInfo)
#pragma once
#include <Object.mqh>
class CSymbolInfo : public CObject
  {
   string m_name;
public:
   CSymbolInfo() {}
   string Name() const { return m_name; }
   bool   Name(const string &name) { m_name = name; return true; }
   bool   Refresh() { return true; }
   bool   RefreshRates() { return true; }
   bool   Select() const { return true; }
   bool   Select(const bool) { return true; }
   bool   IsSynchronized() const { return true; }
   // volumes / time
   ulong    Volume() const { return 0; }
   ulong    VolumeHigh() const { return 0; }
   ulong    VolumeLow() const { return 0; }
   datetime Time() const { return 0; }
   int      Spread() const { return 0; }
   bool     SpreadFloat() const { return true; }
   int      TicksBookDepth() const { return 0; }
   int      StopsLevel() const { return 0; }
   int      FreezeLevel() const { return 0; }
   // prices
   double Bid() const { return 0; }
   double BidHigh() const { return 0; }
   double BidLow() const { return 0; }
   double Ask() const { return 0; }
   double AskHigh() const { return 0; }
   double AskLow() const { return 0; }
   double Last() const { return 0; }
   double LastHigh() const { return 0; }
   double LastLow() const { return 0; }
   // terms of trade
   ENUM_SYMBOL_CALC_MODE TradeCalcMode() const { return SYMBOL_CALC_MODE_FOREX; }
   string TradeCalcModeDescription() const { return ""; }
   ENUM_SYMBOL_TRADE_MODE TradeMode() const { return SYMBOL_TRADE_MODE_FULL; }
   string TradeModeDescription() const { return ""; }
   ENUM_SYMBOL_TRADE_EXECUTION TradeExecution() const { return SYMBOL_TRADE_EXECUTION_MARKET; }
   string TradeExecutionDescription() const { return ""; }
   ENUM_SYMBOL_SWAP_MODE SwapMode() const { return SYMBOL_SWAP_MODE_POINTS; }
   string SwapModeDescription() const { return ""; }
   ENUM_DAY_OF_WEEK SwapRollover3days() const { return WEDNESDAY; }
   string SwapRollover3daysDescription() const { return ""; }
   bool   MarginHedgedUseLeg() const { return false; }
   int    ExpirationMode() const { return 0; }
   int    FillingMode() const { return 0; }
   int    OrderMode() const { return 0; }
   bool   ExpirationModeFlag(int) const { return true; }
   bool   FillingModeFlag(int) const { return true; }
   bool   OrderModeFlag(int) const { return true; }
   // dates / digits / points
   datetime StartTime() const { return 0; }
   datetime ExpirationTime() const { return 0; }
   int    Digits() const { return 5; }
   double Point() const { return 0.00001; }
   double TickValue() const { return 0; }
   double TickValueProfit() const { return 0; }
   double TickValueLoss() const { return 0; }
   double TickSize() const { return 0; }
   double ContractSize() const { return 0; }
   double LotsMin() const { return 0; }
   double LotsMax() const { return 0; }
   double LotsStep() const { return 0; }
   double LotsLimit() const { return 0; }
   double SwapLong() const { return 0; }
   double SwapShort() const { return 0; }
   double MarginInitial() const { return 0; }
   double MarginMaintenance() const { return 0; }
   bool   MarginLong(double &, double &) const { return true; }
   bool   MarginShort(double &, double &) const { return true; }
   bool   MarginStop(double &, double &) const { return true; }
   bool   MarginLimit(double &, double &) const { return true; }
   bool   MarginStopLimit(double &, double &) const { return true; }
   int    TradeTimeFlags() const { return 0; }
   int    TradeFillFlags() const { return 0; }
   // text
   string CurrencyBase() const { return ""; }
   string CurrencyProfit() const { return ""; }
   string CurrencyMargin() const { return ""; }
   string Bank() const { return ""; }
   string Description() const { return ""; }
   string Path() const { return ""; }
   long   SessionDeals() const { return 0; }
   long   SessionBuyOrders() const { return 0; }
   long   SessionSellOrders() const { return 0; }
   double SessionTurnover() const { return 0; }
   double SessionInterest() const { return 0; }
   double SessionBuyOrdersVolume() const { return 0; }
   double SessionSellOrdersVolume() const { return 0; }
   double SessionOpen() const { return 0; }
   double SessionClose() const { return 0; }
   double SessionAW() const { return 0; }
   double SessionPriceSettlement() const { return 0; }
   double SessionPriceLimitMin() const { return 0; }
   double SessionPriceLimitMax() const { return 0; }
   // access to raw API
   bool   InfoInteger(int, long &) const { return true; }
   bool   InfoDouble(int, double &) const { return true; }
   bool   InfoString(int, string &) const { return true; }
   // helpers
   double NormalizePrice(const double price) const { return price; }
   bool   CheckMarketWatch() { return true; }
  };
