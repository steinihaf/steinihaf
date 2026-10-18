// mqlcheck stand-in for <Trade\PositionInfo.mqh> (CPositionInfo) - Standard Library signatures
#pragma once
#pragma GCC system_header
#include <Object.mqh>
class CPositionInfo : public CObject
  {
public:
   CPositionInfo() {}
   //--- fast access to integer properties
   ulong    Ticket() const { return 0; }
   datetime Time() const { return 0; }
   ulong    TimeMsc() const { return 0; }
   datetime TimeUpdate() const { return 0; }
   ulong    TimeUpdateMsc() const { return 0; }
   ENUM_POSITION_TYPE PositionType() const { return POSITION_TYPE_BUY; }
   string   TypeDescription() const { return ""; }
   long     Magic() const { return 0; }
   long     Identifier() const { return 0; }
   //--- fast access to double properties
   double   Volume() const { return 0; }
   double   PriceOpen() const { return 0; }
   double   StopLoss() const { return 0; }
   double   TakeProfit() const { return 0; }
   double   PriceCurrent() const { return 0; }
   double   Commission() const { return 0; }
   double   Swap() const { return 0; }
   double   Profit() const { return 0; }
   //--- fast access to string properties
   string   Symbol() const { return ""; }
   string   Comment() const { return ""; }
   //--- access to MQL5 API
   bool     InfoInteger(const int, long &) const { return true; }
   bool     InfoDouble(const int, double &) const { return true; }
   bool     InfoString(const int, string &) const { return true; }
   //--- text
   string   FormatType(string &str, const uint) const { return str; }
   string   FormatPosition(string &str) const { return str; }
   //--- selection
   bool     Select(const string &) { return true; }
   bool     SelectByMagic(const string &, const ulong) { return true; }
   bool     SelectByTicket(const ulong) { return true; }
   bool     SelectByIndex(const int) { return true; }
   //--- state
   void     StoreState() {}
   bool     CheckState() { return false; }
  };
