//+------------------------------------------------------------------+
//|                                             RiskProtectorApp.mqh |
//| Orchestrator shared by the production EA and the tester harness. |
//|                                                                  |
//| One Cycle() serves OnTick, OnTimer and OnTradeTransaction, so the |
//| account-wide monitor never depends on ticks of the chart symbol  |
//| (spec 5.0 / 15A). This class never opens a position.             |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_RISKPROTECTORAPP_MQH
#define EVE_RISK_RISKPROTECTORAPP_MQH

#include "Defines.mqh"
#include "IDRFormatter.mqh"
#include "Logger.mqh"
#include "AccountValidator.mqh"
#include "ConfigurationValidator.mqh"
#include "PositionScanner.mqh"
#include "FloatingMonitor.mqh"
#include "PriceRiskCalculator.mqh"
#include "TradeExecutor.mqh"
#include "StateMachine.mqh"
#include "Persistence.mqh"
#include "AggregateSLManager.mqh"
#include "TrailTPManager.mqh"
#include "RiskDashboard.mqh"

class CEveRiskProtectorApp
  {
private:
   SEveConfig             m_cfg;
   SEveFeatureFlags       m_flags;
   string                 m_cfgErrors[];
   string                 m_cfgWarnings[];
   double                 m_cfgChecksum;
   CEveLogger             m_log;
   CEveNotifier           m_notify;
   CEvePersistence        m_persist;
   CEveInstanceGuard      m_guard;
   CEvePositionScanner    m_scanner;
   CEveTradeExecutor      m_exec;
   CEveStateMachine       m_sm;
   CEveAggregateSLManager m_sl;
   CEveTrailTPManager     m_trail;
   CEveRiskDashboard      m_dash;
   SEveEnvironment        m_env;
   bool                   m_isTester;
   bool                   m_inCycle;
   bool                   m_setChangedSinceSL;
   bool                   m_tradeBlockedLogged;
   bool                   m_timerOk;
   ulong                  m_lastDashMs;
   ulong                  m_emptySinceMs;
   ulong                  m_lastStopsMs;
   string                 m_lastEvent;
   string                 m_safeDisabledReason;
   ENUM_EVE_REASON        m_lastReason;
   datetime               m_lastTriggerTime;
   ulong                  m_lockSeenTickets[];

   void              StartTimer(const int ms);
   void              Cycle(const string source, const bool full);
   void              GuardCheck(void);
   void              RestoreAndArm(const string source);
   void              CheckTradePermission(void);
   void              LogPositionChanges(void);
   string            DescribePosition(const SEvePosition &p) const;
   void              TriggerProtection(const ENUM_EVE_REASON reason);
   void              HandleClosing(void);
   void              FinalizeCloseAll(void);
   void              HandleLocked(void);
   void              CancelPendingOrders(const string why);
   bool              LockAppliesFor(const ENUM_EVE_REASON reason) const;
   void              ManualReset(const string source);
   void              PersistState(void);
   void              RefreshDashboard(const bool force);
   string            BuildBanner(color &clr);
   void              SetEvent(const string text);

public:
                     CEveRiskProtectorApp(void);
   int               Init(const SEveConfig &cfg);
   void              Deinit(const int reason);
   void              OnTickEvent(void)  { Cycle("tick", false); }
   void              OnTimerEvent(void) { Cycle("timer", true); }
   void              OnTradeTransactionEvent(const MqlTradeTransaction &trans, const MqlTradeRequest &request,
                                             const MqlTradeResult &result);
   void              OnChartEventHandler(const int id, const long &lparam, const double &dparam, const string &sparam);

   //--- read-only accessors (dashboard / tester harness)
   ENUM_EVE_STATE    State(void) const           { return m_sm.State();             }
   ENUM_EVE_REASON   Reason(void) const          { return m_sm.Reason();            }
   double            Floating(void) const        { return m_scanner.TotalProfit();  }
   int               Positions(void) const       { return m_scanner.Count();        }
   bool              LossActive(void) const      { return m_flags.lossActive;       }
   bool              ProfitActive(void) const    { return m_flags.profitActive;     }
   bool              SLActive(void) const        { return m_flags.slActive;         }
   long              LossLimit(void) const       { return m_cfg.maxGlobalLossIDR;   }
   long              ProfitTarget(void) const    { return m_cfg.globalProfitTargetIDR; }
   long              SLBudget(void) const        { return m_cfg.maxAggregateSLRiskIDR; }
   double            SLTheoretical(void) const   { return m_sl.TheoreticalLoss();   }
   bool              SLCompliant(void) const     { return m_sl.Compliant();         }
   bool              HasActiveOps(void) const    { return (m_exec.ActiveOpCount() > 0); }
   bool              HasActiveModifyOps(void) const { return m_exec.HasActiveModifyOps(); }
   void              TestManualReset(void)       { ManualReset("test harness"); }
  };

//+------------------------------------------------------------------+
CEveRiskProtectorApp::CEveRiskProtectorApp(void) : m_cfgChecksum(0.0),
                                                   m_isTester(false),
                                                   m_inCycle(false),
                                                   m_setChangedSinceSL(true),
                                                   m_tradeBlockedLogged(false),
                                                   m_timerOk(false),
                                                   m_lastDashMs(0),
                                                   m_emptySinceMs(0),
                                                   m_lastStopsMs(0),
                                                   m_lastEvent(""),
                                                   m_safeDisabledReason(""),
                                                   m_lastReason(EVE_REASON_NONE),
                                                   m_lastTriggerTime(0)
  {
   EveConfigSetDefaults(m_cfg);
   m_flags.lossActive = false;
   m_flags.profitActive = false;
   m_flags.slActive = false;
   m_flags.trailActive = false;
   m_flags.tpActive = false;
   m_flags.anyActive = false;
  }

