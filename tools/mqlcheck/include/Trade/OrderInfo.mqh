// mqlcheck stand-in for <Trade\OrderInfo.mqh> (COrderInfo) - Standard Library signatures
#pragma once
#pragma GCC system_header
#include <Object.mqh>
class COrderInfo : public CObject
  {
public:
   COrderInfo() {}
   ulong    Ticket() const { return 0; }
   datetime TimeSetup() const { return 0; }
   ulong    TimeSetupMsc() const { return 0; }
   datetime TimeDone() const { return 0; }
   ulong    TimeDoneMsc() const { return 0; }
   ENUM_ORDER_TYPE OrderType() const { return ORDER_TYPE_BUY; }
   string   TypeDescription() const { return ""; }
   ENUM_ORDER_STATE State() const { return ORDER_STATE_PLACED; }
   string   StateDescription() const { return ""; }
   datetime TimeExpiration() const { return 0; }
   ENUM_ORDER_TYPE_FILLING TypeFilling() const { return ORDER_FILLING_FOK; }
   string   TypeFillingDescription() const { return ""; }
   ENUM_ORDER_TYPE_TIME TypeTime() const { return ORDER_TIME_GTC; }
   string   TypeTimeDescription() const { return ""; }
   long     Magic() const { return 0; }
   long     PositionId() const { return 0; }
   long     PositionById() const { return 0; }
   double   VolumeInitial() const { return 0; }
   double   VolumeCurrent() const { return 0; }
   double   PriceOpen() const { return 0; }
   double   StopLoss() const { return 0; }
   double   TakeProfit() const { return 0; }
   double   PriceCurrent() const { return 0; }
   double   PriceStopLimit() const { return 0; }
   string   Symbol() const { return ""; }
   string   Comment() const { return ""; }
   string   ExternalId() const { return ""; }
   bool     InfoInteger(const int, long &) const { return true; }
   bool     InfoDouble(const int, double &) const { return true; }
   bool     InfoString(const int, string &) const { return true; }
   string   FormatType(string &str, const uint) const { return str; }
   string   FormatStatus(string &str, const uint) const { return str; }
   string   FormatTypeFilling(string &str, const uint) const { return str; }
   string   FormatTypeTime(string &str, const uint) const { return str; }
   string   FormatOrder(string &str) const { return str; }
   string   FormatPrice(string &str, const double, const double, const uint) const { return str; }
   bool     Select() { return true; }
   bool     Select(const ulong) { return true; }
   bool     SelectByIndex(const int) { return true; }
   void     StoreState() {}
   bool     CheckState() { return false; }
  };
