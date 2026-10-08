//+------------------------------------------------------------------+
//|                                        EVE_IDR_RiskProtector.mq5 |
//|                EVE IDR Risk Protector - account-wide IDR risk EA |
//+------------------------------------------------------------------+
//| RISK-CONTROL EA ONLY. It never opens a trade, never generates     |
//| signals, never averages down, no martingale, no grid.             |
//|                                                                  |
//| SCOPE: ALL OPEN POSITIONS IN THIS ACCOUNT - every symbol, every   |
//| magic number, manual trades and trades of other EAs. Attaching it |
//| to an XAUUSD chart does NOT limit it to XAUUSD.                   |
//|                                                                  |
//| All money inputs are in IDR (Rupiah). The account currency must   |
//| be IDR, otherwise the EA stays in SAFE_DISABLED.                  |
//|                                                                  |
//| A limit is a TRIGGER THRESHOLD, not a guaranteed realized result: |
//| price movement, spread, slippage, latency and gaps can make the   |
//| realized loss/profit differ from the configured amount.           |
//+------------------------------------------------------------------+
#property copyright   "EVE"
#property version     "1.00"
#property description "EVE IDR Risk Protector v1.00 - risk-control EA (never opens trades)."
#property description "Scope: ALL positions in the account (all symbols, manual + other EAs)."
#property description "Global floating LOSS close-all, floating PROFIT close-all, aggregate IDR Stop Loss."
#property description "All amounts in IDR. Limits are trigger thresholds, not guaranteed fill results."

#include <EVE_Risk\RiskProtectorApp.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== SCOPE: ALL POSITIONS IN THIS ACCOUNT (every symbol, manual + other EAs) ==="
input ENUM_EVE_SCOPE ProtectionScope = EVE_SCOPE_ALL_ACCOUNT_POSITIONS;                   // PROTECTION SCOPE

input group "=== A. GLOBAL FLOATING LOSS PROTECTION (IDR) - closes ALL positions ==="
input bool EnableGlobalFloatingLossProtection = true;                                     // ENABLE GLOBAL FLOATING LOSS PROTECTION
input long MaxGlobalFloatingLossIDR           = 500000;                                   // MAX GLOBAL FLOATING LOSS (IDR)
input bool LockAfterGlobalTrigger             = false;                                    // LOCK AFTER GLOBAL LOSS TRIGGER
input bool RequireManualReset                 = true;                                     // REQUIRE MANUAL RESET (must be true if lock ON)

input group "=== B. GLOBAL FLOATING PROFIT AUTO-CLOSE (IDR) - closes ALL positions ==="
input bool EnableGlobalFloatingProfitAutoClose = false;                                   // ENABLE GLOBAL FLOATING PROFIT AUTO-CLOSE
input long GlobalFloatingProfitTargetIDR       = 500000;                                  // GLOBAL FLOATING PROFIT TARGET (IDR)
input bool LockAfterGlobalProfitTrigger        = false;                                   // LOCK AFTER GLOBAL PROFIT TRIGGER
input bool RequireManualResetAfterProfit       = false;                                   // REQUIRE MANUAL RESET AFTER PROFIT (must be true if lock ON)

input group "=== C. LOCK MODE (only when a lock above is ON) ==="
input ENUM_EVE_LOCK_NEWPOS_POLICY LockedNewPositionPolicy = EVE_LOCKPOL_CLOSE_IMMEDIATELY; // NEW POSITION WHILE LOCKED
input bool CancelPendingOrdersWhenLocked = true;                                          // CANCEL PENDING ORDERS WHEN LOCKED

input group "=== D. AGGREGATE IDR STOP LOSS (server-side SL on every position) ==="
input bool EnableAggregateIDRSL                      = true;                              // ENABLE AGGREGATE IDR SL
input long MaxAggregateSLRiskIDR                     = 500000;                            // MAX AGGREGATE SL RISK (IDR) - total loss if all SLs hit
input bool AutoApplySLToNewPositions                 = true;                              // AUTO-APPLY SL TO NEW POSITIONS
input bool RebalanceExistingPositionsOnNewEntry      = true;                              // REBALANCE EXISTING POSITIONS ON NEW ENTRY
input ENUM_EVE_SL_ALLOCATION SLAllocationMethod      = EVE_SL_ALLOC_BASKET_COMMON_PRICE;  // SL ALLOCATION METHOD
input bool PreserveMoreProtectiveExistingSL          = true;                              // PRESERVE MORE PROTECTIVE EXISTING SL (never widen)
input ENUM_EVE_SL_FAILSAFE FailSafeWhenCompliantSLImpossible = EVE_FAILSAFE_CLOSE_POSITION; // FAIL-SAFE WHEN COMPLIANT SL IMPOSSIBLE
input double SLBudgetSafetyMarginPct                 = 1.0;                               // SL BUDGET SAFETY MARGIN (%) vs USD/IDR drift
input int SLExtraBufferTicks                         = 1;                                 // SL EXTRA DISTANCE BUFFER (ticks) beyond broker stop level
input int SLModifyFailuresBeforeFailSafe             = 5;                                 // SL MODIFY FAILURES BEFORE FAIL-SAFE