//+------------------------------------------------------------------+
void CEveRiskProtectorApp::SetEvent(const string text)
  {
   m_lastEvent = TimeToString(TimeCurrent(), TIME_MINUTES | TIME_SECONDS) + " " + text;
  }

//+------------------------------------------------------------------+
void CEveRiskProtectorApp::StartTimer(const int ms)
  {
   EventKillTimer();
   m_timerOk = EventSetMillisecondTimer(ms);
   if(!m_timerOk)
     {
      m_log.Critical("TIMER", "EventSetMillisecondTimer(" + IntegerToString(ms) + ") failed (error " +
                     IntegerToString(GetLastError()) + ") - falling back to a 1 s timer");
      m_timerOk = EventSetTimer(1);
     }
   if(!m_timerOk)
      m_log.Critical("TIMER", "Timer could not be started: only OnTick/OnTradeTransaction monitoring is active!");
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int CEveRiskProtectorApp::Init(const SEveConfig &cfg)
  {
   //--- the object survives re-initialization (inputs/chart change): reset runtime state
   m_inCycle = false;
   m_setChangedSinceSL = true;
   m_tradeBlockedLogged = false;
   m_lastDashMs = 0;
   m_emptySinceMs = 0;
   m_lastStopsMs = 0;
   m_lastEvent = "";
   m_safeDisabledReason = "";
   m_lastReason = EVE_REASON_NONE;
   m_lastTriggerTime = 0;
   ArrayResize(m_lockSeenTickets, 0);
   m_sm.Reset();

   m_isTester = (MQLInfoInteger(MQL_TESTER) != 0);
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   m_log.Init(cfg.enableFileLog, login);
   m_notify.Init(cfg.enablePush, cfg.enableAlerts);
   m_sm.SetLogger(GetPointer(m_log));

   m_log.Info("STARTUP", EVE_RP_NAME + " v" + EVE_RP_VERSION + " starting | account " + IntegerToString(login) +
              " @ " + server + " (" + AccountInfoString(ACCOUNT_COMPANY) + ") | terminal build " +
              IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)) + " | chart " + _Symbol +
              (m_isTester ? " | STRATEGY TESTER" : "") +
              " | risk-control only: this EA never opens trades");
   m_sm.TransitionTo(EVE_STATE_VALIDATING, "startup");

   //--- account currency (spec 4)
   CEveAccountValidator::ReadEnvironment(m_env);
   bool currencyOK = CEveAccountValidator::IsCurrencyIDR(m_env.currency);
   if(!currencyOK && m_isTester && cfg.testAllowAnyCurrency)
     {
      m_log.Warning("CURRENCY", "TEST HARNESS: account currency '" + m_env.currency +
                    "' accepted for testing only (amounts are in deposit currency units)");
      currencyOK = true;
     }
   m_dash.Init(cfg.showDashboard, (int)cfg.dashboardCorner, cfg.dashboardX, cfg.dashboardY, cfg.dashboardSizePct);
   if(!currencyOK)
     {
      m_safeDisabledReason = "account currency is '" + m_env.currency + "', not IDR - all protection is off";
      m_log.Critical("CURRENCY", "Account currency is '" + m_env.currency + "' but IDR is required. No monetary risk " +
                     "calculation is performed and no FX conversion is guessed. Entering SAFE_DISABLED.");
      m_sm.TransitionTo(EVE_STATE_SAFE_DISABLED, "account currency is not IDR");
      m_notify.Notify("EA DISABLED: account currency is " + m_env.currency + ", not IDR", true);
      EveConfigSetDefaults(m_cfg);
      m_flags.lossActive = false;
      m_flags.profitActive = false;
      m_flags.slActive = false;
      m_flags.trailActive = false;
      m_flags.tpActive = false;
      m_flags.anyActive = false;
      m_scanner.Init(m_env.currencyDigits, m_cfg.scope);
      m_exec.Init(GetPointer(m_log), m_cfg, m_env.hedging);
      m_sl.Init(GetPointer(m_log), GetPointer(m_exec), GetPointer(m_notify), m_cfg, false);
      m_cfg.trailingEnabled = false;
      m_cfg.tpEnabled = false;
      m_trail.Init(GetPointer(m_log), GetPointer(m_exec), GetPointer(m_notify), m_cfg);
      StartTimer(1000);
      RefreshDashboard(true);
      return INIT_SUCCEEDED;   // stay on the chart and show the error
     }
   m_log.Info("CURRENCY", "Account currency validated: " + m_env.currency + " (currency digits " +
              IntegerToString(m_env.currencyDigits) + ")");

   //--- configuration (spec 19, audit K-04)
   CEveConfigurationValidator::Validate(cfg, m_cfg, m_flags, m_cfgErrors, m_cfgWarnings);
   m_cfgChecksum = CEveConfigurationValidator::Checksum(m_cfg);
   for(int i = 0; i < ArraySize(m_cfgErrors); i++)
      m_log.Error("CONFIG", m_cfgErrors[i]);
   for(int i = 0; i < ArraySize(m_cfgWarnings); i++)
      m_log.Warning("CONFIG", m_cfgWarnings[i]);
   m_log.Info("CONFIG", "Effective configuration: " + CEveConfigurationValidator::Summary(m_cfg, m_flags) +
              " | checksum " + DoubleToString(m_cfgChecksum, 0));
   m_log.Info("CONFIG", "SCOPE = ALL ACCOUNT POSITIONS: every symbol, every magic number, manual and other EAs.");

   //--- environment
   m_log.Info("ENV", "Margin mode " + CEveAccountValidator::MarginModeName(m_env.marginMode) +
              " | trade allowed: terminal=" + EveBoolOnOff(m_env.terminalTradeAllowed) +
              " ea=" + EveBoolOnOff(m_env.mqlTradeAllowed) +
              " account=" + EveBoolOnOff(m_env.accountTradeAllowed) +
              " expert=" + EveBoolOnOff(m_env.accountExpertAllowed) +
              " connected=" + EveBoolOnOff(m_env.connected));

   //--- components
   m_scanner.Init(m_env.currencyDigits, m_cfg.scope);
   m_exec.Init(GetPointer(m_log), m_cfg, m_env.hedging);
   m_sl.Init(GetPointer(m_log), GetPointer(m_exec), GetPointer(m_notify), m_cfg, m_flags.slActive);
   m_trail.Init(GetPointer(m_log), GetPointer(m_exec), GetPointer(m_notify), m_cfg);
   m_persist.Init(login, server);
   m_guard.Init(m_persist.Prefix(), !m_isTester);
   m_dash.Init(m_cfg.showDashboard, (int)m_cfg.dashboardCorner, m_cfg.dashboardX, m_cfg.dashboardY, m_cfg.dashboardSizePct);
   StartTimer(m_cfg.reconciliationIntervalMs);

   //--- single instance per account (audit G-09)
   if(!m_guard.Acquire())
     {
      m_log.Warning("INSTANCE", "Another EVE Risk Protector instance already protects account " + IntegerToString(login) +
                    " in this terminal. This instance runs in STANDBY (display only, no trading).");
      m_sm.TransitionTo(EVE_STATE_STANDBY, "another instance is active");
      m_scanner.Scan();
      RefreshDashboard(true);
      return INIT_SUCCEEDED;
     }
   RestoreAndArm("startup");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Restore persisted state (spec 17) and arm                        |
