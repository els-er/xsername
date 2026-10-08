//+------------------------------------------------------------------+
//|                                                TradeExecutor.mqh |
//| All trade operations go through this registry (spec 23):         |
//|   send -> check retcode -> log -> re-query -> verify -> retry     |
//| - one in-flight operation per ticket and kind (no duplicate close |
//|   or blind modification, audit G-15)                             |
//| - non-blocking: no Sleep(), retries are scheduled                |
//| - close: fast burst retries, then persistent retries for as long  |
//|   as the position exists (audit K-02)                            |
//| - closing deals always carry request.position and never exceed   |
//|   the live position volume (netting safety)                      |
//| - SL and TP of a position are changed in ONE request; requests of |
//|   the same cycle are merged (SL: most protective wins)           |
//| - optional asynchronous sending (OrderSendAsync): all requests of |
//|   a cycle leave at once; broker replies arrive via                |
//|   OnTradeTransaction (OnRequestResult) and state is re-verified  |
//| This class never opens a position.                               |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_TRADEEXECUTOR_MQH
#define EVE_RISK_TRADEEXECUTOR_MQH

#include "Defines.mqh"
#include "Logger.mqh"
#include "PriceRiskCalculator.mqh"

enum ENUM_EVE_RC_CLASS
  {
   EVE_RCC_SUCCESS    = 0,
   EVE_RCC_NO_CHANGE  = 1,
   EVE_RCC_GONE       = 2,
   EVE_RCC_RETRY      = 3,
   EVE_RCC_RETRY_SLOW = 4,
   EVE_RCC_REFILL     = 5
  };

struct SEveOp
  {
   ulong             ticket;
   int               kind;
   int               purpose;
   string            symbol;
   double            targetSL;          // EVE_KEEP = leave the SL as it is
   double            targetTP;          // EVE_KEEP = leave the TP as it is
   bool              slFromEngine;      // SL part requested by the aggregate SL engine
   bool              sentAsync;         // last request sent with OrderSendAsync
   uint              requestId;         // request_id of the last async request
   int               attempts;          // failed attempts
   int               sendCount;         // requests actually sent
   ulong             nextAttemptMs;
   bool              awaitingVerify;
   ulong             verifyDeadlineMs;
   double            volumeBefore;      // live volume when the close was sent
   uint              lastRetcode;
   uint              lastLoggedRetcode;
   bool              exhausted;         // fast burst exhausted -> persistent mode
   bool              blocked;           // market closed / trading disabled
   int               fillingIndex;
   ulong             createdMs;
   bool              done;
  };

struct SEveTicketCounter
  {
   ulong             ticket;
   int               failures;          // SL-engine failures (count toward the fail-safe)
   int               softFailures;      // trailing / TP failures (back-off only)
   ulong             blockedUntilMs;    // hard / environment block (applies to every request)
   ulong             softBlockedUntilMs; // back-off after trailing / TP failures (does not delay the SL engine)
   uint              lastRetcode;
  };

class CEveTradeExecutor
  {
private:
   SEveOp            m_ops[];
   SEveTicketCounter m_counters[];
   CEveLogger       *m_log;
   int               m_closeRetryCount;
   int               m_closeRetryDelayMs;
   int               m_verificationTimeoutMs;
   int               m_persistentRetryMs;
   int               m_deviationPoints;
   bool              m_preserveSL;
   bool              m_hedging;
   bool              m_async;
   string            m_lastFailure;

   int               FindOp(const ulong ticket, const int kind) const;
   int               AddOp(const ulong ticket, const int kind, const int purpose, const string symbol, const double targetSL);
   void              ProcessClose(const int i);
   void              ProcessModify(const int i);
   void              ProcessDelete(const int i);
   void              ScheduleRetry(const int i, const int rcClass, const string what);
   int               CounterIndex(const ulong ticket) const;
   int               EnsureCounter(const ulong ticket);
   void              RegisterModifyFailure(const ulong ticket, const uint retcode, const bool hard);
   bool              Send(MqlTradeRequest &req, MqlTradeResult &res, const int i);
   void              BlockModify(const ulong ticket, const uint retcode);
   void              PruneCounters(void);
   void              Compact(void);
   int               ClassifySendResult(const uint retcode);
   void              LogInfo(const string c, const string m)     { if(m_log != NULL) m_log.Info(c, m);     }
   void              LogWarning(const string c, const string m)  { if(m_log != NULL) m_log.Warning(c, m);  }
   void              LogError(const string c, const string m)    { if(m_log != NULL) m_log.Error(c, m);    }
   void              LogCritical(const string c, const string m) { if(m_log != NULL) m_log.Critical(c, m); }

public:
                     CEveTradeExecutor(void);
   void              Init(CEveLogger *log, const SEveConfig &cfg, const bool hedging);
   void              RequestClose(const ulong ticket, const int purpose);
   bool              RequestStops(const ulong ticket, const double sl, const double tp, const int purpose);
   bool              RequestModifySL(const ulong ticket, const double sl, const int purpose)
     { return RequestStops(ticket, sl, EVE_KEEP, purpose); }
   void              OnRequestResult(const MqlTradeRequest &request, const MqlTradeResult &result);
   void              RequestDeleteOrder(const ulong ticket, const int purpose);
   void              CancelModifyOps(const string why) { CancelOpsOfKind(EVE_OP_MODIFY_SL, why); }
   void              CancelOpsOfKind(const int kind, const string why);
   void              CancelAll(const string why);
   void              Process(void);

   bool              HasOp(const ulong ticket, const int kind) const { return (FindOp(ticket, kind) >= 0); }
   bool              HasActiveCloseOps(void) const;
   bool              HasActiveModifyOps(void) const;
   bool              AnyCloseFailing(void) const;
   int               ActiveOpCount(void) const;
   int               ModifyFailures(const ulong ticket) const;
   bool              IsModifyBlocked(const ulong ticket) const;
   bool              IsSoftBlocked(const ulong ticket) const;
   void              ResetModifyCounter(const ulong ticket);
   string            LastFailure(void) const { return m_lastFailure; }

   static int        ClassifyRetcode(const uint retcode);
   static string     RetcodeText(const uint retcode);
   static ENUM_ORDER_TYPE_FILLING FillingFor(const string symbol, const int index);
  };

