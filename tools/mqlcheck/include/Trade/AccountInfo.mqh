// mqlcheck stand-in for <Trade\AccountInfo.mqh> (CAccountInfo)
#pragma once
#include <Object.mqh>
class CAccountInfo : public CObject
  {
public:
   CAccountInfo() {}
   long   Login() const { return 0; }
   ENUM_ACCOUNT_TRADE_MODE TradeMode() const { return ACCOUNT_TRADE_MODE_DEMO; }
   string TradeModeDescription() const { return ""; }
   long   Leverage() const { return 100; }
   ENUM_ACCOUNT_STOPOUT_MODE StopoutMode() const { return ACCOUNT_STOPOUT_MODE_PERCENT; }
   string StopoutModeDescription() const { return ""; }
   ENUM_ACCOUNT_MARGIN_MODE MarginMode() const { return ACCOUNT_MARGIN_MODE_RETAIL_HEDGING; }
   string MarginModeDescription() const { return ""; }
   bool   TradeAllowed() const { return true; }
   bool   TradeExpert() const { return true; }
   int    LimitOrders() const { return 0; }
   double Balance() const { return 0; }
   double Credit() const { return 0; }
   double Profit() const { return 0; }
   double Equity() const { return 0; }
   double Margin() const { return 0; }
   double FreeMargin() const { return 0; }
   double MarginLevel() const { return 0; }
   double MarginCall() const { return 0; }
   double MarginStopOut() const { return 0; }
   string Name() const { return ""; }
   string Server() const { return ""; }
   string Currency() const { return ""; }
   string Company() const { return ""; }
   long   InfoInteger(int) const { return 0; }
   double InfoDouble(int) const { return 0; }
   string InfoString(int) const { return ""; }
   double OrderProfitCheck(const string &, const int, const double, const double, const double) const { return 0; }
   double MarginCheck(const string &, const int, const double, const double) const { return 0; }
   double FreeMarginCheck(const string &, const int, const double, const double) const { return 0; }
   double MaxLotCheck(const string &, const int, const double, const double = 100.0) const { return 0; }
  };