//+------------------------------------------------------------------+
void CEveRiskProtectorApp::RestoreAndArm(const string source)
  {
   SEvePersistedState ps;
   m_persist.Load(ps);
   if(ps.found)
     {
      m_log.Info("RESTORE", "Persistent state found (" + source + "): state=" + EveStateName((ENUM_EVE_STATE)ps.state) +
                 " reason=" + EveReasonName((ENUM_EVE_REASON)ps.reason) +
                 " trigger time=" + TimeToString(ps.triggerTime, TIME_DATE | TIME_SECONDS) +
                 " locked=" + EveBoolOnOff(ps.locked) +
                 " saved=" + TimeToString(ps.savedAt, TIME_DATE | TIME_SECONDS));
      if(ps.checksum != m_cfgChecksum)
         m_log.Info("RESTORE", "Configuration changed since the state was saved (stored checksum " +
                    DoubleToString(ps.checksum, 0) + "). A configuration change never clears an existing lock.");
     }

   if(ps.found && (ps.locked || ps.state == (int)EVE_STATE_LOCKED))
     {
      m_sm.SetReason((ENUM_EVE_REASON)ps.reason, ps.triggerTime);
      m_lastReason = (ENUM_EVE_REASON)ps.reason;
      m_lastTriggerTime = ps.triggerTime;
      m_sm.TransitionTo(EVE_STATE_LOCKED, "restored from persistent state (" + source + ")");
      m_log.Warning("RESTORE", "RESTORED LOCKED state after " + EveReasonName((ENUM_EVE_REASON)ps.reason) +
                    " - press RESET PROTECTION (two clicks) to re-arm.");
      if(!LockAppliesFor((ENUM_EVE_REASON)ps.reason))
         m_log.Warning("RESTORE", "Note: the lock setting for this reason is now OFF, but an existing lock is only cleared by manual reset.");
      SetEvent("Restored: LOCKED");
     }
   else
      if(ps.found && ps.state == (int)EVE_STATE_CLOSING_ALL)
        {
         m_sm.SetReason((ENUM_EVE_REASON)ps.reason, ps.triggerTime);
         m_lastReason = (ENUM_EVE_REASON)ps.reason;
         m_lastTriggerTime = ps.triggerTime;
         m_sm.TransitionTo(EVE_STATE_CLOSING_ALL, "restored: a close-all was in progress (" + source + ")");
         m_log.Critical("RESTORE", "RESUMING CLOSE-ALL after restart (reason " + EveReasonName((ENUM_EVE_REASON)ps.reason) +
                        ", triggered " + TimeToString(ps.triggerTime, TIME_DATE | TIME_SECONDS) + ")");
         m_notify.Notify("Restart: continuing to close all positions (" + EveReasonLabel((ENUM_EVE_REASON)ps.reason) + ")", true);
         SetEvent("Continuing close-all");
        }
      else
        {
         m_sm.TransitionTo(EVE_STATE_ARMED, "armed (" + source + ")");
         SetEvent("EA armed");
        }
   PersistState();
   m_setChangedSinceSL = true;
   Cycle(source, true);
  }