//+------------------------------------------------------------------+
CEveTradeExecutor::CEveTradeExecutor(void) : m_log(NULL),
                                             m_closeRetryCount(5),
                                             m_closeRetryDelayMs(250),
                                             m_verificationTimeoutMs(5000),
                                             m_persistentRetryMs(1000),
                                             m_deviationPoints(1000),
                                             m_preserveSL(true),
                                             m_hedging(true),
                                             m_async(true),
                                             m_lastFailure("")
  {
  }

//+------------------------------------------------------------------+
void CEveTradeExecutor::Init(CEveLogger *log, const SEveConfig &cfg, const bool hedging)
  {
   m_log                   = log;
   m_closeRetryCount       = cfg.closeRetryCount;
   m_closeRetryDelayMs     = cfg.closeRetryDelayMs;
   m_verificationTimeoutMs = cfg.verificationTimeoutMs;
   m_persistentRetryMs     = cfg.persistentRetryIntervalMs;
   m_deviationPoints       = cfg.emergencyDeviationPoints;
   m_preserveSL            = cfg.preserveMoreProtectiveSL;
   m_hedging               = hedging;
   m_async                 = cfg.asyncSend;
   ArrayResize(m_ops, 0);
   ArrayResize(m_counters, 0);
   m_lastFailure = "";
  }

//+------------------------------------------------------------------+
//| Retcode classification                                           |
//+------------------------------------------------------------------+
int CEveTradeExecutor::ClassifyRetcode(const uint retcode)
  {
   switch(retcode)
     {
      case TRADE_RETCODE_DONE:
      case TRADE_RETCODE_DONE_PARTIAL:
      case TRADE_RETCODE_PLACED:
         return EVE_RCC_SUCCESS;
      case TRADE_RETCODE_NO_CHANGES:
         return EVE_RCC_NO_CHANGE;
      case TRADE_RETCODE_POSITION_CLOSED:
         return EVE_RCC_GONE;
      case TRADE_RETCODE_INVALID_FILL:
         return EVE_RCC_REFILL;
      case TRADE_RETCODE_MARKET_CLOSED:
      case TRADE_RETCODE_TRADE_DISABLED:
      case TRADE_RETCODE_SERVER_DISABLES_AT:
      case TRADE_RETCODE_CLIENT_DISABLES_AT:
      case TRADE_RETCODE_ONLY_REAL:
         return EVE_RCC_RETRY_SLOW;
     }
   return EVE_RCC_RETRY;
  }

//+------------------------------------------------------------------+
//| retcode 0 means the request never reached the server (local       |
//| check failed). If trading is not allowed this is "blocked".       |
//+------------------------------------------------------------------+
int CEveTradeExecutor::ClassifySendResult(const uint retcode)
  {
   if(retcode != 0)
      return ClassifyRetcode(retcode);
   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0 ||
      MQLInfoInteger(MQL_TRADE_ALLOWED) == 0 ||
      TerminalInfoInteger(TERMINAL_CONNECTED) == 0)
      return EVE_RCC_RETRY_SLOW;
   return EVE_RCC_RETRY;
  }

//+------------------------------------------------------------------+
string CEveTradeExecutor::RetcodeText(const uint retcode)
  {
   string name = "";
   switch(retcode)
     {
      case 0:                                  name = "NOT_SENT"; break;
      case TRADE_RETCODE_REQUOTE:              name = "REQUOTE"; break;
      case TRADE_RETCODE_REJECT:               name = "REJECT"; break;
      case TRADE_RETCODE_CANCEL:               name = "CANCEL"; break;
      case TRADE_RETCODE_PLACED:               name = "PLACED"; break;
      case TRADE_RETCODE_DONE:                 name = "DONE"; break;
      case TRADE_RETCODE_DONE_PARTIAL:         name = "DONE_PARTIAL"; break;
      case TRADE_RETCODE_ERROR:                name = "ERROR"; break;
      case TRADE_RETCODE_TIMEOUT:              name = "TIMEOUT"; break;
      case TRADE_RETCODE_INVALID:              name = "INVALID"; break;
      case TRADE_RETCODE_INVALID_VOLUME:       name = "INVALID_VOLUME"; break;
      case TRADE_RETCODE_INVALID_PRICE:        name = "INVALID_PRICE"; break;
      case TRADE_RETCODE_INVALID_STOPS:        name = "INVALID_STOPS"; break;
      case TRADE_RETCODE_TRADE_DISABLED:       name = "TRADE_DISABLED"; break;
      case TRADE_RETCODE_MARKET_CLOSED:        name = "MARKET_CLOSED"; break;
      case TRADE_RETCODE_NO_MONEY:             name = "NO_MONEY"; break;
      case TRADE_RETCODE_PRICE_CHANGED:        name = "PRICE_CHANGED"; break;
      case TRADE_RETCODE_PRICE_OFF:            name = "PRICE_OFF"; break;
      case TRADE_RETCODE_ORDER_CHANGED:        name = "ORDER_CHANGED"; break;
      case TRADE_RETCODE_TOO_MANY_REQUESTS:    name = "TOO_MANY_REQUESTS"; break;
      case TRADE_RETCODE_NO_CHANGES:           name = "NO_CHANGES"; break;
      case TRADE_RETCODE_SERVER_DISABLES_AT:   name = "SERVER_DISABLES_AT"; break;
      case TRADE_RETCODE_CLIENT_DISABLES_AT:   name = "CLIENT_DISABLES_AT (AutoTrading OFF)"; break;
      case TRADE_RETCODE_LOCKED:               name = "LOCKED"; break;
      case TRADE_RETCODE_FROZEN:               name = "FROZEN"; break;
      case TRADE_RETCODE_INVALID_FILL:         name = "INVALID_FILL"; break;
      case TRADE_RETCODE_CONNECTION:           name = "CONNECTION"; break;
      case TRADE_RETCODE_ONLY_REAL:            name = "ONLY_REAL"; break;
      case TRADE_RETCODE_LIMIT_ORDERS:         name = "LIMIT_ORDERS"; break;
      case TRADE_RETCODE_LIMIT_VOLUME:         name = "LIMIT_VOLUME"; break;
      case TRADE_RETCODE_INVALID_ORDER:        name = "INVALID_ORDER"; break;
      case TRADE_RETCODE_POSITION_CLOSED:      name = "POSITION_CLOSED"; break;
      case EVE_RC_INVALID_CLOSE_VOLUME:        name = "INVALID_CLOSE_VOLUME"; break;
      case EVE_RC_CLOSE_ORDER_EXIST:           name = "CLOSE_ORDER_EXIST"; break;
      case EVE_RC_LIMIT_POSITIONS:             name = "LIMIT_POSITIONS"; break;
      case EVE_RC_CLOSE_ONLY:                  name = "CLOSE_ONLY"; break;
      case EVE_RC_FIFO_CLOSE:                  name = "FIFO_CLOSE"; break;
      default:                                 name = "RETCODE"; break;
     }
   return name + "(" + IntegerToString((long)retcode) + ")";
  }

