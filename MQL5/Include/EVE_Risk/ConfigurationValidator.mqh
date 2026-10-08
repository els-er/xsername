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
   bool              trailActive;
   bool              tpActive;
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
      Add(errors, name + " = " + IntegerToString(value) + " is not valid (allowed " +
          IntegerToString(lo) + ".." + IntegerToString(hi) + "), using safe value " + IntegerToString(def));
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
      Add(errors, "Protection scope not valid, using all positions in the account");
      out.scope = EVE_SCOPE_ALL_ACCOUNT_POSITIONS;
     }

   //--- feature A
   flags.lossActive = out.enableGlobalLoss;
   if(out.enableGlobalLoss && out.maxGlobalLossIDR <= 0)
     {
      Add(errors, "Max total loss must be > 0 - MAX TOTAL LOSS is turned OFF");
      flags.lossActive = false;
     }
   if(out.lockAfterGlobalLoss && !out.requireManualResetLoss)
     {
      Add(errors, "Lock after max loss always needs a manual reset - manual reset kept");
      out.requireManualResetLoss = true;
     }

   //--- feature B
   flags.profitActive = out.enableGlobalProfit;
   if(out.enableGlobalProfit && out.globalProfitTargetIDR <= 0)
     {
      Add(errors, "Profit target must be > 0 - PROFIT TARGET is turned OFF");
      flags.profitActive = false;
     }
   if(out.lockAfterGlobalProfit && !out.requireManualResetProfit)
     {
      Add(errors, "Lock after profit target always needs a manual reset - manual reset kept");
      out.requireManualResetProfit = true;
     }

   //--- feature D
   flags.slActive = out.enableAggregateSL;
   if(out.enableAggregateSL && out.maxAggregateSLRiskIDR <= 0)
     {
      Add(errors, "Max SL loss must be > 0 - AUTO STOP LOSS is turned OFF");
      flags.slActive = false;
     }
   if(out.slAllocation != EVE_SL_ALLOC_BASKET_COMMON_PRICE &&
      out.slAllocation != EVE_SL_ALLOC_PROPORTIONAL_TO_VOLUME)
     {
      Add(errors, "SL mode not valid, using Basket");
      out.slAllocation = EVE_SL_ALLOC_BASKET_COMMON_PRICE;
     }
   if(out.slFailSafe != EVE_FAILSAFE_CLOSE_POSITION && out.slFailSafe != EVE_FAILSAFE_LEAVE_UNPROTECTED)
     {
      Add(errors, "'If SL cannot be placed' not valid, using Close the position");
      out.slFailSafe = EVE_FAILSAFE_CLOSE_POSITION;
     }
   if(!MathIsValidNumber(out.slSafetyMarginPct) || out.slSafetyMarginPct < 0.0 || out.slSafetyMarginPct > 50.0)
     {
      Add(errors, "FX safety margin must be 0..50 %, using 1 %");
      out.slSafetyMarginPct = 1.0;
     }
   out.slExtraBufferTicks = CheckRange(out.slExtraBufferTicks, 0, 1000, 1, "Extra SL distance (ticks)", errors);
   out.slModifyFailuresBeforeFailSafe = CheckRange(out.slModifyFailuresBeforeFailSafe, 1, 100, 5,
                                                   "Max SL errors", errors);

   //--- trailing stop / take profit (per basket, IDR)
   flags.trailActive = out.trailingEnabled;
   if(out.trailingEnabled && (out.trailingStartIDR <= 0 || out.trailingDistanceIDR <= 0 || out.trailingStepIDR < 0))
     {
      Add(errors, "Trailing: start and distance must be > 0, step >= 0 - TRAILING STOP is turned OFF");
      flags.trailActive = false;
      out.trailingEnabled = false;
     }
   if(flags.trailActive && out.trailingDistanceIDR > out.trailingStartIDR)
      Add(warnings, "Trailing distance " + EveFormatIDRLong(out.trailingDistanceIDR) + " is larger than the start " +
          EveFormatIDRLong(out.trailingStartIDR) + ": the first trailing SL is still below break-even");
   if(flags.trailActive && !out.preserveMoreProtectiveSL)
     {
      Add(warnings, "Trailing is ON: 'Never move an SL further away' is forced ON");
      out.preserveMoreProtectiveSL = true;
     }
   flags.tpActive = out.tpEnabled;
   if(out.tpEnabled && out.tpBasketIDR <= 0)
     {
      Add(errors, "Basket TP must be > 0 - TAKE PROFIT is turned OFF");
      flags.tpActive = false;
      out.tpEnabled = false;
     }

   //--- lock policy
   if(out.lockedNewPositionPolicy != EVE_LOCKPOL_CLOSE_IMMEDIATELY &&
      out.lockedNewPositionPolicy != EVE_LOCKPOL_ALERT_ONLY)
     {
      Add(errors, "'New position while locked' not valid, using Close it immediately");
      out.lockedNewPositionPolicy = EVE_LOCKPOL_CLOSE_IMMEDIATELY;
     }

   //--- execution (technical values fall back to safe defaults)
   out.closeRetryCount           = CheckRange(out.closeRetryCount, 0, 100, 5, "Fast close retries", errors);
   out.closeRetryDelayMs         = CheckRange(out.closeRetryDelayMs, 0, 60000, 250, "Fast retry delay (ms)", errors);
   out.verificationTimeoutMs     = CheckRange(out.verificationTimeoutMs, 100, 120000, 5000, "Broker confirmation wait (ms)", errors);
   out.persistentRetryIntervalMs = CheckRange(out.persistentRetryIntervalMs, 100, 60000, 1000, "Slow retry delay (ms)", errors);
   out.emergencyDeviationPoints  = CheckRange(out.emergencyDeviationPoints, 0, 1000000, 1000, "Max slippage (points)", errors);
   out.reconciliationIntervalMs  = CheckRange(out.reconciliationIntervalMs, 50, 10000, 250, "Check interval (ms)", errors);
   out.dashboardX                = CheckRange(out.dashboardX, 0, 5000, 10, "Panel offset X", errors);
   out.dashboardY                = CheckRange(out.dashboardY, 0, 5000, 30, "Panel offset Y", errors);
   out.dashboardSizePct          = CheckRange(out.dashboardSizePct, 50, 200, 100, "Panel size (%)", errors);
   if(out.dashboardCorner != EVE_CORNER_LEFT_UPPER && out.dashboardCorner != EVE_CORNER_RIGHT_UPPER &&
      out.dashboardCorner != EVE_CORNER_LEFT_LOWER && out.dashboardCorner != EVE_CORNER_RIGHT_LOWER)
     {
      Add(errors, "Panel position not valid, using Top left");
      out.dashboardCorner = EVE_CORNER_LEFT_UPPER;
     }

   //--- warnings
   flags.anyActive = (flags.lossActive || flags.profitActive || flags.slActive);
   if(!flags.anyActive)
      Add(warnings, "WARNING: ALL AUTOMATIC PROTECTION IS OFF");
   if(flags.slActive && flags.lossActive && out.maxAggregateSLRiskIDR > out.maxGlobalLossIDR)
      Add(warnings, "Max SL loss " + EveFormatIDRLong(out.maxAggregateSLRiskIDR) +
          " is larger than max total loss " + EveFormatIDRLong(out.maxGlobalLossIDR) +
          ": the total close-all will usually happen before the SLs are hit");
   if(flags.slActive && !out.autoApplySLToNewPositions)
      Add(warnings, "SL for new positions is OFF: auto SL only warns (no SL is placed, nothing is closed)");
   if(flags.slActive && !out.preserveMoreProtectiveSL)
      Add(warnings, "'Never move an SL further away' is OFF: the EA may move SLs further away (within the limit). SLs that lock profit are never moved away.");
   if(flags.slActive && out.slFailSafe == EVE_FAILSAFE_LEAVE_UNPROTECTED)
      Add(warnings, "If SL cannot be placed: the position stays open (warning only)");
   if(out.closeRetryCount == 0)
      Add(warnings, "Fast close retries = 0: a failed close goes straight to slow retries");
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
              (c.trailingEnabled ? "1" : "0") + IntegerToString(c.trailingStartIDR) + IntegerToString(c.trailingDistanceIDR) +
              IntegerToString(c.trailingStepIDR) + (c.tpEnabled ? "1" : "0") + IntegerToString(c.tpBasketIDR) + "|" +
              IntegerToString(c.closeRetryCount) + IntegerToString(c.closeRetryDelayMs) +
              IntegerToString(c.verificationTimeoutMs) + IntegerToString(c.persistentRetryIntervalMs) +
              IntegerToString(c.emergencyDeviationPoints) + IntegerToString(c.reconciliationIntervalMs) +
              (c.asyncSend ? "1" : "0") + "|" +
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
              " | TRAIL " + (flags.trailActive ? "ON start " + EveFormatIDRLong(c.trailingStartIDR) + " dist " +
                             EveFormatIDRLong(c.trailingDistanceIDR) + " step " + EveFormatIDRLong(c.trailingStepIDR) : "OFF") +
              " | TP " + (flags.tpActive ? "ON " + EveFormatIDRLong(c.tpBasketIDR) + "/basket" : "OFF") +
              " | async " + EveBoolOnOff(c.asyncSend) +
              " | retry " + IntegerToString(c.closeRetryCount) + "x" + IntegerToString(c.closeRetryDelayMs) + "ms" +
              " verify=" + IntegerToString(c.verificationTimeoutMs) + "ms" +
              " dev=" + IntegerToString(c.emergencyDeviationPoints) + "pt" +
              " timer=" + IntegerToString(c.reconciliationIntervalMs) + "ms";
   return s;
  }

#endif // EVE_RISK_CONFIGURATIONVALIDATOR_MQH
//+------------------------------------------------------------------+