//+------------------------------------------------------------------+
void CEveRiskProtectorApp::Deinit(const int reason)
  {
   EventKillTimer();
   ENUM_EVE_STATE st = m_sm.State();
   if(st != EVE_STATE_STANDBY && st != EVE_STATE_SAFE_DISABLED && st != EVE_STATE_INIT && st != EVE_STATE_VALIDATING)
      PersistState();
   m_guard.Release();
   GlobalVariablesFlush();
   m_dash.Destroy();
   m_log.Info("SHUTDOWN", "Deinit: " + EveDeinitReasonText(reason) + " | state " + EveStateName(st) +
              " persisted | open operations " + IntegerToString(m_exec.ActiveOpCount()) +
              ((EveIsClosingState(st)) ? " | CLOSE-ALL WILL RESUME ON NEXT START" : ""));
  }

//+------------------------------------------------------------------+
//| Persist the durable part of the state                            |
//+------------------------------------------------------------------+
void CEveRiskProtectorApp::PersistState(void)
  {
   ENUM_EVE_STATE st = m_sm.State();
   if(st == EVE_STATE_STANDBY || st == EVE_STATE_SAFE_DISABLED || st == EVE_STATE_INIT || st == EVE_STATE_VALIDATING)
      return;
   ENUM_EVE_STATE durable = EVE_STATE_ARMED;
   bool locked = false;
   if(st == EVE_STATE_LOCKED)
     {
      durable = EVE_STATE_LOCKED;
      locked = true;
     }
   else
      if(EveIsClosingState(st) || st == EVE_STATE_ALL_POSITIONS_CLOSED)
         durable = EVE_STATE_CLOSING_ALL;
   ENUM_EVE_REASON reason = (durable == EVE_STATE_ARMED) ? EVE_REASON_NONE : m_sm.Reason();
   datetime t = (durable == EVE_STATE_ARMED) ? 0 : m_sm.TriggerTime();
   if(!m_persist.Save(durable, reason, t, locked, m_cfgChecksum))
      m_log.Error("PERSIST", "Failed to save persistent state (GlobalVariableSet error " + IntegerToString(GetLastError()) + ")");
  }

//+------------------------------------------------------------------+
bool CEveRiskProtectorApp::LockAppliesFor(const ENUM_EVE_REASON reason) const
  {
   if(reason == EVE_REASON_GLOBAL_FLOATING_LOSS)
      return m_cfg.lockAfterGlobalLoss;
   if(reason == EVE_REASON_GLOBAL_FLOATING_PROFIT_TARGET)
      return m_cfg.lockAfterGlobalProfit;
   return false;
  }

//+------------------------------------------------------------------+
//| Instance guard heartbeat / takeover                              |
//+------------------------------------------------------------------+
void CEveRiskProtectorApp::GuardCheck(void)
  {
   ENUM_EVE_STATE st = m_sm.State();
   bool owner = m_guard.Acquire();
   if(st == EVE_STATE_STANDBY && owner)
     {
      m_log.Warning("INSTANCE", "The previously active instance is gone - this instance takes over the protection.");
      m_sm.TransitionTo(EVE_STATE_VALIDATING, "takeover");
      RestoreAndArm("takeover");
     }
   else
      if(st != EVE_STATE_STANDBY && !owner)
        {
         m_log.Critical("INSTANCE", "Instance ownership lost (another instance took over) - switching to STANDBY.");
         m_exec.CancelAll("instance switched to STANDBY");
         m_sm.TransitionTo(EVE_STATE_STANDBY, "ownership lost");
        }
  }

//+------------------------------------------------------------------+
void CEveRiskProtectorApp::CheckTradePermission(void)
  {
   bool can = CEveAccountValidator::CanTrade(m_env);
   if(!can && !m_tradeBlockedLogged)
     {
      string why = CEveAccountValidator::TradeBlockReason(m_env);
      m_log.Critical("ENV", "TRADING NOT POSSIBLE: " + why +
                     " - triggers are still evaluated but positions CANNOT be closed or modified until this is fixed.");
      m_notify.Notify("CANNOT TRADE: " + why, true);
      m_tradeBlockedLogged = true;
     }
   else
      if(can && m_tradeBlockedLogged)
        {
         m_log.Info("ENV", "Trading permission restored.");
         m_tradeBlockedLogged = false;
        }
  }

//+------------------------------------------------------------------+
string CEveRiskProtectorApp::DescribePosition(const SEvePosition &p) const
  {
   int digits = (int)SymbolInfoInteger(p.symbol, SYMBOL_DIGITS);
   return EveTicketStr(p.ticket) + " " + p.symbol + " " + EvePositionTypeName(p.type) +
          " vol " + DoubleToString(p.volume, 2) +
          " open " + DoubleToString(p.priceOpen, digits) +
          " SL " + DoubleToString(p.sl, digits) + " TP " + DoubleToString(p.tp, digits) +
          " magic " + IntegerToString(p.magic) + ((p.magic == 0) ? " (manual)" : "") +
          " P/L " + EveFormatIDRSigned(p.profit) + " (swap " + EveFormatIDRSigned(p.swap) + " excluded)";
  }

