//+------------------------------------------------------------------+
//|                                       ConfigurationValidator.mqh |
//| Per-feature validation. An invalid setting disables only its own |
//| feature (or falls back to a safe default for technical values);  |
//| it never disables the other protections (spec 37, audit K-04).   |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_CONFIGURATIONVALIDATOR_MQH
#define EVE_RISK_CONFIGURATIONVALIDATOR_MQH

#include "Defines.mqh"
#include "IDRFormatter.mqh"

struct SEveFeatureFlags
  {
   bool              lossActive;
   bool              profitActive;
   bool              slActive;
   bool              anyActive;
  };

class CEveConfigurationValidator
  {
private:
   static void       Add(string &arr[], const string msg);
   static int        CheckRange(const int value, const int lo, const int hi, const int def,
                                const string name, string &errors[]);

public:
   static void       Validate(const SEveConfig &inCfg, SEveConfig &out, SEveFeatureFlags &flags,
                              string &errors[], string &warnings[]);
   static double     Checksum(const SEveConfig &c);
   static string     Summary(const SEveConfig &c, const SEveFeatureFlags &flags);
  };

//+------------------------------------------------------------------+
void CEveConfigurationValidator::Add(string &arr[], const string msg)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = msg;
  }

//+------------------------------------------------------------------+
int CEveConfigurationValidator::CheckRange(const int value, const int lo, const int hi, const int def,
                                           const string name, string &errors[])
  {
   if(value < lo || value > hi)
     {
      Add(errors, name + "=" + IntegerToString(value) + " is invalid (allowed " +
          IntegerToString(lo) + ".." + IntegerToString(hi) + "); using safe default " + IntegerToString(def));
      return def;
     }
   return value;
  }

