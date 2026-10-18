// mqlcheck stand-in for <Trade\Trade.mqh> (CTrade) - signatures follow the
// MQL5 Standard Library including default arguments.
#pragma once
#include <Object.mqh>
#include "SymbolInfo.mqh"
#include "OrderInfo.mqh"
#include "HistoryOrderInfo.mqh"
#include "PositionInfo.mqh"
#include "DealInfo.mqh"

class CTrade : public CObject
  {
protected:
   MqlTradeRequest     m_request;
   MqlTradeResult      m_result;
   MqlTradeCheckResult m_check_result;
   bool                m_async_mode;
   ulong               m_magic;
   ulong               m_deviation;
   ENUM_ORDER_TYPE_FILLING m_type_filling;
   ENUM_ACCOUNT_MARGIN_MODE m_margin_mode;
   ENUM_LOG_LEVELS     m_log_level;
public:
   CTrade() : m_async_mode(false), m_magic(0), m_deviation(10), m_type_filling(ORDER_FILLING_FOK),
              m_margin_mode(ACCOUNT_MARGIN_MODE_RETAIL_HEDGING), m_log_level(LOG_LEVEL_ERRORS) {}
   //--- settings
   void   LogLevel(const ENUM_LOG_LEVELS log_level) { m_log_level = log_level; }
   void   Request(MqlTradeRequest &request) const { request = m_request; }
   ENUM_TRADE_REQUEST_ACTIONS RequestAction() const { return m_request.action; }
   string RequestActionDescription() const { return ""; }
   ulong  RequestMagic() const { return m_request.magic; }
   ulong  RequestOrder() const { return m_request.order; }
   ulong  RequestPosition() const { return m_request.position; }
   ulong  RequestPositionBy() const { return m_request.position_by; }
   string RequestSymbol() const { return m_request.symbol; }
   double RequestVolume() const { return m_request.volume; }
   double RequestPrice() const { return m_request.price; }
   double RequestStopLimit() const { return m_request.stoplimit; }
   double RequestSL() const { return m_request.sl; }
   double RequestTP() const { return m_request.tp; }
   ulong  RequestDeviation() const { return m_request.deviation; }
   ENUM_ORDER_TYPE RequestType() const { return m_request.type; }
   string RequestTypeDescription() const { return ""; }
   ENUM_ORDER_TYPE_FILLING RequestTypeFilling() const { return m_request.type_filling; }
   string RequestTypeFillingDescription() const { return ""; }
   ENUM_ORDER_TYPE_TIME RequestTypeTime() const { return m_request.type_time; }
   string RequestTypeTimeDescription() const { return ""; }
   datetime RequestExpiration() const { return m_request.expiration; }
   string RequestComment() const { return m_request.comment; }
   //--- trade result
   void   Result(MqlTradeResult &result) const { result = m_result; }
   uint   ResultRetcode() const { return m_result.retcode; }
   string ResultRetcodeDescription() const { return ""; }
   int    ResultRetcodeExternal() const { return m_result.retcode_external; }
   ulong  ResultDeal() const { return m_result.deal; }
   ulong  ResultOrder() const { return m_result.order; }
   double ResultVolume() const { return m_result.volume; }
   double ResultPrice() const { return m_result.price; }
   double ResultBid() const { return m_result.bid; }
   double ResultAsk() const { return m_result.ask; }
   string ResultComment() const { return m_result.comment; }
   //--- check result
   void   CheckResult(MqlTradeCheckResult &check_result) const { check_result = m_check_result; }
   uint   CheckResultRetcode() const { return m_check_result.retcode; }
   string CheckResultRetcodeDescription() const { return ""; }
   double CheckResultBalance() const { return m_check_result.balance; }
   double CheckResultEquity() const { return m_check_result.equity; }
   double CheckResultProfit() const { return m_check_result.profit; }
   double CheckResultMargin() const { return m_check_result.margin; }
   double CheckResultMarginFree() const { return m_check_result.margin_free; }
   double CheckResultMarginLevel() const { return m_check_result.margin_level; }
   string CheckResultComment() const { return m_check_result.comment; }
   //--- trade methods
   void   SetAsyncMode(const bool mode) { m_async_mode = mode; }
   void   SetExpertMagicNumber(const ulong magic) { m_magic = magic; }
   void   SetDeviationInPoints(const ulong deviation) { m_deviation = deviation; }
   void   SetTypeFilling(const ENUM_ORDER_TYPE_FILLING filling) { m_type_filling = filling; }
   bool   SetTypeFillingBySymbol(const string &symbol) { return true; }
   void   SetMarginMode() {}
   //--- positions
   bool   PositionOpen(const string &symbol, const ENUM_ORDER_TYPE order_type, const double volume, const double price,
                       const double sl, const double tp, const string &comment = "") { return true; }
   bool   PositionModify(const string &symbol, const double sl, const double tp) { return true; }
   bool   PositionModify(const ulong ticket, const double sl, const double tp) { return true; }
   bool   PositionClose(const string &symbol, const ulong deviation = ULONG_MAX) { return true; }
   bool   PositionClose(const ulong ticket, const ulong deviation = ULONG_MAX) { return true; }
   bool   PositionCloseBy(const ulong ticket, const ulong ticket_by) { return true; }
   bool   PositionClosePartial(const string &symbol, const double volume, const ulong deviation = ULONG_MAX) { return true; }
   bool   PositionClosePartial(const ulong ticket, const double volume, const ulong deviation = ULONG_MAX) { return true; }
   //--- orders
   bool   OrderOpen(const string &symbol, const ENUM_ORDER_TYPE order_type, const double volume, const double limit_price,
                    const double price, const double sl, const double tp, ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC,
                    const datetime expiration = 0, const string &comment = "") { return true; }
   bool   OrderModify(const ulong ticket, const double price, const double sl, const double tp,
                      const ENUM_ORDER_TYPE_TIME type_time, const datetime expiration, const double stoplimit = 0.0) { return true; }
   bool   OrderDelete(const ulong ticket) { return true; }
   //--- market orders
   bool   Buy(const double volume, const string &symbol = NULL, double price = 0.0, const double sl = 0.0, const double tp = 0.0, const string &comment = "") { return true; }
   bool   Sell(const double volume, const string &symbol = NULL, double price = 0.0, const double sl = 0.0, const double tp = 0.0, const string &comment = "") { return true; }
   //--- pending orders
   bool   BuyLimit(const double volume, const double price, const string &symbol = NULL, const double sl = 0.0, const double tp = 0.0,
                   const ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, const datetime expiration = 0, const string &comment = "") { return true; }
   bool   BuyStop(const double volume, const double price, const string &symbol = NULL, const double sl = 0.0, const double tp = 0.0,
                  const ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, const datetime expiration = 0, const string &comment = "") { return true; }
   bool   SellLimit(const double volume, const double price, const string &symbol = NULL, const double sl = 0.0, const double tp = 0.0,
                    const ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, const datetime expiration = 0, const string &comment = "") { return true; }
   bool   SellStop(const double volume, const double price, const string &symbol = NULL, const double sl = 0.0, const double tp = 0.0,
                   const ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, const datetime expiration = 0, const string &comment = "") { return true; }
   //--- raw
   bool   OrderSend(const MqlTradeRequest &request, MqlTradeResult &result) { return ::OrderSend(request, result); }
   //--- info
   void   PrintRequest() const {}
   void   PrintResult() const {}
   string FormatRequest(string &str, const MqlTradeRequest &request) const { return str; }
   string FormatRequestResult(string &str, const MqlTradeRequest &request, const MqlTradeResult &result) const { return str; }
   bool   ClearStructures() { return true; }
   bool   IsStopped(const string &function) { return false; }
   bool   SelectPosition(const string &symbol) { return true; }
   bool   OrderTypeCheck(const string &symbol) { return true; }
   bool   FillingCheck(const string &symbol) { return true; }
   bool   ExpirationCheck(const string &symbol) { return true; }
  };