//+------------------------------------------------------------------+
//| Filling candidates. Instant/Request execution -> FOK first.      |
//| Market execution -> modes allowed by SYMBOL_FILLING_MODE first,  |
//| then the remaining ones. Rotated on TRADE_RETCODE_INVALID_FILL.  |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING CEveTradeExecutor::FillingFor(const string symbol, const int index)
  {
   ENUM_ORDER_TYPE_FILLING list[3];
   int n = 0;
   ENUM_SYMBOL_TRADE_EXECUTION exe = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE);
   long fm = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if(exe == SYMBOL_TRADE_EXECUTION_REQUEST || exe == SYMBOL_TRADE_EXECUTION_INSTANT)
     {
      list[0] = ORDER_FILLING_FOK;
      list[1] = ORDER_FILLING_IOC;
      list[2] = ORDER_FILLING_RETURN;
      n = 3;
     }
   else
     {
      bool fok = ((fm & SYMBOL_FILLING_FOK) != 0);
      bool ioc = ((fm & SYMBOL_FILLING_IOC) != 0);
      if(fok)
        {
         list[n] = ORDER_FILLING_FOK;
         n++;
        }
      if(ioc)
        {
         list[n] = ORDER_FILLING_IOC;
         n++;
        }
      list[n] = ORDER_FILLING_RETURN;
      n++;
      if(!fok && n < 3)
        {
         list[n] = ORDER_FILLING_FOK;
         n++;
        }
      if(!ioc && n < 3)
        {
         list[n] = ORDER_FILLING_IOC;
         n++;
        }
     }
   int idx = (index < 0) ? 0 : (index % n);
   return list[idx];
  }

