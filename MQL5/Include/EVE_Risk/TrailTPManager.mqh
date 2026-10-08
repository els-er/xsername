//+------------------------------------------------------------------+
//|                                               TrailTPManager.mqh |
//| Trailing stop and take profit per BASKET (symbol + direction),   |
//| all amounts in Rupiah, one common price for every entry of the   |
//| basket (same idea as the basket SL, user decision Q1).           |
//|                                                                  |
//| TAKE PROFIT : server TP at the price where the basket profit =    |
//|               target. If the target is already reached (e.g. the  |
//|               TP could not be placed), the basket is closed.      |
//| TRAILING    : once the basket profit >= start, the common SL is   |
//|               moved to the price where the basket profit =        |
//|               (current profit - distance). It only ever moves in  |
//|               the protective direction and only when the locked   |
//|               profit improves by at least "step".                 |
//| Both are stateless (survive restarts) and never open trades.     |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_TRAILTPMANAGER_MQH
#define EVE_RISK_TRAILTPMANAGER_MQH

#include "Defines.mqh"
#include "Logger.mqh"
#include "IDRFormatter.mqh"
#include "PositionScanner.mqh"
#include "PriceRiskCalculator.mqh"
#include "TradeExecutor.mqh"

class CEveTrailTPManager
  {
private:
   CEveLogger             *m_log;
   CEveTradeExecutor      *m_exec;
   CEveNotifier           *m_notify;
   CEvePriceRiskCalculator m_calc;
   SEveConfig              m_cfg;
   bool                    m_trailOn;
   bool                    m_tpOn;
   int                     m_trailGroups;
   int                     m_tpGroups;
   double                  m_lockedProfit;

   void              LogInfo(const string c, const string m) { if(m_log != NULL) m_log.Info(c, m); }

public:
                     CEveTrailTPManager(void);
   void              Init(CEveLogger *log, CEveTradeExecutor *exec, CEveNotifier *notify, const SEveConfig &cfg);
   void              Reconcile(CEvePositionScanner &scanner, const bool allowActions);

   bool              TrailingOn(void) const   { return m_trailOn;      }
   bool              TPOn(void) const         { return m_tpOn;         }
   int               TrailGroups(void) const  { return m_trailGroups;  }
   int               TPGroups(void) const     { return m_tpGroups;     }
   double            LockedProfit(void) const { return m_lockedProfit; }
   CEvePriceRiskCalculator *Calculator(void)  { return GetPointer(m_calc); }

   // Move the SL to newSL? Only in the protective direction and only if the
   // basket profit locked at newSL beats the one at the current SL by >= step.
   static bool       TrailShouldMove(const ENUM_POSITION_TYPE type, const double currentSL, const double newSL,
                                     const double profitAtNew, const double profitAtCurrent, const double stepIDR)
     {
      if(newSL <= 0.0)
         return false;
      if(currentSL <= 0.0)
         return true;
      if(!CEvePriceRiskCalculator::IsMoreProtective(type, newSL, currentSL))
         return false;
      return (profitAtNew - profitAtCurrent >= stepIDR - EVE_EPS);
     }

   // Does a position's TP need to be (re)set? Missing, or the basket profit at
   // that TP is further from the target than the tolerance.
   static bool       TPNeedsUpdate(const double currentTP, const double profitAtCurrentTP,
                                   const double target, const double tolerance)
     {
      if(currentTP <= 0.0)
         return true;
      return (MathAbs(profitAtCurrentTP - target) > tolerance);
     }
  };

//+------------------------------------------------------------------+
CEveTrailTPManager::CEveTrailTPManager(void) : m_log(NULL),
                                               m_exec(NULL),
                                               m_notify(NULL),
                                               m_trailOn(false),
                                               m_tpOn(false),
                                               m_trailGroups(0),
                                               m_tpGroups(0),
                                               m_lockedProfit(0.0)
  {
  }

