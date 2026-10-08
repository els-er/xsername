//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|               EVE IDR Risk Protector - shared types and helpers  |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_DEFINES_MQH
#define EVE_RISK_DEFINES_MQH

#define EVE_RP_NAME              "EVE IDR RISK PROTECTOR"
#define EVE_RP_VERSION           "1.00"
#define EVE_RP_REQUIRED_CURRENCY "IDR"
#define EVE_RP_MAGIC             770010
#define EVE_RP_COMMENT           "EVE-RP"

// Tolerance used in money comparisons. Totals are normalized to the
// account currency digits first, so this is far below one Rupiah unit.
#define EVE_EPS                  0.0000001

// Retry interval used while the market/trading is blocked (market closed,
// AutoTrading disabled, trade disabled). Retries never stop while a
// position that must be closed is still open.
#define EVE_SLOW_RETRY_MS        5000

// Instance-guard heartbeat considered stale after this many milliseconds.
#define EVE_HEARTBEAT_STALE_MS   10000

// Retcodes that may be missing as named constants on older terminals.
#define EVE_RC_INVALID_CLOSE_VOLUME 10038
#define EVE_RC_CLOSE_ORDER_EXIST    10039
#define EVE_RC_LIMIT_POSITIONS      10040
#define EVE_RC_CLOSE_ONLY           10044
#define EVE_RC_FIFO_CLOSE           10045

//--- trade operation kinds handled by the executor
#define EVE_OP_CLOSE           0
#define EVE_OP_MODIFY_SL       1
#define EVE_OP_DELETE_ORDER    2

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_EVE_STATE
  {
   EVE_STATE_INIT                 = 0,
   EVE_STATE_VALIDATING           = 1,
   EVE_STATE_SAFE_DISABLED        = 2,
   EVE_STATE_ARMED                = 3,
   EVE_STATE_PROTECTION_TRIGGERED = 4,
   EVE_STATE_CLOSING_ALL          = 5,
   EVE_STATE_CLOSE_FAILED         = 6,
   EVE_STATE_ALL_POSITIONS_CLOSED = 7,
   EVE_STATE_LOCKED               = 8,
   EVE_STATE_STANDBY              = 9
  };

enum ENUM_EVE_REASON
  {
   EVE_REASON_NONE                          = 0,
   EVE_REASON_GLOBAL_FLOATING_LOSS          = 1,
   EVE_REASON_GLOBAL_FLOATING_PROFIT_TARGET = 2
  };

enum ENUM_EVE_SCOPE
  {
   EVE_SCOPE_ALL_ACCOUNT_POSITIONS = 0 // ALL ACCOUNT POSITIONS (every symbol, magic, manual and EA)
  };

enum ENUM_EVE_SL_ALLOCATION
  {
   EVE_SL_ALLOC_BASKET_COMMON_PRICE    = 0, // BASKET: one SL price per symbol+direction (total of all entries)
   EVE_SL_ALLOC_PROPORTIONAL_TO_VOLUME = 1  // PROPORTIONAL TO VOLUME: fixed share of budget per position
  };

enum ENUM_EVE_SL_FAILSAFE
  {
   EVE_FAILSAFE_CLOSE_POSITION    = 0, // CLOSE POSITION
   EVE_FAILSAFE_LEAVE_UNPROTECTED = 1  // LEAVE UNPROTECTED (critical alert only)
  };

enum ENUM_EVE_LOCK_NEWPOS_POLICY
  {
   EVE_LOCKPOL_CLOSE_IMMEDIATELY = 0, // CLOSE NEW POSITION IMMEDIATELY (stay LOCKED)
   EVE_LOCKPOL_ALERT_ONLY        = 1  // ALERT ONLY (leave new position open)
  };

enum ENUM_EVE_LOG_LEVEL
  {
   EVE_LOG_INFO     = 0,
   EVE_LOG_WARNING  = 1,
   EVE_LOG_ERROR    = 2,
   EVE_LOG_CRITICAL = 3
  };

enum ENUM_EVE_PURPOSE
  {
   EVE_PURPOSE_GLOBAL_CLOSE_ALL = 0,
   EVE_PURPOSE_LOCK_POLICY      = 1,
   EVE_PURPOSE_SL_FAILSAFE      = 2,
   EVE_PURPOSE_SL_ENGINE        = 3,
   EVE_PURPOSE_PENDING_CANCEL   = 4
  };