//+------------------------------------------------------------------+
void CEveRiskProtectorApp::LogPositionChanges(void)
  {
   bool first = m_scanner.WasFirstScan();
   if(first)
      m_log.Info("SCAN", "Position discovery: " + IntegerToString(m_scanner.Count()) +
                 " open position(s) in the whole account, floating P/L " + EveFormatIDRSigned(m_scanner.TotalProfit()));
   int nNew = m_scanner.NewTicketCount();
   for(int i = 0; i < nNew; i++)
     {
      SEvePosition p;
      if(!m_scanner.FindByTicket(m_scanner.NewTicket(i), p))
         continue;
      m_log.Info("SCAN", (first ? "Existing position " : "NEW POSITION detected ") + DescribePosition(p));
      if(!first)
         SetEvent("New " + p.symbol + " " + EvePositionTypeName(p.type) + " " + DoubleToString(p.volume, 2));
     }
   int nRem = m_scanner.RemovedTicketCount();
   for(int i = 0; i < nRem; i++)
      m_log.Info("SCAN", "Position " + EveTicketStr(m_scanner.RemovedTicket(i)) + " is no longer open");
  }

//+------------------------------------------------------------------+
//| Main reconciliation cycle                                        |
//+------------------------------------------------------------------+
void CEveRiskProtectorApp::Cycle(const string source, const bool full)
  {
   if(m_inCycle)
      return;
   m_inCycle = true;

   ENUM_EVE_STATE st = m_sm.State();
   if(st == EVE_STATE_SAFE_DISABLED || st == EVE_STATE_INIT || st == EVE_STATE_VALIDATING)
     {
      if(full)
         RefreshDashboard(false);
      m_inCycle = false;
      return;
     }
   if(full && !m_isTester)
      GuardCheck();
   st = m_sm.State();
   if(st == EVE_STATE_STANDBY)
     {
      if(full)
        {
         CEveAccountValidator::ReadEnvironment(m_env);
         m_scanner.Scan();
         RefreshDashboard(false);
        }
      m_inCycle = false;
      return;
     }

   CEveAccountValidator::ReadEnvironment(m_env);
   CheckTradePermission();
   m_scanner.Scan();
   LogPositionChanges();
   if(m_scanner.Changed())
      m_setChangedSinceSL = true;

   //--- global floating loss / profit (evaluated on EVERY event)
   if(m_sm.State() == EVE_STATE_ARMED)
     {
      ENUM_EVE_REASON r = CEveFloatingMonitor::Evaluate(m_scanner.TotalProfit(),
                                                        m_flags.lossActive, m_cfg.maxGlobalLossIDR,
                                                        m_flags.profitActive, m_cfg.globalProfitTargetIDR);
      if(r != EVE_REASON_NONE)
         TriggerProtection(r);
     }

   st = m_sm.State();
   if(EveIsClosingState(st))
      HandleClosing();
   else
      if(st == EVE_STATE_LOCKED)
         HandleLocked();

   //--- stops engines (aggregate SL, trailing, take profit): on timer cycles, on trade
   //--- events (a new position gets its SL/TP at once) and on ticks at most every 200 ms.
   //--- Actions only while ARMED (audit G-21); statistics are refreshed in every state.
   ulong nowMs = GetTickCount64();
   if(full || source == "trade" || nowMs - m_lastStopsMs >= 200)
     {
      m_lastStopsMs = nowMs;
      bool armed = (m_sm.State() == EVE_STATE_ARMED);
      m_sl.Reconcile(m_scanner, armed, m_setChangedSinceSL);
      if(armed)
         m_setChangedSinceSL = false;
      m_trail.Reconcile(m_scanner, armed);
     }

   m_exec.Process();

   if(full)
      m_notify.Flush();
   RefreshDashboard(false);
   m_inCycle = false;
  }

//+------------------------------------------------------------------+
//| Global trigger                                                   |
//+------------------------------------------------------------------+
void CEveRiskProtectorApp::TriggerProtection(const ENUM_EVE_REASON reason)
  {
   double total = m_scanner.TotalProfit();
   int n = m_scanner.Count();
   bool lossTrigger = (reason == EVE_REASON_GLOBAL_FLOATING_LOSS);
   string what = lossTrigger ? "GLOBAL FLOATING LOSS PROTECTION TRIGGERED" : "GLOBAL FLOATING PROFIT TARGET REACHED";
   string cond = lossTrigger ? ("Floating P/L " + EveFormatIDRSigned(total) + " <= -" + EveFormatIDRLong(m_cfg.maxGlobalLossIDR))
                             : ("Floating P/L " + EveFormatIDRSigned(total) + " >= " + EveFormatIDRLong(m_cfg.globalProfitTargetIDR));
   string detail = cond + " | positions " + IntegerToString(n) + " (whole account) | lock after close: " +
                   EveBoolOnOff(LockAppliesFor(reason)) + " | basis: POSITION_PROFIT only (no swap/commission)";
   m_log.Critical(EveReasonName(reason), what + ": " + detail);
   for(int i = 0; i < n; i++)
     {
      SEvePosition p;
      if(m_scanner.Get(i, p))
         m_log.Info("SNAPSHOT", DescribePosition(p));
     }

   m_sm.SetReason(reason, TimeCurrent());
   m_lastReason = reason;
   m_lastTriggerTime = TimeCurrent();
   m_sm.TransitionTo(EVE_STATE_PROTECTION_TRIGGERED, what);
   PersistState();
   m_exec.CancelModifyOps("global protection triggered");
   m_notify.Notify((lossTrigger ? "MAX TOTAL LOSS HIT " : "PROFIT TARGET HIT ") + EveFormatIDRSigned(total) +
                   " - closing all " + IntegerToString(n) + " position(s)", true);
   SetEvent(lossTrigger ? "Max loss hit " + EveFormatIDRSigned(total) : "Profit target hit " + EveFormatIDRSigned(total));
   if(LockAppliesFor(reason) && m_cfg.cancelPendingWhenLocked)
      CancelPendingOrders("lock will apply after this close-all");
   m_sm.TransitionTo(EVE_STATE_CLOSING_ALL, "close-all started");
   PersistState();
   m_emptySinceMs = 0;
   m_log.Info("CLOSE_ALL", "Close-all requested for " + IntegerToString(n) + " position(s); verification timeout " +
              IntegerToString(m_cfg.verificationTimeoutMs) + " ms, fast retries " + IntegerToString(m_cfg.closeRetryCount) +
              " x " + IntegerToString(m_cfg.closeRetryDelayMs) + " ms, then persistent every " +
              IntegerToString(m_cfg.persistentRetryIntervalMs) + " ms");
   HandleClosing();
  }

