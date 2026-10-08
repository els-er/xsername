//+------------------------------------------------------------------+
//|                                              FloatingMonitor.mqh |
//| Global floating loss / profit trigger evaluation (pure functions).|
//|                                                                  |
//| Input is the account-wide NET sum of POSITION_PROFIT (no swap, no |
//| commission), already normalized to the account currency digits.  |
//|   LOSS   : total <= -MaxGlobalFloatingLossIDR                    |
//|   PROFIT : total >=  GlobalFloatingProfitTargetIDR               |
//| Threshold crossing, never equality-only matching.                |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_FLOATINGMONITOR_MQH
#define EVE_RISK_FLOATINGMONITOR_MQH

#include "Defines.mqh"

class CEveFloatingMonitor
  {
public:
   static ENUM_EVE_REASON Evaluate(const double totalProfitIDR,
                                   const bool lossActive, const long maxLossIDR,
                                   const bool profitActive, const long profitTargetIDR)
     {
      if(!MathIsValidNumber(totalProfitIDR))
         return EVE_REASON_NONE;
      if(lossActive && maxLossIDR > 0 && totalProfitIDR <= -(double)maxLossIDR + EVE_EPS)
         return EVE_REASON_GLOBAL_FLOATING_LOSS;
      if(profitActive && profitTargetIDR > 0 && totalProfitIDR >= (double)profitTargetIDR - EVE_EPS)
         return EVE_REASON_GLOBAL_FLOATING_PROFIT_TARGET;
      return EVE_REASON_NONE;
     }

   static double  FloatingLoss(const double total)   { return MathMax(0.0, -total); }
   static double  FloatingProfit(const double total) { return MathMax(0.0, total);  }

   static double  LossRemaining(const double total, const long maxLossIDR)
     {
      return MathMax(0.0, (double)maxLossIDR - FloatingLoss(total));
     }

   static double  ProfitProgressPct(const double total, const long targetIDR)
     {
      if(targetIDR <= 0)
         return 0.0;
      return 100.0 * FloatingProfit(total) / (double)targetIDR;
     }
  };

#endif // EVE_RISK_FLOATINGMONITOR_MQH
//+------------------------------------------------------------------+