//+------------------------------------------------------------------+
//| Configuration (filled from EA inputs)                            |
//+------------------------------------------------------------------+
struct SEveConfig
  {
   //--- scope
   ENUM_EVE_SCOPE              scope;
   //--- feature A: global floating loss
   bool                        enableGlobalLoss;
   long                        maxGlobalLossIDR;
   bool                        lockAfterGlobalLoss;
   bool                        requireManualResetLoss;
   //--- feature B: global floating profit
   bool                        enableGlobalProfit;
   long                        globalProfitTargetIDR;
   bool                        lockAfterGlobalProfit;
   bool                        requireManualResetProfit;
   //--- feature C: lock mode
   ENUM_EVE_LOCK_NEWPOS_POLICY lockedNewPositionPolicy;
   bool                        cancelPendingWhenLocked;
   //--- feature D: aggregate SL
   bool                        enableAggregateSL;
   long                        maxAggregateSLRiskIDR;
   bool                        autoApplySLToNewPositions;
   bool                        rebalanceOnNewEntry;
   ENUM_EVE_SL_ALLOCATION      slAllocation;
   bool                        preserveMoreProtectiveSL;
   ENUM_EVE_SL_FAILSAFE        slFailSafe;
   double                      slSafetyMarginPct;
   int                         slExtraBufferTicks;
   int                         slModifyFailuresBeforeFailSafe;
   //--- execution
   int                         closeRetryCount;
   int                         closeRetryDelayMs;
   int                         verificationTimeoutMs;
   int                         persistentRetryIntervalMs;
   int                         emergencyDeviationPoints;
   int                         reconciliationIntervalMs;
   //--- notifications / logging / dashboard
   bool                        enablePush;
   bool                        enableAlerts;
   bool                        enableFileLog;
   bool                        showDashboard;
   int                         dashboardX;
   int                         dashboardY;
   //--- test harness only (ignored outside the Strategy Tester)
   bool                        testAllowAnyCurrency;
  };

//+------------------------------------------------------------------+
//| Defaults (spec section 35, with user decision Q4: lock OFF)      |
//+------------------------------------------------------------------+
void EveConfigSetDefaults(SEveConfig &c)
  {
   c.scope                          = EVE_SCOPE_ALL_ACCOUNT_POSITIONS;
   c.enableGlobalLoss               = true;
   c.maxGlobalLossIDR               = 500000;
   c.lockAfterGlobalLoss            = false;
   c.requireManualResetLoss         = true;
   c.enableGlobalProfit             = false;
   c.globalProfitTargetIDR          = 500000;
   c.lockAfterGlobalProfit          = false;
   c.requireManualResetProfit       = false;
   c.lockedNewPositionPolicy        = EVE_LOCKPOL_CLOSE_IMMEDIATELY;
   c.cancelPendingWhenLocked        = true;
   c.enableAggregateSL              = true;
   c.maxAggregateSLRiskIDR          = 500000;
   c.autoApplySLToNewPositions      = true;
   c.rebalanceOnNewEntry            = true;
   c.slAllocation                   = EVE_SL_ALLOC_BASKET_COMMON_PRICE;
   c.preserveMoreProtectiveSL       = true;
   c.slFailSafe                     = EVE_FAILSAFE_CLOSE_POSITION;
   c.slSafetyMarginPct              = 1.0;
   c.slExtraBufferTicks             = 1;
   c.slModifyFailuresBeforeFailSafe = 5;
   c.closeRetryCount                = 5;
   c.closeRetryDelayMs              = 250;
   c.verificationTimeoutMs          = 5000;
   c.persistentRetryIntervalMs      = 1000;
   c.emergencyDeviationPoints       = 1000;
   c.reconciliationIntervalMs       = 250;
   c.enablePush                     = true;
   c.enableAlerts                   = true;
   c.enableFileLog                  = true;
   c.showDashboard                  = true;
   c.dashboardX                     = 10;
   c.dashboardY                     = 25;
   c.testAllowAnyCurrency           = false;
  }

//+------------------------------------------------------------------+
//| Name helpers                                                     |
//+------------------------------------------------------------------+
string EveStateName(const ENUM_EVE_STATE s)
  {
   switch(s)
     {
      case EVE_STATE_INIT:                 return "INIT";
      case EVE_STATE_VALIDATING:           return "VALIDATING";
      case EVE_STATE_SAFE_DISABLED:        return "SAFE_DISABLED";
      case EVE_STATE_ARMED:                return "ARMED";
      case EVE_STATE_PROTECTION_TRIGGERED: return "PROTECTION_TRIGGERED";
      case EVE_STATE_CLOSING_ALL:          return "CLOSING_ALL";
      case EVE_STATE_CLOSE_FAILED:         return "CLOSE_FAILED";
      case EVE_STATE_ALL_POSITIONS_CLOSED: return "ALL_POSITIONS_CLOSED";
      case EVE_STATE_LOCKED:               return "LOCKED";
      case EVE_STATE_STANDBY:              return "STANDBY";
     }
   return "UNKNOWN";
  }