//+------------------------------------------------------------------+
//| Close everything that is open (including positions that appear   |
//| during the close-all, spec 25.D) and verify                      |
//+------------------------------------------------------------------+
void CEveRiskProtectorApp::HandleClosing(void)
  {
   int n = m_scanner.Count();
   for(int i = 0; i < n; i++)
     {
      SEvePosition p;
      if(!m_scanner.Get(i, p))
         continue;
      if(!m_exec.HasOp(p.ticket, EVE_OP_CLOSE))
        {
         m_log.Info("CLOSE_ALL", "Close requested " + DescribePosition(p));
         m_exec.RequestClose(p.ticket, EVE_PURPOSE_GLOBAL_CLOSE_ALL);
        }
     }
   if(LockAppliesFor(m_sm.Reason()) && m_cfg.cancelPendingWhenLocked)
      CancelPendingOrders("close-all with lock");

   ENUM_EVE_STATE st = m_sm.State();
   if(st == EVE_STATE_PROTECTION_TRIGGERED)
      return;
   bool failing = m_exec.AnyCloseFailing();
   if(failing && st == EVE_STATE_CLOSING_ALL)
     {
      m_sm.TransitionTo(EVE_STATE_CLOSE_FAILED, "close retries exhausted or blocked - still retrying");
      m_notify.Notify("CLOSE FAILED - still retrying: " + m_exec.LastFailure(), true);
      SetEvent("Close failed - retrying");
     }
   else
      if(!failing && st == EVE_STATE_CLOSE_FAILED)
         m_sm.TransitionTo(EVE_STATE_CLOSING_ALL, "close attempts recovering");

   if(n == 0 && !m_exec.HasActiveCloseOps())
     {
      ulong now = GetTickCount64();
      if(m_emptySinceMs == 0)
         m_emptySinceMs = now;
      ulong settle = (ulong)MathMax(m_cfg.reconciliationIntervalMs, 100);
      if(now - m_emptySinceMs >= settle)
         FinalizeCloseAll();
     }
   else
      m_emptySinceMs = 0;
  }

//+------------------------------------------------------------------+
void CEveRiskProtectorApp::FinalizeCloseAll(void)
  {
   ENUM_EVE_REASON reason = m_sm.Reason();
   m_sm.TransitionTo(EVE_STATE_ALL_POSITIONS_CLOSED, "all positions verified closed");
   m_log.Info("VERIFY", "CLOSE-ALL VERIFIED: no open positions remain in the account (reason " + EveReasonName(reason) +
              ", account balance now " + EveFormatIDR(AccountInfoDouble(ACCOUNT_BALANCE)) + ")");
   m_emptySinceMs = 0;
   if(LockAppliesFor(reason))
     {
      m_sm.TransitionTo(EVE_STATE_LOCKED, "lock after " + EveReasonName(reason));
      PersistState();
      ArrayResize(m_lockSeenTickets, 0);
      m_log.Warning("LOCK", "LOCK ACTIVATED after " + EveReasonName(reason) + ". New positions: " +
                    ((m_cfg.lockedNewPositionPolicy == EVE_LOCKPOL_CLOSE_IMMEDIATELY) ? "CLOSED IMMEDIATELY" : "ALERT ONLY") +
                    ". Pending orders: " + (m_cfg.cancelPendingWhenLocked ? "CANCELLED" : "NOT cancelled") +
                    ". Press RESET PROTECTION (two clicks) to re-arm.");
      m_notify.Notify("All positions closed (" + EveReasonLabel(reason) + "). EA LOCKED - manual reset needed.", true);
      SetEvent("All closed - LOCKED");
      if(m_cfg.cancelPendingWhenLocked)
         CancelPendingOrders("entered LOCKED");
     }
   else
     {
      m_sm.TransitionTo(EVE_STATE_ARMED, "lock OFF for " + EveReasonName(reason) + " - re-armed");
      m_sm.SetReason(EVE_REASON_NONE, 0);
      PersistState();
      m_notify.Notify("All positions closed (" + EveReasonLabel(reason) + "). EA armed again - you can trade.", false);
      SetEvent("All closed - armed again");
     }
   m_setChangedSinceSL = true;
  }