//+------------------------------------------------------------------+
void CEveConfigurationValidator::Validate(const SEveConfig &inCfg, SEveConfig &out, SEveFeatureFlags &flags,
                                          string &errors[], string &warnings[])
  {
   ArrayResize(errors, 0);
   ArrayResize(warnings, 0);
   out = inCfg;

   //--- scope: only ALL_ACCOUNT_POSITIONS exists in this release
   if(out.scope != EVE_SCOPE_ALL_ACCOUNT_POSITIONS)
     {
      Add(errors, "ProtectionScope is invalid; forced to ALL_ACCOUNT_POSITIONS");
      out.scope = EVE_SCOPE_ALL_ACCOUNT_POSITIONS;
     }

   //--- feature A
   flags.lossActive = out.enableGlobalLoss;
   if(out.enableGlobalLoss && out.maxGlobalLossIDR <= 0)
     {
      Add(errors, "MAX GLOBAL FLOATING LOSS (IDR) must be > 0 -> GLOBAL FLOATING LOSS PROTECTION DISABLED");
      flags.lossActive = false;
     }
   if(out.lockAfterGlobalLoss && !out.requireManualResetLoss)
     {
      Add(errors, "LockAfterGlobalTrigger=true requires RequireManualReset=true -> treated as manual reset REQUIRED");
      out.requireManualResetLoss = true;
     }

   //--- feature B
   flags.profitActive = out.enableGlobalProfit;
   if(out.enableGlobalProfit && out.globalProfitTargetIDR <= 0)
     {
      Add(errors, "GLOBAL FLOATING PROFIT TARGET (IDR) must be > 0 -> GLOBAL FLOATING PROFIT AUTO-CLOSE DISABLED");
      flags.profitActive = false;
     }
   if(out.lockAfterGlobalProfit && !out.requireManualResetProfit)
     {
      Add(errors, "LockAfterGlobalProfitTrigger=true requires RequireManualResetAfterProfit=true -> treated as manual reset REQUIRED");
      out.requireManualResetProfit = true;
     }

   //--- feature D
   flags.slActive = out.enableAggregateSL;
   if(out.enableAggregateSL && out.maxAggregateSLRiskIDR <= 0)
     {
      Add(errors, "MAX AGGREGATE SL RISK (IDR) must be > 0 -> AGGREGATE IDR SL ENGINE DISABLED");
      flags.slActive = false;
     }
   if(out.slAllocation != EVE_SL_ALLOC_BASKET_COMMON_PRICE &&
      out.slAllocation != EVE_SL_ALLOC_PROPORTIONAL_TO_VOLUME)
     {
      Add(errors, "SLAllocationMethod is invalid; using BASKET_COMMON_PRICE");
      out.slAllocation = EVE_SL_ALLOC_BASKET_COMMON_PRICE;
     }
   if(out.slFailSafe != EVE_FAILSAFE_CLOSE_POSITION && out.slFailSafe != EVE_FAILSAFE_LEAVE_UNPROTECTED)
     {
      Add(errors, "FailSafeWhenCompliantSLImpossible is invalid; using CLOSE_POSITION");
      out.slFailSafe = EVE_FAILSAFE_CLOSE_POSITION;
     }
   if(!MathIsValidNumber(out.slSafetyMarginPct) || out.slSafetyMarginPct < 0.0 || out.slSafetyMarginPct > 50.0)
     {
      Add(errors, "SL BUDGET SAFETY MARGIN (%) must be 0..50; using 1.0");
      out.slSafetyMarginPct = 1.0;
     }
   out.slExtraBufferTicks = CheckRange(out.slExtraBufferTicks, 0, 1000, 1, "SLExtraBufferTicks", errors);
   out.slModifyFailuresBeforeFailSafe = CheckRange(out.slModifyFailuresBeforeFailSafe, 1, 100, 5,
                                                   "SLModifyFailuresBeforeFailSafe", errors);

   //--- lock policy
   if(out.lockedNewPositionPolicy != EVE_LOCKPOL_CLOSE_IMMEDIATELY &&
      out.lockedNewPositionPolicy != EVE_LOCKPOL_ALERT_ONLY)
     {
      Add(errors, "LockedNewPositionPolicy is invalid; using CLOSE_IMMEDIATELY");
      out.lockedNewPositionPolicy = EVE_LOCKPOL_CLOSE_IMMEDIATELY;
     }

   //--- execution (technical values fall back to safe defaults)
   out.closeRetryCount           = CheckRange(out.closeRetryCount, 0, 100, 5, "CloseRetryCount", errors);
   out.closeRetryDelayMs         = CheckRange(out.closeRetryDelayMs, 0, 60000, 250, "CloseRetryDelayMs", errors);
   out.verificationTimeoutMs     = CheckRange(out.verificationTimeoutMs, 100, 120000, 5000, "VerificationTimeoutMs", errors);
   out.persistentRetryIntervalMs = CheckRange(out.persistentRetryIntervalMs, 100, 60000, 1000, "PersistentRetryIntervalMs", errors);
   out.emergencyDeviationPoints  = CheckRange(out.emergencyDeviationPoints, 0, 1000000, 1000, "EmergencyCloseMaxDeviationPoints", errors);
   out.reconciliationIntervalMs  = CheckRange(out.reconciliationIntervalMs, 50, 10000, 250, "ReconciliationIntervalMs", errors);
   out.dashboardX                = CheckRange(out.dashboardX, 0, 5000, 10, "DashboardX", errors);
   out.dashboardY                = CheckRange(out.dashboardY, 0, 5000, 25, "DashboardY", errors);

   //--- warnings
   flags.anyActive = (flags.lossActive || flags.profitActive || flags.slActive);
   if(!flags.anyActive)
      Add(warnings, "WARNING: ALL AUTOMATIC RISK PROTECTION IS DISABLED");
   if(flags.slActive && flags.lossActive && out.maxAggregateSLRiskIDR > out.maxGlobalLossIDR)
      Add(warnings, "SL risk budget " + EveFormatIDRLong(out.maxAggregateSLRiskIDR) +
          " is larger than the global floating loss limit " + EveFormatIDRLong(out.maxGlobalLossIDR) +
          ": the global close-all will normally trigger before the SLs");
   if(flags.slActive && !out.autoApplySLToNewPositions)
      Add(warnings, "AutoApplySLToNewPositions=false: SL engine is ADVISORY ONLY (no SL is placed, no fail-safe close)");
   if(flags.slActive && !out.preserveMoreProtectiveSL)
      Add(warnings, "PreserveMoreProtectiveExistingSL=false: the EA may WIDEN existing stops (within budget). Stops that lock profit are never widened.");
   if(flags.slActive && out.slFailSafe == EVE_FAILSAFE_LEAVE_UNPROTECTED)
      Add(warnings, "Fail-safe LEAVE_UNPROTECTED: positions without a compliant SL stay open (critical alert only)");
   if(!out.lockAfterGlobalLoss && !out.lockAfterGlobalProfit && out.cancelPendingWhenLocked)
      Add(warnings, "Lock is OFF for both triggers: pending orders are NOT cancelled after a close-all");
   if(out.closeRetryCount == 0)
      Add(warnings, "CloseRetryCount=0: no fast burst; failed closes go straight to persistent retry");
  }