//+------------------------------------------------------------------+
void CEveTrailTPManager::Init(CEveLogger *log, CEveTradeExecutor *exec, CEveNotifier *notify, const SEveConfig &cfg)
  {
   m_log = log;
   m_exec = exec;
   m_notify = notify;
   m_cfg = cfg;
   m_trailOn = cfg.trailingEnabled;
   m_tpOn = cfg.tpEnabled;
   m_trailGroups = 0;
   m_tpGroups = 0;
   m_lockedProfit = 0.0;
  }

//+------------------------------------------------------------------+
void CEveTrailTPManager::Reconcile(CEvePositionScanner &scanner, const bool allowActions)
  {
   m_trailGroups = 0;
   m_tpGroups = 0;
   m_lockedProfit = 0.0;
   SEvePosition all[];
   scanner.CopyAll(all);
   int n = ArraySize(all);

   //--- profit already locked by the current stops (dashboard statistic)
   for(int i = 0; i < n; i++)
     {
      if(all[i].sl <= 0.0)
         continue;
      double p = 0.0;
      if(m_calc.ProfitAt(all[i].type, all[i].symbol, all[i].volume, all[i].priceOpen, all[i].sl, p) && p > 0.0)
         m_lockedProfit += p;
     }
   if(!allowActions || (!m_trailOn && !m_tpOn) || n == 0 || m_exec == NULL)
      return;

   //--- baskets: symbol + direction (positions that are being closed are skipped)
   SEvePosition use[];
   int nUse = 0;
   for(int i = 0; i < n; i++)
     {
      if(m_exec.HasOp(all[i].ticket, EVE_OP_CLOSE))
         continue;
      ArrayResize(use, nUse + 1);
      use[nUse] = all[i];
      nUse++;
     }
   string keys[];
   int gOf[];
   ArrayResize(gOf, nUse);
   int nG = 0;
   for(int i = 0; i < nUse; i++)
     {
      string key = use[i].symbol + "|" + IntegerToString((int)use[i].type);
      int g = -1;
      for(int k = 0; k < nG; k++)
        {
         if(keys[k] == key)
           {
            g = k;
            break;
           }
        }
      if(g < 0)
        {
         ArrayResize(keys, nG + 1);
         keys[nG] = key;
         g = nG;
         nG++;
        }
      gOf[i] = g;
     }

   for(int g = 0; g < nG; g++)
     {
      SEvePosition grp[];
      int cnt = 0;
      for(int i = 0; i < nUse; i++)
        {
         if(gOf[i] != g)
            continue;
         ArrayResize(grp, cnt + 1);
         grp[cnt] = use[i];
         cnt++;
        }
      SEveSymbolSnapshot s;
      if(!EveReadSymbol(grp[0].symbol, s))
         continue;
      ENUM_POSITION_TYPE type = grp[0].type;
      double exitPrice = (type == POSITION_TYPE_BUY) ? s.bid : s.ask;
      double basketProfit = 0.0;
      if(!m_calc.GroupProfitAt(grp, exitPrice, basketProfit))
         continue;
      string sym = grp[0].symbol;
      string dir = EvePositionTypeName(type);
      int digits = s.digits;

      //--- take profit
      if(m_tpOn)
        {
         double target = (double)m_cfg.tpBasketIDR;
         if(basketProfit >= target - EVE_EPS)
           {
            int closes = 0;
            for(int k = 0; k < cnt; k++)
              {
               if(m_exec.HasOp(grp[k].ticket, EVE_OP_CLOSE))
                  continue;
               m_exec.RequestClose(grp[k].ticket, EVE_PURPOSE_TAKE_PROFIT);
               closes++;
              }
            if(closes > 0)
              {
               LogInfo("TP", "BASKET TP REACHED " + sym + " " + dir + " | basket profit " + EveFormatIDRSigned(basketProfit) +
                       " >= " + EveFormatIDRLong(m_cfg.tpBasketIDR) + " | closing " + IntegerToString(closes) + " position(s)");
               if(m_notify != NULL)
                  m_notify.Notify("Basket TP hit " + sym + " " + dir + " " + EveFormatIDRSigned(basketProfit) + " - positions closed", false);
              }
            continue;
           }
         double tpPrice = 0.0;
         if(m_calc.SolvePriceForProfit(grp, s, target, tpPrice) &&
            CEvePriceRiskCalculator::IsLegalTP(type, tpPrice, s, m_cfg.slExtraBufferTicks))
           {
            m_tpGroups++;
            double tolerance = MathMax(target * 0.01, 1.0);
            int tpMoves = 0;
            for(int k = 0; k < cnt; k++)
              {
               bool need = (grp[k].tp <= 0.0);
               if(!need)
                 {
                  double atTP = 0.0;
                  if(m_calc.GroupProfitAt(grp, grp[k].tp, atTP))
                     need = TPNeedsUpdate(grp[k].tp, atTP, target, tolerance);
                 }
               if(need && MathAbs(grp[k].tp - tpPrice) >= s.tickSize * 0.5)
                  if(m_exec.RequestStops(grp[k].ticket, EVE_KEEP, tpPrice, EVE_PURPOSE_TAKE_PROFIT))
                     tpMoves++;
              }
            if(tpMoves > 0)
              {
               double atPlanned = 0.0;
               m_calc.GroupProfitAt(grp, tpPrice, atPlanned);
               LogInfo("TP", "TP PLAN " + sym + " " + dir + " | positions " + IntegerToString(cnt) +
                       " | basket profit now " + EveFormatIDRSigned(basketProfit) +
                       " | TP " + DoubleToString(tpPrice, digits) + " (basket profit at TP " + EveFormatIDRSigned(atPlanned) +
                       ", target " + EveFormatIDRLong(m_cfg.tpBasketIDR) + ") | modifications " + IntegerToString(tpMoves));
              }
           }
        }

      //--- trailing stop
      if(m_trailOn && basketProfit >= (double)m_cfg.trailingStartIDR - EVE_EPS)
        {
         m_trailGroups++;
         double lockTarget = basketProfit - (double)m_cfg.trailingDistanceIDR;
         double slPrice = 0.0;
         if(!m_calc.SolvePriceForProfit(grp, s, lockTarget, slPrice))
            continue;
         double legal = CEvePriceRiskCalculator::ClosestLegalSL(type, s, m_cfg.slExtraBufferTicks);
         if(legal <= 0.0)
            continue;
         if(CEvePriceRiskCalculator::IsMoreProtective(type, slPrice, legal))
            slPrice = legal;   // closer than the broker allows: use the closest legal SL
         double profitNew = 0.0;
         if(!m_calc.GroupProfitAt(grp, slPrice, profitNew))
            continue;
         int slMoves = 0;
         for(int k = 0; k < cnt; k++)
           {
            double profitCur = 0.0;
            if(grp[k].sl > 0.0 && !m_calc.GroupProfitAt(grp, grp[k].sl, profitCur))
               continue;
            if(TrailShouldMove(type, grp[k].sl, slPrice, profitNew, profitCur, (double)m_cfg.trailingStepIDR))
               if(m_exec.RequestStops(grp[k].ticket, slPrice, EVE_KEEP, EVE_PURPOSE_TRAILING))
                  slMoves++;
           }
         if(slMoves > 0)
            LogInfo("TRAIL", "TRAILING " + sym + " " + dir + " | basket profit " + EveFormatIDRSigned(basketProfit) +
                    " | locked at SL " + EveFormatIDRSigned(profitNew) + " | SL " + DoubleToString(slPrice, digits) +
                    " | modifications " + IntegerToString(slMoves));
        }
     }
  }

#endif // EVE_RISK_TRAILTPMANAGER_MQH
//+------------------------------------------------------------------+