// Short label used on the chart dashboard (spec section 20).
string EveStateDashboardLabel(const ENUM_EVE_STATE s)
  {
   switch(s)
     {
      case EVE_STATE_INIT:                 return "INIT";
      case EVE_STATE_VALIDATING:           return "VALIDATING";
      case EVE_STATE_SAFE_DISABLED:        return "ERROR (SAFE_DISABLED)";
      case EVE_STATE_ARMED:                return "ARMED";
      case EVE_STATE_PROTECTION_TRIGGERED: return "PROTECTION";
      case EVE_STATE_CLOSING_ALL:          return "CLOSING";
      case EVE_STATE_CLOSE_FAILED:         return "CLOSING (FAILED-RETRYING)";
      case EVE_STATE_ALL_POSITIONS_CLOSED: return "ALL CLOSED";
      case EVE_STATE_LOCKED:               return "LOCKED";
      case EVE_STATE_STANDBY:              return "STANDBY";
     }
   return "UNKNOWN";
  }

string EveReasonName(const ENUM_EVE_REASON r)
  {
   switch(r)
     {
      case EVE_REASON_NONE:                          return "NONE";
      case EVE_REASON_GLOBAL_FLOATING_LOSS:          return "GLOBAL_FLOATING_LOSS";
      case EVE_REASON_GLOBAL_FLOATING_PROFIT_TARGET: return "GLOBAL_FLOATING_PROFIT_TARGET";
     }
   return "UNKNOWN";
  }

string EveLevelName(const ENUM_EVE_LOG_LEVEL l)
  {
   switch(l)
     {
      case EVE_LOG_INFO:     return "INFO";
      case EVE_LOG_WARNING:  return "WARNING";
      case EVE_LOG_ERROR:    return "ERROR";
      case EVE_LOG_CRITICAL: return "CRITICAL";
     }
   return "UNKNOWN";
  }

string EvePurposeName(const int purpose)
  {
   switch(purpose)
     {
      case EVE_PURPOSE_GLOBAL_CLOSE_ALL: return "GLOBAL_CLOSE_ALL";
      case EVE_PURPOSE_LOCK_POLICY:      return "LOCK_POLICY";
      case EVE_PURPOSE_SL_FAILSAFE:      return "SL_FAILSAFE";
      case EVE_PURPOSE_SL_ENGINE:        return "SL_ENGINE";
      case EVE_PURPOSE_PENDING_CANCEL:   return "PENDING_CANCEL";
     }
   return "UNKNOWN";
  }

string EveOpKindName(const int kind)
  {
   switch(kind)
     {
      case EVE_OP_CLOSE:        return "CLOSE";
      case EVE_OP_MODIFY_SL:    return "MODIFY_SL";
      case EVE_OP_DELETE_ORDER: return "DELETE_ORDER";
     }
   return "UNKNOWN";
  }

bool EveIsClosingState(const ENUM_EVE_STATE s)
  {
   return (s == EVE_STATE_PROTECTION_TRIGGERED ||
           s == EVE_STATE_CLOSING_ALL ||
           s == EVE_STATE_CLOSE_FAILED);
  }

string EveTicketStr(const ulong ticket)
  {
   return "#" + IntegerToString((long)ticket);
  }

string EvePositionTypeName(const ENUM_POSITION_TYPE t)
  {
   return (t == POSITION_TYPE_BUY) ? "BUY" : "SELL";
  }

string EveBoolOnOff(const bool v)
  {
   return v ? "ON" : "OFF";
  }

string EveTruncate(const string s, const int maxLen)
  {
   if(StringLen(s) <= maxLen)
      return s;
   if(maxLen <= 3)
      return StringSubstr(s, 0, maxLen);
   return StringSubstr(s, 0, maxLen - 3) + "...";
  }

bool EveIsPendingOrderType(const ENUM_ORDER_TYPE t)
  {
   return (t == ORDER_TYPE_BUY_LIMIT || t == ORDER_TYPE_SELL_LIMIT ||
           t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_SELL_STOP ||
           t == ORDER_TYPE_BUY_STOP_LIMIT || t == ORDER_TYPE_SELL_STOP_LIMIT);
  }

// 32-bit FNV-1a hash (used for persistence keys and config checksum).
uint EveFnv1a(const string s)
  {
   uint h = (uint)2166136261;
   int len = StringLen(s);
   for(int i = 0; i < len; i++)
     {
      h ^= (uint)StringGetCharacter(s, i);
      h *= 16777619;
     }
   return h;
  }

string EveDeinitReasonText(const int reason)
  {
   switch(reason)
     {
      case REASON_PROGRAM:     return "EA stopped (ExpertRemove)";
      case REASON_REMOVE:      return "EA removed from chart";
      case REASON_RECOMPILE:   return "EA recompiled";
      case REASON_CHARTCHANGE: return "symbol/timeframe changed";
      case REASON_CHARTCLOSE:  return "chart closed";
      case REASON_PARAMETERS:  return "input parameters changed";
      case REASON_ACCOUNT:     return "account changed";
      case REASON_TEMPLATE:    return "template applied";
      case REASON_INITFAILED:  return "OnInit failed";
      case REASON_CLOSE:       return "terminal closed";
     }
   return "reason " + IntegerToString(reason);
  }

#endif // EVE_RISK_DEFINES_MQH
//+------------------------------------------------------------------+
