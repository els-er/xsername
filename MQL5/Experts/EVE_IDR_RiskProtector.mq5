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
//| be IDR, otherwise the EA stays DISABLED.                          |
//|                                                                  |
//| A limit is a TRIGGER, not a guaranteed result: price movement,    |
//| spread, slippage, latency and gaps can make the realized          |
//| loss/profit differ from the amount you set.                       |
//+------------------------------------------------------------------+
#property copyright   "EVE"
#property version     "1.12"
#property description "EVE IDR Risk Protector v1.12 - risk-control EA (never opens trades)."
#property description "Works on ALL positions in the account (all symbols, manual + other EAs)."
#property description "Max total loss, profit target, auto stop loss, trailing stop and basket TP - all in IDR."
#property description "Limits are triggers, not guaranteed fill results."

#include <EVE_Risk\RiskProtectorApp.mqh>

//+------------------------------------------------------------------+
//| Inputs (simple English, all money in IDR)                        |
//+------------------------------------------------------------------+
input group "1. MAX TOTAL LOSS - closes ALL positions"
input ENUM_EVE_ONOFF UseMaxTotalLoss  = EVE_ON;     // Close all when total loss reaches the limit
input long           MaxTotalLossIDR  = 500000;     // Max total loss (IDR)
input ENUM_EVE_ONOFF LockAfterMaxLoss = EVE_OFF;    // Lock EA after max loss (needs manual reset)

input group "2. PROFIT TARGET - closes ALL positions"
input ENUM_EVE_ONOFF UseProfitTarget        = EVE_OFF;  // Close all when total profit reaches the target
input long           ProfitTargetIDR        = 500000;   // Profit target (IDR)
input ENUM_EVE_ONOFF LockAfterProfitTarget  = EVE_OFF;  // Lock EA after profit target (needs manual reset)

input group "3. AUTO STOP LOSS - SL on every position (on the broker server)"
input ENUM_EVE_ONOFF         UseAutoSL       = EVE_ON;                            // Put an SL on every position
input long                   MaxSLLossIDR    = 500000;                            // Max total loss if all SLs are hit (IDR)
input ENUM_EVE_SL_ALLOCATION SLMode          = EVE_SL_ALLOC_BASKET_COMMON_PRICE;  // SL mode
input ENUM_EVE_SL_FAILSAFE   IfSLNotPossible = EVE_FAILSAFE_CLOSE_POSITION;       // If an SL cannot be placed within the limit

input group "4. TRAILING STOP - per basket (same symbol + direction)"
input ENUM_EVE_ONOFF UseTrailingStop   = EVE_OFF;   // Trailing stop
input long           TrailStartIDR     = 100000;    // Start when basket profit reaches (IDR)
input long           TrailDistanceIDR  = 50000;     // Keep this much below the highest profit (IDR)
input long           TrailStepIDR      = 10000;     // Move SL only when locked profit grows by (IDR)

input group "5. TAKE PROFIT - per basket (same symbol + direction)"
input ENUM_EVE_ONOFF UseBasketTP = EVE_OFF;         // Take profit
input long           BasketTPIDR = 300000;          // Close the basket at this profit (IDR)

input group "6. WHEN THE EA IS LOCKED"
input ENUM_EVE_LOCK_NEWPOS_POLICY NewPositionWhenLocked   = EVE_LOCKPOL_CLOSE_IMMEDIATELY; // New position while locked
input ENUM_EVE_ONOFF              DeletePendingWhenLocked = EVE_ON;                        // Delete pending orders while locked

input group "7. PANEL AND ALERTS"
input ENUM_EVE_ONOFF  ShowPanel      = EVE_ON;                  // Show panel
input ENUM_EVE_CORNER PanelPosition  = EVE_CORNER_LEFT_UPPER;   // Panel position
input int             PanelSizePct   = 100;                     // Panel size (%) - 100 = normal
input int             PanelOffsetX   = 10;                      // Panel distance from side (px)
input int             PanelOffsetY   = 30;                      // Panel distance from top/bottom (px)
input ENUM_EVE_ONOFF  PhoneAlerts    = EVE_ON;                  // Alerts to phone (set MetaQuotes ID in MT5)
input ENUM_EVE_ONOFF  PopupAlerts    = EVE_ON;                  // Popup alerts for important events