//+------------------------------------------------------------------+
//| LOCKED: new exposure policy (spec 7, 25.I)                       |
//+------------------------------------------------------------------+
void CEveRiskProtectorApp::HandleLocked(void)
  {
   int n = m_scanner.Count();
   bool closePolicy = (m_cfg.lockedNewPositionPolicy == EVE_LOCKPOL_CLOSE_IMMEDIATELY);
   ulong present[];
   ArrayResize(present, 0);
   for(int i = 0; i < n; i++)
     {
      SEvePosition p;
      if(!m_scanner.Get(i, p))
         continue;
      int k = ArraySize(present);
      ArrayResize(present, k + 1);
      present[k] = p.ticket;
      bool seen = false;
      for(int j = 0; j < ArraySize(m_lockSeenTickets); j++)
        {
         if(m_lockSeenTickets[j] == p.ticket)
           {
            seen = true;
            break;
           }
        }
      if(!seen)
        {
         int s = ArraySize(m_lockSeenTickets);
         ArrayResize(m_lockSeenTickets, s + 1);
         m_lockSeenTickets[s] = p.ticket;
         if(closePolicy)
            m_log.Warning("LOCK", "Position detected while LOCKED - closing immediately (lock policy): " + DescribePosition(p));
         else
            m_log.Warning("LOCK", "Position detected while LOCKED - ALERT ONLY policy, position left open: " + DescribePosition(p));
         m_notify.Notify("LOCKED: new position " + p.symbol + " " + EvePositionTypeName(p.type) + " " +
                         DoubleToString(p.volume, 2) + (closePolicy ? " - closed" : " - left open"), true);
         SetEvent(closePolicy ? "Locked: new position closed" : "Locked: new position (warning)");
        }
      if(closePolicy && !m_exec.HasOp(p.ticket, EVE_OP_CLOSE))
         m_exec.RequestClose(p.ticket, EVE_PURPOSE_LOCK_POLICY);
     }
   //--- forget tickets that are gone
   int w = 0;
   int m = ArraySize(m_lockSeenTickets);
   for(int r = 0; r < m; r++)
     {
      bool still = false;
      for(int k = 0; k < ArraySize(present); k++)
        {
         if(present[k] == m_lockSeenTickets[r])
           {
            still = true;
            break;
           }
        }
      if(!still)
         continue;
      m_lockSeenTickets[w] = m_lockSeenTickets[r];
      w++;
     }
   if(w != m)
      ArrayResize(m_lockSeenTickets, w);

   if(m_cfg.cancelPendingWhenLocked)
      CancelPendingOrders("LOCKED");
  }

//+------------------------------------------------------------------+
//| Delete every pending order in the account (G-06)                 |
//+------------------------------------------------------------------+
void CEveRiskProtectorApp::CancelPendingOrders(const string why)
  {
   int total = OrdersTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0)
         continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(!EveIsPendingOrderType(ot))
         continue;
      if(m_exec.HasOp(t, EVE_OP_DELETE_ORDER))
         continue;
      m_log.Warning("PENDING", "Deleting pending order " + EveTicketStr(t) + " " + OrderGetString(ORDER_SYMBOL) + " " +
                    EnumToString(ot) + " vol " + DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT), 2) + " (" + why + ")");
      m_exec.RequestDeleteOrder(t, EVE_PURPOSE_PENDING_CANCEL);
     }
  }

//+------------------------------------------------------------------+
//| Manual reset (spec 18)                                           |
//+------------------------------------------------------------------+
void CEveRiskProtectorApp::ManualReset(const string source)
  {
   ENUM_EVE_STATE st = m_sm.State();
   if(st != EVE_STATE_LOCKED)
     {
      m_log.Info("RESET", "Reset ignored (" + source + "): state is " + EveStateName(st) + ", not LOCKED");
      SetEvent("Reset ignored (not locked)");
      return;
     }
   if(m_exec.HasActiveCloseOps())
     {
      m_log.Warning("RESET", "Reset REFUSED (" + source + "): a close operation is still active - wait until it is verified.");
      SetEvent("Reset refused: still closing");
      return;
     }
   m_log.Warning("RESET", "MANUAL RESET requested (" + source + "): clearing persistent lock (last trigger " +
                 EveReasonName(m_sm.Reason()) + " at " + TimeToString(m_sm.TriggerTime(), TIME_DATE | TIME_SECONDS) + ")");
   m_sm.TransitionTo(EVE_STATE_ARMED, "manual reset");
   m_sm.SetReason(EVE_REASON_NONE, 0);
   PersistState();
   m_exec.CancelOpsOfKind(EVE_OP_DELETE_ORDER, "manual reset - pending orders are no longer cancelled");
   ArrayResize(m_lockSeenTickets, 0);
   m_setChangedSinceSL = true;
   m_scanner.Scan();
   m_log.Info("RESET", "MANUAL RESET COMPLETE: LOCKED -> ARMED | open positions " + IntegerToString(m_scanner.Count()) +
              " | floating " + EveFormatIDRSigned(m_scanner.TotalProfit()));
   m_notify.Notify("Protection reset - EA armed again", false);
   SetEvent("Manual reset - armed");
   Cycle("reset", true);
  }

//+------------------------------------------------------------------+
void CEveRiskProtectorApp::OnTradeTransactionEvent(const MqlTradeTransaction &trans, const MqlTradeRequest &request,
                                                   const MqlTradeResult &result)
  {
   //--- broker reply to an asynchronous request
   if(trans.type == TRADE_TRANSACTION_REQUEST)
      m_exec.OnRequestResult(request, result);
   //--- any position/order/deal change: reconcile immediately (spec 12)
   if(trans.type == TRADE_TRANSACTION_POSITION || trans.type == TRADE_TRANSACTION_DEAL_ADD ||
      trans.type == TRADE_TRANSACTION_ORDER_ADD || trans.type == TRADE_TRANSACTION_ORDER_DELETE ||
      trans.type == TRADE_TRANSACTION_ORDER_UPDATE || trans.type == TRADE_TRANSACTION_HISTORY_ADD ||
      trans.type == TRADE_TRANSACTION_REQUEST)
     {
      m_setChangedSinceSL = true;
      Cycle("trade", false);
     }
  }

