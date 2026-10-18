// mqlcheck stand-in for <Trade\DealInfo.mqh> (CDealInfo)
#pragma once
#include <Object.mqh>
class CDealInfo : public CObject
  {
public:
   CDealInfo() {}
   void     Ticket(const ulong) {}
   ulong    Ticket() const { return 0; }
   long     Order() const { return 0; }
   datetime Time() const { return 0; }
   ulong    TimeMsc() const { return 0; }
   ENUM_DEAL_TYPE DealType() const { return DEAL_TYPE_BUY; }
   string   TypeDescription() const { return ""; }
   ENUM_DEAL_ENTRY Entry() const { return DEAL_ENTRY_IN; }
   string   EntryDescription() const { return ""; }
   long     Magic() const { return 0; }
   long     PositionId() const { return 0; }
   double   Volume() const { return 0; }
   double   Price() const { return 0; }
   double   Commission() const { return 0; }
   double   Swap() const { return 0; }
   double   Profit() const { return 0; }
   string   Symbol() const { return ""; }
   string   Comment() const { return ""; }
   string   ExternalId() const { return ""; }
   bool     InfoInteger(int, long &) const { return true; }
   bool     InfoDouble(int, double &) const { return true; }
   bool     InfoString(int, string &) const { return true; }
   string   FormatAction(string &str, const uint) const { return str; }
   string   FormatEntry(string &str, const uint) const { return str; }
   string   FormatDeal(string &str) const { return str; }
   bool     SelectByIndex(const int) { return true; }
  };