input group "=== EXECUTION / RETRY / VERIFICATION ==="
input int CloseRetryCount                  = 5;                                           // CLOSE RETRY COUNT (fast burst)
input int CloseRetryDelayMs                = 250;                                         // CLOSE RETRY DELAY (ms)
input int VerificationTimeoutMs            = 5000;                                        // VERIFICATION TIMEOUT (ms)
input int PersistentRetryIntervalMs        = 1000;                                        // PERSISTENT RETRY INTERVAL AFTER BURST (ms)
input int EmergencyCloseMaxDeviationPoints = 1000;                                        // EMERGENCY CLOSE MAX DEVIATION (points)
input int ReconciliationIntervalMs         = 250;                                         // RECONCILIATION TIMER (ms)

input group "=== NOTIFICATIONS / LOG / DASHBOARD ==="
input bool EnablePushNotifications = true;                                                // PUSH NOTIFICATIONS (MetaQuotes ID)
input bool EnableAlerts            = true;                                                // ALERT POPUPS FOR CRITICAL EVENTS
input bool EnableFileLog           = true;                                                // WRITE DAILY LOG FILE (MQL5\Files)
input bool ShowDashboard           = true;                                                // SHOW DASHBOARD
input int  DashboardX              = 10;                                                  // DASHBOARD X (px)
input int  DashboardY              = 25;                                                  // DASHBOARD Y (px)

CEveRiskProtectorApp g_app;

//+------------------------------------------------------------------+
int OnInit()
  {
   SEveConfig c;
   EveConfigSetDefaults(c);
   c.scope                          = ProtectionScope;
   c.enableGlobalLoss               = EnableGlobalFloatingLossProtection;
   c.maxGlobalLossIDR               = MaxGlobalFloatingLossIDR;
   c.lockAfterGlobalLoss            = LockAfterGlobalTrigger;
   c.requireManualResetLoss         = RequireManualReset;
   c.enableGlobalProfit             = EnableGlobalFloatingProfitAutoClose;
   c.globalProfitTargetIDR          = GlobalFloatingProfitTargetIDR;
   c.lockAfterGlobalProfit          = LockAfterGlobalProfitTrigger;
   c.requireManualResetProfit       = RequireManualResetAfterProfit;
   c.lockedNewPositionPolicy        = LockedNewPositionPolicy;
   c.cancelPendingWhenLocked        = CancelPendingOrdersWhenLocked;
   c.enableAggregateSL              = EnableAggregateIDRSL;
   c.maxAggregateSLRiskIDR          = MaxAggregateSLRiskIDR;
   c.autoApplySLToNewPositions      = AutoApplySLToNewPositions;
   c.rebalanceOnNewEntry            = RebalanceExistingPositionsOnNewEntry;
   c.slAllocation                   = SLAllocationMethod;
   c.preserveMoreProtectiveSL       = PreserveMoreProtectiveExistingSL;
   c.slFailSafe                     = FailSafeWhenCompliantSLImpossible;
   c.slSafetyMarginPct              = SLBudgetSafetyMarginPct;
   c.slExtraBufferTicks             = SLExtraBufferTicks;
   c.slModifyFailuresBeforeFailSafe = SLModifyFailuresBeforeFailSafe;
   c.closeRetryCount                = CloseRetryCount;
   c.closeRetryDelayMs              = CloseRetryDelayMs;
   c.verificationTimeoutMs          = VerificationTimeoutMs;
   c.persistentRetryIntervalMs      = PersistentRetryIntervalMs;
   c.emergencyDeviationPoints       = EmergencyCloseMaxDeviationPoints;
   c.reconciliationIntervalMs       = ReconciliationIntervalMs;
   c.enablePush                     = EnablePushNotifications;
   c.enableAlerts                   = EnableAlerts;
   c.enableFileLog                  = EnableFileLog;
   c.showDashboard                  = ShowDashboard;
   c.dashboardX                     = DashboardX;
   c.dashboardY                     = DashboardY;
   c.testAllowAnyCurrency           = false;   // production: IDR is mandatory
   return g_app.Init(c);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_app.Deinit(reason);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   g_app.OnTickEvent();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   g_app.OnTimerEvent();
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_app.OnTradeTransactionEvent(trans);
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   g_app.OnChartEventHandler(id, lparam, dparam, sparam);
  }
//+------------------------------------------------------------------+