input group "8. ADVANCED - keep the default if unsure"
input ENUM_EVE_ONOFF RecalcSLOnNewEntry   = EVE_ON;   // Recalculate basket SL on a new entry
input ENUM_EVE_ONOFF NeverLoosenSL        = EVE_ON;   // Never move an SL further away
input ENUM_EVE_ONOFF SLForNewPositions    = EVE_ON;   // Put SL on new positions (OFF = warning only)
input double         FXSafetyMarginPct    = 1.0;      // SL safety margin for USD/IDR moves (%)
input int            SLExtraTicks         = 1;        // Extra SL distance from the broker limit (ticks)
input int            MaxSLErrors          = 5;        // Close a position after this many SL errors
input int            FastCloseRetries     = 5;        // Fast close retries
input int            FastRetryDelayMs     = 250;      // Fast retry delay (ms)
input int            BrokerConfirmWaitMs  = 5000;     // Wait for broker confirmation (ms)
input int            SlowRetryDelayMs     = 1000;     // Retry delay after the fast retries (ms)
input int            MaxSlippagePoints    = 1000;     // Max slippage for emergency close (points)
input int            CheckIntervalMs      = 250;      // Account check interval (ms)
input ENUM_EVE_ONOFF SendOrdersInParallel = EVE_ON;   // Send orders in parallel (faster)
input ENUM_EVE_ONOFF SaveLogFile          = EVE_ON;   // Save a daily log file

CEveRiskProtectorApp g_app;

//+------------------------------------------------------------------+
int OnInit()
  {
   SEveConfig c;
   EveConfigSetDefaults(c);
   c.scope                          = EVE_SCOPE_ALL_ACCOUNT_POSITIONS;
   //--- 1. max total loss
   c.enableGlobalLoss               = (UseMaxTotalLoss == EVE_ON);
   c.maxGlobalLossIDR               = MaxTotalLossIDR;
   c.lockAfterGlobalLoss            = (LockAfterMaxLoss == EVE_ON);
   c.requireManualResetLoss         = true;    // a lock is always cleared by manual reset only
   //--- 2. profit target
   c.enableGlobalProfit             = (UseProfitTarget == EVE_ON);
   c.globalProfitTargetIDR          = ProfitTargetIDR;
   c.lockAfterGlobalProfit          = (LockAfterProfitTarget == EVE_ON);
   c.requireManualResetProfit       = true;
   //--- 3. auto stop loss
   c.enableAggregateSL              = (UseAutoSL == EVE_ON);
   c.maxAggregateSLRiskIDR          = MaxSLLossIDR;
   c.slAllocation                   = SLMode;
   c.slFailSafe                     = IfSLNotPossible;
   //--- 4. trailing stop
   c.trailingEnabled                = (UseTrailingStop == EVE_ON);
   c.trailingStartIDR               = TrailStartIDR;
   c.trailingDistanceIDR            = TrailDistanceIDR;
   c.trailingStepIDR                = TrailStepIDR;
   //--- 5. take profit
   c.tpEnabled                      = (UseBasketTP == EVE_ON);
   c.tpBasketIDR                    = BasketTPIDR;
   //--- 6. lock
   c.lockedNewPositionPolicy        = NewPositionWhenLocked;
   c.cancelPendingWhenLocked        = (DeletePendingWhenLocked == EVE_ON);
   //--- 7. panel and alerts
   c.showDashboard                  = (ShowPanel == EVE_ON);
   c.dashboardCorner                = PanelPosition;
   c.dashboardX                     = PanelOffsetX;
   c.dashboardY                     = PanelOffsetY;
   c.dashboardSizePct               = PanelSizePct;
   c.enablePush                     = (PhoneAlerts == EVE_ON);
   c.enableAlerts                   = (PopupAlerts == EVE_ON);
   //--- 8. advanced
   c.rebalanceOnNewEntry            = (RecalcSLOnNewEntry == EVE_ON);
   c.preserveMoreProtectiveSL       = (NeverLoosenSL == EVE_ON);
   c.autoApplySLToNewPositions      = (SLForNewPositions == EVE_ON);
   c.slSafetyMarginPct              = FXSafetyMarginPct;
   c.slExtraBufferTicks             = SLExtraTicks;
   c.slModifyFailuresBeforeFailSafe = MaxSLErrors;
   c.closeRetryCount                = FastCloseRetries;
   c.closeRetryDelayMs              = FastRetryDelayMs;
   c.verificationTimeoutMs          = BrokerConfirmWaitMs;
   c.persistentRetryIntervalMs      = SlowRetryDelayMs;
   c.emergencyDeviationPoints       = MaxSlippagePoints;
   c.reconciliationIntervalMs       = CheckIntervalMs;
   c.asyncSend                      = (SendOrdersInParallel == EVE_ON);
   c.enableFileLog                  = (SaveLogFile == EVE_ON);
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
   g_app.OnTradeTransactionEvent(trans, request, result);
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   g_app.OnChartEventHandler(id, lparam, dparam, sparam);
  }
//+------------------------------------------------------------------+