//+------------------------------------------------------------------+
int CEveTradeExecutor::FindOp(const ulong ticket, const int kind) const
  {
   int n = ArraySize(m_ops);
   for(int i = 0; i < n; i++)
      if(!m_ops[i].done && m_ops[i].ticket == ticket && m_ops[i].kind == kind)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
int CEveTradeExecutor::AddOp(const ulong ticket, const int kind, const int purpose, const string symbol, const double targetSL)
  {
   int n = ArraySize(m_ops);
   ArrayResize(m_ops, n + 1);
   m_ops[n].ticket            = ticket;
   m_ops[n].kind              = kind;
   m_ops[n].purpose           = purpose;
   m_ops[n].symbol            = symbol;
   m_ops[n].targetSL          = targetSL;
   m_ops[n].targetTP          = EVE_KEEP;
   m_ops[n].slFromEngine      = false;
   m_ops[n].sentAsync         = false;
   m_ops[n].requestId         = 0;
   m_ops[n].attempts          = 0;
   m_ops[n].sendCount         = 0;
   m_ops[n].nextAttemptMs     = 0;
   m_ops[n].awaitingVerify    = false;
   m_ops[n].verifyDeadlineMs  = 0;
   m_ops[n].volumeBefore      = 0.0;
   m_ops[n].lastRetcode       = 0;
   m_ops[n].lastLoggedRetcode = 0;
   m_ops[n].exhausted         = false;
   m_ops[n].blocked           = false;
   m_ops[n].fillingIndex      = 0;
   m_ops[n].createdMs         = GetTickCount64();
   m_ops[n].done              = false;
   return n;
  }

//+------------------------------------------------------------------+
void CEveTradeExecutor::RequestClose(const ulong ticket, const int purpose)
  {
   int i = FindOp(ticket, EVE_OP_CLOSE);
   if(i >= 0)
     {
      if(purpose == EVE_PURPOSE_GLOBAL_CLOSE_ALL)
         m_ops[i].purpose = purpose;
      return;
     }
   //--- a close supersedes a pending SL modification of the same position
   int m = FindOp(ticket, EVE_OP_MODIFY_SL);
   if(m >= 0)
      m_ops[m].done = true;
   string symbol = "";
   if(PositionSelectByTicket(ticket))
      symbol = PositionGetString(POSITION_SYMBOL);
   AddOp(ticket, EVE_OP_CLOSE, purpose, symbol, 0.0);
  }

//+------------------------------------------------------------------+
//| Requests an SL and/or TP change (EVE_KEEP = leave unchanged).     |
//| Requests made in the same cycle for the same position are merged |
//| into one TRADE_ACTION_SLTP: for the SL the most protective value |
//| wins, for the TP the latest value wins. Refused while a request  |
//| for this position is in flight or the position is being closed.  |
//+------------------------------------------------------------------+
bool CEveTradeExecutor::RequestStops(const ulong ticket, const double sl, const double tp, const int purpose)
  {
   if(sl <= 0.0 && tp <= 0.0)
      return false;
   if(FindOp(ticket, EVE_OP_CLOSE) >= 0)
      return false;
   if(purpose == EVE_PURPOSE_SL_ENGINE ? IsModifyBlocked(ticket) : IsSoftBlocked(ticket))
      return false;
   int i = FindOp(ticket, EVE_OP_MODIFY_SL);
   if(i >= 0)
     {
      if(m_ops[i].awaitingVerify || m_ops[i].sendCount > 0)
         return false;   // in flight: the caller re-plans after verification
      if(sl > 0.0)
        {
         ENUM_POSITION_TYPE ptype = POSITION_TYPE_BUY;
         if(PositionSelectByTicket(ticket))
            ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(m_ops[i].targetSL <= 0.0 || CEvePriceRiskCalculator::IsMoreProtective(ptype, sl, m_ops[i].targetSL))
            m_ops[i].targetSL = sl;
         if(purpose == EVE_PURPOSE_SL_ENGINE)
            m_ops[i].slFromEngine = true;
        }
      if(tp > 0.0)
         m_ops[i].targetTP = tp;
      return true;
     }
   string symbol = "";
   if(PositionSelectByTicket(ticket))
      symbol = PositionGetString(POSITION_SYMBOL);
   int n = AddOp(ticket, EVE_OP_MODIFY_SL, purpose, symbol, (sl > 0.0) ? sl : EVE_KEEP);
   m_ops[n].targetTP = (tp > 0.0) ? tp : EVE_KEEP;
   m_ops[n].slFromEngine = (purpose == EVE_PURPOSE_SL_ENGINE && sl > 0.0);
   return true;
  }

//+------------------------------------------------------------------+
void CEveTradeExecutor::RequestDeleteOrder(const ulong ticket, const int purpose)
  {
   if(FindOp(ticket, EVE_OP_DELETE_ORDER) >= 0)
      return;
   string symbol = "";
   if(OrderSelect(ticket))
      symbol = OrderGetString(ORDER_SYMBOL);
   AddOp(ticket, EVE_OP_DELETE_ORDER, purpose, symbol, 0.0);
  }

//+------------------------------------------------------------------+
void CEveTradeExecutor::CancelOpsOfKind(const int kind, const string why)
  {
   int cancelled = 0;
   int n = ArraySize(m_ops);
   for(int i = 0; i < n; i++)
     {
      if(!m_ops[i].done && m_ops[i].kind == kind)
        {
         m_ops[i].done = true;
         cancelled++;
        }
     }
   if(cancelled > 0)
      LogInfo("EXEC", "Cancelled " + IntegerToString(cancelled) + " pending " + EveOpKindName(kind) +
              " operation(s): " + why);
   Compact();
  }

//+------------------------------------------------------------------+
void CEveTradeExecutor::CancelAll(const string why)
  {
   int n = ArraySize(m_ops);
   int active = 0;
   for(int i = 0; i < n; i++)
      if(!m_ops[i].done)
         active++;
   ArrayResize(m_ops, 0);
   if(active > 0)
      LogWarning("EXEC", "Dropped " + IntegerToString(active) + " trade operation(s): " + why);
  }

//+------------------------------------------------------------------+
bool CEveTradeExecutor::HasActiveCloseOps(void) const
  {
   int n = ArraySize(m_ops);
   for(int i = 0; i < n; i++)
      if(!m_ops[i].done && m_ops[i].kind == EVE_OP_CLOSE)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
bool CEveTradeExecutor::HasActiveModifyOps(void) const
  {
   int n = ArraySize(m_ops);
   for(int i = 0; i < n; i++)
      if(!m_ops[i].done && m_ops[i].kind == EVE_OP_MODIFY_SL)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
bool CEveTradeExecutor::AnyCloseFailing(void) const
  {
   int n = ArraySize(m_ops);
   for(int i = 0; i < n; i++)
      if(!m_ops[i].done && m_ops[i].kind == EVE_OP_CLOSE && (m_ops[i].exhausted || m_ops[i].blocked))
         return true;
   return false;
  }

//+------------------------------------------------------------------+
int CEveTradeExecutor::ActiveOpCount(void) const
  {
   int count = 0;
   int n = ArraySize(m_ops);
   for(int i = 0; i < n; i++)
      if(!m_ops[i].done)
         count++;
   return count;
  }

//+------------------------------------------------------------------+
//| Per-ticket SL modification failure counters                      |
//+------------------------------------------------------------------+
int CEveTradeExecutor::CounterIndex(const ulong ticket) const
  {
   int n = ArraySize(m_counters);
   for(int i = 0; i < n; i++)
      if(m_counters[i].ticket == ticket)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
int CEveTradeExecutor::EnsureCounter(const ulong ticket)
  {
   int i = CounterIndex(ticket);
   if(i >= 0)
      return i;
   int n = ArraySize(m_counters);
   ArrayResize(m_counters, n + 1);
   m_counters[n].ticket         = ticket;
   m_counters[n].failures       = 0;
   m_counters[n].softFailures   = 0;
   m_counters[n].softBlockedUntilMs = 0;
   m_counters[n].blockedUntilMs = 0;
   m_counters[n].lastRetcode    = 0;
   return n;
  }

//+------------------------------------------------------------------+
//| Counted failure with growing back-off. Hard failures (an SL the  |
//| aggregate SL engine needs) count toward the fail-safe (max 10 s  |
//| back-off); soft failures (trailing / TP) only back off (max 30 s).|
//+------------------------------------------------------------------+
void CEveTradeExecutor::RegisterModifyFailure(const ulong ticket, const uint retcode, const bool hard)
  {
   int i = EnsureCounter(ticket);
   int count = 0;
   int cap = 10000;
   if(hard)
     {
      m_counters[i].failures++;
      count = m_counters[i].failures;
     }
   else
     {
      m_counters[i].softFailures++;
      count = m_counters[i].softFailures;
      cap = 30000;
     }
   m_counters[i].lastRetcode = retcode;
   int backoff = count * 1000;
   if(backoff > cap)
      backoff = cap;
   if(hard)
      m_counters[i].blockedUntilMs = GetTickCount64() + (ulong)backoff;
   else
      m_counters[i].softBlockedUntilMs = GetTickCount64() + (ulong)backoff;
  }

//+------------------------------------------------------------------+
//| Environment block (market closed etc.): not counted as failure.  |
//+------------------------------------------------------------------+
void CEveTradeExecutor::BlockModify(const ulong ticket, const uint retcode)
  {
   int i = EnsureCounter(ticket);
   m_counters[i].lastRetcode = retcode;
   m_counters[i].blockedUntilMs = GetTickCount64() + (ulong)EVE_SLOW_RETRY_MS;
  }

//+------------------------------------------------------------------+
int CEveTradeExecutor::ModifyFailures(const ulong ticket) const
  {
   int i = CounterIndex(ticket);
   return (i >= 0) ? m_counters[i].failures : 0;
  }

//+------------------------------------------------------------------+
bool CEveTradeExecutor::IsModifyBlocked(const ulong ticket) const
  {
   int i = CounterIndex(ticket);
   if(i < 0)
      return false;
   return (GetTickCount64() < m_counters[i].blockedUntilMs);
  }

//+------------------------------------------------------------------+
//| Blocked for trailing / TP requests (soft or hard back-off).      |
//+------------------------------------------------------------------+
bool CEveTradeExecutor::IsSoftBlocked(const ulong ticket) const
  {
   int i = CounterIndex(ticket);
   if(i < 0)
      return false;
   ulong now = GetTickCount64();
   return (now < m_counters[i].blockedUntilMs || now < m_counters[i].softBlockedUntilMs);
  }

//+------------------------------------------------------------------+
void CEveTradeExecutor::ResetModifyCounter(const ulong ticket)
  {
   int i = CounterIndex(ticket);
   if(i < 0)
      return;
   int n = ArraySize(m_counters);
   for(int k = i + 1; k < n; k++)
      m_counters[k - 1] = m_counters[k];
   ArrayResize(m_counters, n - 1);
  }

//+------------------------------------------------------------------+
void CEveTradeExecutor::PruneCounters(void)
  {
   int n = ArraySize(m_counters);
   int w = 0;
   for(int r = 0; r < n; r++)
     {
      if(!PositionSelectByTicket(m_counters[r].ticket))
         continue;
      if(w != r)
         m_counters[w] = m_counters[r];
      w++;
     }
   if(w != n)
      ArrayResize(m_counters, w);
  }

//+------------------------------------------------------------------+
void CEveTradeExecutor::Compact(void)
  {
   int n = ArraySize(m_ops);
   int w = 0;
   for(int r = 0; r < n; r++)
     {
      if(m_ops[r].done)
         continue;
      if(w != r)
         m_ops[w] = m_ops[r];
      w++;
     }
   if(w != n)
      ArrayResize(m_ops, w);
  }

//+------------------------------------------------------------------+
//| Schedules the next attempt after a failure                       |
//+------------------------------------------------------------------+
void CEveTradeExecutor::ScheduleRetry(const int i, const int rcClass, const string what)
  {
   ulong now = GetTickCount64();
   m_ops[i].attempts++;
   int a = m_ops[i].attempts;
   string kind = EveOpKindName(m_ops[i].kind);
   string tk = EveTicketStr(m_ops[i].ticket);

   if(rcClass == EVE_RCC_RETRY_SLOW)
     {
      bool first = !m_ops[i].blocked;
      m_ops[i].blocked = true;
      m_ops[i].nextAttemptMs = now + (ulong)EVE_SLOW_RETRY_MS;
      m_lastFailure = kind + " " + tk + " BLOCKED: " + what;
      if(first || (a % 20) == 0)
         LogCritical(kind, "BLOCKED " + tk + " (attempt " + IntegerToString(a) + "): " + what +
                     " - retrying every " + IntegerToString(EVE_SLOW_RETRY_MS / 1000) + " s until it succeeds");
      return;
     }

   m_ops[i].blocked = false;
   m_lastFailure = kind + " " + tk + " FAILED: " + what;
   if(a <= m_closeRetryCount)
     {
      m_ops[i].nextAttemptMs = now + (ulong)m_closeRetryDelayMs;
      LogWarning(kind, "FAILED " + tk + " - fast retry " + IntegerToString(a) + "/" + IntegerToString(m_closeRetryCount) +
                 " in " + IntegerToString(m_closeRetryDelayMs) + " ms: " + what);
      return;
     }
   bool firstExhaust = !m_ops[i].exhausted;
   m_ops[i].exhausted = true;
   m_ops[i].nextAttemptMs = now + (ulong)m_persistentRetryMs;
   if(firstExhaust)
      LogCritical(kind, "FAST RETRIES EXHAUSTED for " + tk + " - switching to PERSISTENT retry every " +
                  IntegerToString(m_persistentRetryMs) + " ms for as long as it is needed: " + what);
   else
      if((a % 10) == 0 || m_ops[i].lastLoggedRetcode != m_ops[i].lastRetcode)
         LogError(kind, "Persistent retry " + tk + " attempt " + IntegerToString(a) + ": " + what);
   m_ops[i].lastLoggedRetcode = m_ops[i].lastRetcode;
  }

//+------------------------------------------------------------------+
//| Sends one request. With async sending, true only means that the  |
//| terminal accepted it; the broker reply arrives in OnRequestResult |
//| and the result is always re-verified from the live state.        |
//+------------------------------------------------------------------+
bool CEveTradeExecutor::Send(MqlTradeRequest &req, MqlTradeResult &res, const int i)
  {
   m_ops[i].sentAsync = false;
   m_ops[i].requestId = 0;
   if(m_async)
     {
      bool sentAsync = OrderSendAsync(req, res);
      if(sentAsync)
        {
         m_ops[i].sentAsync = true;
         m_ops[i].requestId = res.request_id;
        }
      return sentAsync;
     }
   return OrderSend(req, res);
  }

//+------------------------------------------------------------------+
//| Broker reply of an asynchronous request (TRADE_TRANSACTION_REQUEST)|
//+------------------------------------------------------------------+
void CEveTradeExecutor::OnRequestResult(const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(result.request_id == 0)
      return;
   int n = ArraySize(m_ops);
   for(int i = 0; i < n; i++)
     {
      if(m_ops[i].done || !m_ops[i].sentAsync || !m_ops[i].awaitingVerify || m_ops[i].requestId != result.request_id)
         continue;
      uint rc = result.retcode;
      m_ops[i].lastRetcode = rc;
      int cls = ClassifyRetcode(rc);
      string kind = EveOpKindName(m_ops[i].kind);
      string tk = EveTicketStr(m_ops[i].ticket);
      if(cls == EVE_RCC_SUCCESS || cls == EVE_RCC_NO_CHANGE)
        {
         LogInfo(kind, "Broker accepted " + tk + " -> " + RetcodeText(rc) + " (verifying state)");
         return;
        }
      m_ops[i].awaitingVerify = false;
      m_ops[i].sentAsync = false;
      if(m_ops[i].kind == EVE_OP_MODIFY_SL)
        {
         if(cls == EVE_RCC_RETRY_SLOW)
            BlockModify(m_ops[i].ticket, rc);
         else
            RegisterModifyFailure(m_ops[i].ticket, rc, m_ops[i].slFromEngine);
         LogWarning("STOPS", "Broker REJECTED stops modification " + tk + " -> " + RetcodeText(rc) +
                    " [" + EvePurposeName(m_ops[i].purpose) + "]");
         m_ops[i].done = true;
         return;
        }
      if(cls == EVE_RCC_GONE)
        {
         m_ops[i].nextAttemptMs = 0;   // next Process() verifies that it is gone
         return;
        }
      if(cls == EVE_RCC_REFILL)
        {
         m_ops[i].fillingIndex++;
         cls = EVE_RCC_RETRY;
        }
      ScheduleRetry(i, cls, "broker rejected " + tk + " -> " + RetcodeText(rc));
      return;
     }
  }

//+------------------------------------------------------------------+
//| Close one position (closing deal only)                           |
//+------------------------------------------------------------------+
void CEveTradeExecutor::ProcessClose(const int i)
  {
   ulong now = GetTickCount64();
   ulong ticket = m_ops[i].ticket;
   string tk = EveTicketStr(ticket);

   if(!PositionSelectByTicket(ticket))
     {
      LogInfo("CLOSE", "VERIFIED CLOSED " + tk + " " + m_ops[i].symbol + " [" + EvePurposeName(m_ops[i].purpose) +
              "] requests sent: " + IntegerToString(m_ops[i].sendCount));
      m_ops[i].done = true;
      return;
     }
   double volume = PositionGetDouble(POSITION_VOLUME);

   if(m_ops[i].awaitingVerify)
     {
      if(volume < m_ops[i].volumeBefore - 0.00000001)
        {
         LogInfo("CLOSE", tk + " partially closed, remaining volume " + DoubleToString(volume, 2) + " - sending remainder");
         m_ops[i].awaitingVerify = false;
         m_ops[i].nextAttemptMs = 0;
        }
      else
        {
         if(now < m_ops[i].verifyDeadlineMs)
            return;   // wait: never send a duplicate close while the first one may still be in flight
         m_ops[i].awaitingVerify = false;
         m_ops[i].attempts++;
         m_ops[i].nextAttemptMs = 0;
         LogWarning("CLOSE", "Close of " + tk + " NOT verified within " + IntegerToString(m_verificationTimeoutMs) +
                    " ms (position still open, volume " + DoubleToString(volume, 2) + ") - re-sending");
        }
     }
   if(now < m_ops[i].nextAttemptMs)
      return;

   string symbol = PositionGetString(POSITION_SYMBOL);
   m_ops[i].symbol = symbol;
   ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
     {
      m_ops[i].lastRetcode = 0;
      ScheduleRetry(i, EVE_RCC_RETRY, "no price available for " + symbol);
      return;
     }
   double sendVol = volume;
   double vmax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(vmax > 0.0 && sendVol > vmax)
      sendVol = vmax;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action       = TRADE_ACTION_DEAL;
   req.position     = ticket;
   req.symbol       = symbol;
   req.volume       = sendVol;
   req.type         = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price        = (ptype == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
   req.deviation    = (ulong)m_deviationPoints;
   req.type_filling = FillingFor(symbol, m_ops[i].fillingIndex);
   req.magic        = EVE_RP_MAGIC;
   req.comment      = EVE_RP_COMMENT + " " + EvePurposeName(m_ops[i].purpose);

   ResetLastError();
   bool sent = Send(req, res, i);
   int err = GetLastError();
   m_ops[i].sendCount++;
   m_ops[i].lastRetcode = res.retcode;
   int cls = ClassifySendResult(res.retcode);
   if(sent && m_ops[i].sentAsync)
      cls = EVE_RCC_SUCCESS;
   else
      if(sent && res.retcode == 0)
         cls = EVE_RCC_RETRY;

   string info = tk + " " + symbol + " " + EvePositionTypeName(ptype) + " vol " + DoubleToString(sendVol, 2) +
                 ((sendVol < volume) ? " (chunk of " + DoubleToString(volume, 2) + ")" : "") +
                 " @" + DoubleToString(req.price, digits) + " dev " + IntegerToString(m_deviationPoints) + "pt" +
                 " fill " + EnumToString(req.type_filling) + " -> " +
                 (m_ops[i].sentAsync ? "SENT_ASYNC" : RetcodeText(res.retcode)) +
                 ((res.retcode == 0 && !sent) ? " err " + IntegerToString(err) : "") +
                 " [" + EvePurposeName(m_ops[i].purpose) + "]";

   if(cls == EVE_RCC_SUCCESS)
     {
      LogInfo("CLOSE", "Close request " + (m_ops[i].sentAsync ? "sent " : "accepted ") + info);
      m_ops[i].awaitingVerify   = true;
      m_ops[i].volumeBefore     = volume;
      m_ops[i].verifyDeadlineMs = now + (ulong)m_verificationTimeoutMs;
      m_ops[i].blocked          = false;
      if(!PositionSelectByTicket(ticket))
        {
         LogInfo("CLOSE", "VERIFIED CLOSED " + tk + " " + symbol + " [" + EvePurposeName(m_ops[i].purpose) + "]");
         m_ops[i].done = true;
        }
      return;
     }
   if(cls == EVE_RCC_GONE)
     {
      if(!PositionSelectByTicket(ticket))
        {
         LogInfo("CLOSE", "VERIFIED CLOSED " + tk + " (server reports position already closed) " + info);
         m_ops[i].done = true;
         return;
        }
      cls = EVE_RCC_RETRY;
     }
   if(cls == EVE_RCC_REFILL)
     {
      m_ops[i].fillingIndex++;
      cls = EVE_RCC_RETRY;
     }
   if(cls == EVE_RCC_NO_CHANGE)
      cls = EVE_RCC_RETRY;
   ScheduleRetry(i, cls, info);
  }

//+------------------------------------------------------------------+
//| Modify SL and/or TP of one position in a single request          |
//+------------------------------------------------------------------+
void CEveTradeExecutor::ProcessModify(const int i)
  {
   ulong now = GetTickCount64();
   ulong ticket = m_ops[i].ticket;
   string tk = EveTicketStr(ticket);

   if(!PositionSelectByTicket(ticket))
     {
      m_ops[i].done = true;   // position no longer exists - nothing to modify
      return;
     }
   string symbol = PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   SEveSymbolSnapshot s;
   bool haveSym = EveReadSymbol(symbol, s);
   double ts = s.tickSize;
   if(ts <= 0.0)
      ts = 0.00001;
   int digits = s.digits;
   double tSL = m_ops[i].targetSL;
   double tTP = m_ops[i].targetTP;
   bool wantSL = (tSL > 0.0);
   bool wantTP = (tTP > 0.0);
   bool slOk = (!wantSL || MathAbs(curSL - tSL) < ts * 0.5);
   bool tpOk = (!wantTP || MathAbs(curTP - tTP) < ts * 0.5);

   //--- verified?
   if(slOk && tpOk)
     {
      if(m_ops[i].sendCount > 0)
         LogInfo("STOPS", "VERIFIED " + tk + " " + symbol + " SL=" + DoubleToString(curSL, digits) +
                 " TP=" + DoubleToString(curTP, digits) + " [" + EvePurposeName(m_ops[i].purpose) + "]");
      ResetModifyCounter(ticket);
      m_ops[i].done = true;
      return;
     }
   if(m_ops[i].awaitingVerify)
     {
      if(now < m_ops[i].verifyDeadlineMs)
         return;
      LogWarning("STOPS", "Modification of " + tk + " NOT verified within " + IntegerToString(m_verificationTimeoutMs) +
                 " ms (SL " + DoubleToString(curSL, digits) + " / wanted " + (wantSL ? DoubleToString(tSL, digits) : "keep") +
                 ", TP " + DoubleToString(curTP, digits) + " / wanted " + (wantTP ? DoubleToString(tTP, digits) : "keep") + ")");
      RegisterModifyFailure(ticket, m_ops[i].lastRetcode, m_ops[i].slFromEngine);
      m_ops[i].done = true;
      return;
     }

   //--- never-widen guard for the SL part (second line of defence)
   if(wantSL && !slOk && curSL > 0.0 && !CEvePriceRiskCalculator::IsMoreProtective(ptype, tSL, curSL))
     {
      bool locksProfit = CEvePriceRiskCalculator::StopLocksProfit(ptype, curSL, open);
      if(m_preserveSL || locksProfit)
        {
         LogError("STOPS", "REFUSED SL change that would WIDEN the stop of " + tk + " (" + DoubleToString(curSL, digits) +
                  " -> " + DoubleToString(tSL, digits) + ")" +
                  (locksProfit ? " - current stop locks profit" : " - never-widen protection is ON"));
         wantSL = false;
         m_ops[i].targetSL = EVE_KEEP;
        }
     }
   if(!haveSym)
     {
      LogWarning("STOPS", "No market data for " + symbol + " - modification of " + tk + " postponed");
      m_ops[i].done = true;
      return;
     }
   if(wantSL && !slOk && !CEvePriceRiskCalculator::IsLegalSL(ptype, tSL, s, 0))
     {
      LogWarning("STOPS", "Planned SL " + DoubleToString(tSL, digits) + " for " + tk + " is no longer legal (bid " +
                 DoubleToString(s.bid, digits) + " ask " + DoubleToString(s.ask, digits) + ") - will re-plan");
      wantSL = false;
      m_ops[i].targetSL = EVE_KEEP;
     }
   if(wantTP && !tpOk && !CEvePriceRiskCalculator::IsLegalTP(ptype, tTP, s, 0))
     {
      LogWarning("STOPS", "Planned TP " + DoubleToString(tTP, digits) + " for " + tk + " is no longer legal (bid " +
                 DoubleToString(s.bid, digits) + " ask " + DoubleToString(s.ask, digits) + ") - will re-plan");
      wantTP = false;
      m_ops[i].targetTP = EVE_KEEP;
     }
   bool needSL = (wantSL && !slOk);
   bool needTP = (wantTP && !tpOk);
   if(!needSL && !needTP)
     {
      m_ops[i].done = true;
      return;
     }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = symbol;
   req.sl       = needSL ? NormalizeDouble(tSL, digits) : curSL;   // unchanged values are re-sent as they are
   req.tp       = needTP ? NormalizeDouble(tTP, digits) : curTP;   // (an SL change never removes the TP, audit B-05)
   req.magic    = EVE_RP_MAGIC;

   ResetLastError();
   bool sent = Send(req, res, i);
   int err = GetLastError();
   m_ops[i].sendCount++;
   m_ops[i].lastRetcode = res.retcode;
   int cls = ClassifySendResult(res.retcode);
   if(sent && m_ops[i].sentAsync)
      cls = EVE_RCC_SUCCESS;
   else
      if(sent && res.retcode == 0)
         cls = EVE_RCC_RETRY;

   string info = tk + " " + symbol + " " + EvePositionTypeName(ptype) +
                 " SL " + DoubleToString(curSL, digits) + " -> " + DoubleToString(req.sl, digits) +
                 " TP " + DoubleToString(curTP, digits) + " -> " + DoubleToString(req.tp, digits) + " -> " +
                 (m_ops[i].sentAsync ? "SENT_ASYNC" : RetcodeText(res.retcode)) +
                 ((res.retcode == 0 && !sent) ? " err " + IntegerToString(err) : "") +
                 " [" + EvePurposeName(m_ops[i].purpose) + "]";

   if(cls == EVE_RCC_SUCCESS)
     {
      LogInfo("STOPS", "Stops modification " + (m_ops[i].sentAsync ? "sent " : "accepted ") + info);
      m_ops[i].awaitingVerify = true;
      m_ops[i].verifyDeadlineMs = now + (ulong)m_verificationTimeoutMs;
      return;
     }
   if(cls == EVE_RCC_NO_CHANGE)
     {
      bool okNow = false;
      if(PositionSelectByTicket(ticket))
        {
         double sl2 = PositionGetDouble(POSITION_SL);
         double tp2 = PositionGetDouble(POSITION_TP);
         okNow = ((!needSL || MathAbs(sl2 - tSL) < ts * 0.5) && (!needTP || MathAbs(tp2 - tTP) < ts * 0.5));
        }
      if(okNow)
        {
         ResetModifyCounter(ticket);
         LogInfo("STOPS", "Stops already at target " + info);
        }
      else
        {
         RegisterModifyFailure(ticket, res.retcode, m_ops[i].slFromEngine);
         LogWarning("STOPS", "NO_CHANGES reported but stops differ " + info);
        }
      m_ops[i].done = true;
      return;
     }
   if(cls == EVE_RCC_GONE)
     {
      m_ops[i].done = true;
      return;
     }
   if(cls == EVE_RCC_RETRY_SLOW)
     {
      BlockModify(ticket, res.retcode);
      LogWarning("STOPS", "Stops modification BLOCKED " + info + " - retry in " + IntegerToString(EVE_SLOW_RETRY_MS / 1000) +
                 " s (not counted as failure)");
      m_ops[i].done = true;
      return;
     }
   RegisterModifyFailure(ticket, res.retcode, m_ops[i].slFromEngine);
   LogWarning("STOPS", "Stops modification FAILED " + info + " (consecutive SL-engine failures " +
              IntegerToString(ModifyFailures(ticket)) + ")");
   m_ops[i].done = true;
  }

//+------------------------------------------------------------------+
//| Delete one pending order                                         |
//+------------------------------------------------------------------+
void CEveTradeExecutor::ProcessDelete(const int i)
  {
   ulong now = GetTickCount64();
   ulong ticket = m_ops[i].ticket;
   string tk = EveTicketStr(ticket);

   if(!OrderSelect(ticket))
     {
      LogInfo("PENDING", "Pending order " + tk + " " + m_ops[i].symbol + " VERIFIED deleted");
      m_ops[i].done = true;
      return;
     }
   if(m_ops[i].awaitingVerify)
     {
      if(now < m_ops[i].verifyDeadlineMs)
         return;
      m_ops[i].awaitingVerify = false;
      m_ops[i].attempts++;
      m_ops[i].nextAttemptMs = 0;
      LogWarning("PENDING", "Deletion of pending order " + tk + " NOT verified - re-sending");
     }
   if(now < m_ops[i].nextAttemptMs)
      return;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_REMOVE;
   req.order  = ticket;
   req.magic  = EVE_RP_MAGIC;

   ResetLastError();
   bool sent = Send(req, res, i);
   int err = GetLastError();
   m_ops[i].sendCount++;
   m_ops[i].lastRetcode = res.retcode;
   int cls = ClassifySendResult(res.retcode);
   if(sent && m_ops[i].sentAsync)
      cls = EVE_RCC_SUCCESS;
   else
      if(sent && res.retcode == 0)
         cls = EVE_RCC_RETRY;
   string info = tk + " " + m_ops[i].symbol + " -> " + (m_ops[i].sentAsync ? "SENT_ASYNC" : RetcodeText(res.retcode)) +
                 ((res.retcode == 0 && !sent) ? " err " + IntegerToString(err) : "");

   if(cls == EVE_RCC_SUCCESS)
     {
      LogInfo("PENDING", "Pending order deletion " + (m_ops[i].sentAsync ? "sent " : "accepted ") + info);
      m_ops[i].awaitingVerify = true;
      m_ops[i].verifyDeadlineMs = now + (ulong)m_verificationTimeoutMs;
      if(!OrderSelect(ticket))
        {
         LogInfo("PENDING", "Pending order " + tk + " VERIFIED deleted");
         m_ops[i].done = true;
        }
      return;
     }
   if(!OrderSelect(ticket))
     {
      LogInfo("PENDING", "Pending order " + tk + " no longer exists (" + info + ")");
      m_ops[i].done = true;
      return;
     }
   if(cls == EVE_RCC_REFILL || cls == EVE_RCC_NO_CHANGE || cls == EVE_RCC_GONE)
      cls = EVE_RCC_RETRY;
   ScheduleRetry(i, cls, "delete pending " + info);
  }

//+------------------------------------------------------------------+
//| Main pump: called every cycle                                    |
//+------------------------------------------------------------------+
void CEveTradeExecutor::Process(void)
  {
   int n = ArraySize(m_ops);
   for(int i = 0; i < n; i++)
     {
      if(m_ops[i].done)
         continue;
      if(m_ops[i].kind == EVE_OP_CLOSE)
         ProcessClose(i);
      else
         if(m_ops[i].kind == EVE_OP_MODIFY_SL)
            ProcessModify(i);
         else
            if(m_ops[i].kind == EVE_OP_DELETE_ORDER)
               ProcessDelete(i);
     }
   Compact();
   if(ArraySize(m_counters) > 0)
      PruneCounters();
  }

#endif // EVE_RISK_TRADEEXECUTOR_MQH
//+------------------------------------------------------------------+