//+------------------------------------------------------------------+
void CEveRiskProtectorApp::OnChartEventHandler(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
     {
      m_dash.OnChartChange();
      RefreshDashboard(true);
      return;
     }
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   int r = m_dash.HandleClick(sparam, (int)lparam, (int)dparam);
   if(r == 1)
     {
      m_log.Info("RESET", "RESET PROTECTION pressed - click again within 10 s to confirm");
      SetEvent("Reset: click again to confirm");
      RefreshDashboard(true);
     }
   else
      if(r == 2)
        {
         ManualReset("chart button, confirmed");
         RefreshDashboard(true);
        }
      else
         if(r == 3)
            RefreshDashboard(true);
  }

//+------------------------------------------------------------------+
string CEveRiskProtectorApp::BuildBanner(color &clr)
  {
   ENUM_EVE_STATE st = m_sm.State();
   clr = C'239,83,80';
   if(st == EVE_STATE_SAFE_DISABLED)
      return "EA DISABLED: " + m_safeDisabledReason;
   if(st == EVE_STATE_CLOSE_FAILED)
      return "CLOSE FAILED - STILL RETRYING: " + m_exec.LastFailure();
   if(EveIsClosingState(st))
      return "CLOSING ALL POSITIONS (" + EveReasonLabel(m_sm.Reason()) + ")";
   if(st == EVE_STATE_LOCKED)
     {
      clr = C'255,167,38';
      return "EA LOCKED after " + EveReasonLabel(m_sm.Reason()) + ". Click RESET PROTECTION twice to re-arm.";
     }
   if(st == EVE_STATE_STANDBY)
     {
      clr = C'255,167,38';
      return "STANDBY: this EA already runs on another chart for this account";
     }
   if(!CEveAccountValidator::CanTrade(m_env))
      return "CANNOT TRADE: " + CEveAccountValidator::TradeBlockReason(m_env);
   if(m_flags.slActive && m_sl.LastCritical() != "")
      return m_sl.LastCritical();
   if(ArraySize(m_cfgErrors) > 0)
     {
      clr = C'255,167,38';
      return "SETTINGS ERROR: " + m_cfgErrors[0];
     }
   if(!m_flags.anyActive)
     {
      clr = C'255,167,38';
      return "WARNING: ALL AUTOMATIC PROTECTION IS OFF";
     }
   if(!m_timerOk)
      return "TIMER NOT RUNNING - checks rely on ticks only";
   clr = C'108,118,134';
   return "";
  }

//+------------------------------------------------------------------+
void CEveRiskProtectorApp::RefreshDashboard(const bool force)
  {
   ulong now = GetTickCount64();
   if(!force && m_lastDashMs != 0 && now - m_lastDashMs < 250)
      return;
   m_lastDashMs = now;

   SEveDashboardData d;
   d.currency      = m_env.currency;
   d.balance       = AccountInfoDouble(ACCOUNT_BALANCE);
   d.equity        = AccountInfoDouble(ACCOUNT_EQUITY);
   d.floating      = m_scanner.TotalProfit();
   d.positions     = m_scanner.Count();
   d.pendingOrders = CEvePositionScanner::PendingOrderCount();
   d.lossActive    = m_flags.lossActive;
   d.lossLimit     = m_cfg.maxGlobalLossIDR;
   d.profitActive  = m_flags.profitActive;
   d.profitTarget  = m_cfg.globalProfitTargetIDR;
   d.slActive      = m_flags.slActive;
   d.slBudget      = m_cfg.maxAggregateSLRiskIDR;
   d.slTheoretical = m_sl.TheoreticalLoss();
   d.slProtected   = m_sl.ProtectedCount();
   d.slUnprotected = m_sl.UnprotectedCount();
   d.slStatus      = m_sl.Status();
   d.trailActive   = m_trail.TrailingOn();
   d.trailStart    = m_cfg.trailingStartIDR;
   d.trailGroups   = m_trail.TrailGroups();
   d.lockedProfit  = m_trail.LockedProfit();
   d.tpActive      = m_trail.TPOn();
   d.tpTarget      = m_cfg.tpBasketIDR;
   d.tpGroups      = m_trail.TPGroups();
   d.lockLoss      = m_cfg.lockAfterGlobalLoss;
   d.lockProfit    = m_cfg.lockAfterGlobalProfit;
   d.cancelPending = m_cfg.cancelPendingWhenLocked;
   d.state         = m_sm.State();
   d.reason        = m_sm.Reason();
   d.tradeAllowed  = CEveAccountValidator::CanTrade(m_env);
   d.tradeBlock    = CEveAccountValidator::TradeBlockReason(m_env);
   d.marginMode    = CEveAccountValidator::MarginModeName(m_env.marginMode);
   d.lastEvent     = m_lastEvent;
   color bc = clrOrange;
   d.banner        = BuildBanner(bc);
   d.bannerColor   = bc;
   d.showReset     = (m_sm.State() == EVE_STATE_LOCKED);
   m_dash.Update(d);
  }

#endif // EVE_RISK_RISKPROTECTORAPP_MQH
//+------------------------------------------------------------------+