//+------------------------------------------------------------------+
double CEveConfigurationValidator::Checksum(const SEveConfig &c)
  {
   string s = IntegerToString((int)c.scope) + "|" +
              (c.enableGlobalLoss ? "1" : "0") + IntegerToString(c.maxGlobalLossIDR) +
              (c.lockAfterGlobalLoss ? "1" : "0") + (c.requireManualResetLoss ? "1" : "0") + "|" +
              (c.enableGlobalProfit ? "1" : "0") + IntegerToString(c.globalProfitTargetIDR) +
              (c.lockAfterGlobalProfit ? "1" : "0") + (c.requireManualResetProfit ? "1" : "0") + "|" +
              IntegerToString((int)c.lockedNewPositionPolicy) + (c.cancelPendingWhenLocked ? "1" : "0") + "|" +
              (c.enableAggregateSL ? "1" : "0") + IntegerToString(c.maxAggregateSLRiskIDR) +
              (c.autoApplySLToNewPositions ? "1" : "0") + (c.rebalanceOnNewEntry ? "1" : "0") +
              IntegerToString((int)c.slAllocation) + (c.preserveMoreProtectiveSL ? "1" : "0") +
              IntegerToString((int)c.slFailSafe) + DoubleToString(c.slSafetyMarginPct, 2) +
              IntegerToString(c.slExtraBufferTicks) + IntegerToString(c.slModifyFailuresBeforeFailSafe) + "|" +
              IntegerToString(c.closeRetryCount) + IntegerToString(c.closeRetryDelayMs) +
              IntegerToString(c.verificationTimeoutMs) + IntegerToString(c.persistentRetryIntervalMs) +
              IntegerToString(c.emergencyDeviationPoints) + IntegerToString(c.reconciliationIntervalMs) + "|" +
              EVE_RP_VERSION;
   return (double)EveFnv1a(s);
  }

//+------------------------------------------------------------------+
string CEveConfigurationValidator::Summary(const SEveConfig &c, const SEveFeatureFlags &flags)
  {
   string s = "LOSS " + (flags.lossActive ? "ON " + EveFormatIDRLong(c.maxGlobalLossIDR) : "OFF") +
              " lock=" + EveBoolOnOff(c.lockAfterGlobalLoss) +
              " | PROFIT " + (flags.profitActive ? "ON " + EveFormatIDRLong(c.globalProfitTargetIDR) : "OFF") +
              " lock=" + EveBoolOnOff(c.lockAfterGlobalProfit) +
              " | SL " + (flags.slActive ? "ON " + EveFormatIDRLong(c.maxAggregateSLRiskIDR) : "OFF") +
              " alloc=" + (c.slAllocation == EVE_SL_ALLOC_BASKET_COMMON_PRICE ? "BASKET" : "PROPORTIONAL") +
              " rebalance=" + EveBoolOnOff(c.rebalanceOnNewEntry) +
              " preserve=" + EveBoolOnOff(c.preserveMoreProtectiveSL) +
              " failsafe=" + (c.slFailSafe == EVE_FAILSAFE_CLOSE_POSITION ? "CLOSE" : "LEAVE_UNPROTECTED") +
              " margin=" + DoubleToString(c.slSafetyMarginPct, 2) + "%" +
              " | retry " + IntegerToString(c.closeRetryCount) + "x" + IntegerToString(c.closeRetryDelayMs) + "ms" +
              " verify=" + IntegerToString(c.verificationTimeoutMs) + "ms" +
              " dev=" + IntegerToString(c.emergencyDeviationPoints) + "pt" +
              " timer=" + IntegerToString(c.reconciliationIntervalMs) + "ms";
   return s;
  }

#endif // EVE_RISK_CONFIGURATIONVALIDATOR_MQH
//+------------------------------------------------------------------+
