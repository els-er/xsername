//+------------------------------------------------------------------+
//|                                           AggregateSLManager.mqh |
//| Aggregate IDR Stop Loss engine (spec 8-13, design section 5).    |
//|                                                                  |
//| Invariant (hard ceiling, never a target):                        |
//|   sum over positions of Loss_i(SL_i) <= MaxAggregateSLRiskIDR    |
//| Default allocation BASKET_COMMON_PRICE (user decision Q1): one    |
//| common SL price per symbol+direction at which the TOTAL loss of   |
//| all entries equals the budget, so the budget follows any number   |
//| of entries and any lot size.                                      |
//| - idempotent: no action while the basket is compliant            |
//| - only tightens (unless preservation is disabled); never widens a |
//|   stop that locks profit                                         |
//| - unsatisfiable -> CRITICAL_SL_BUDGET_UNSATISFIABLE + fail-safe   |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_AGGREGATESLMANAGER_MQH
#define EVE_RISK_AGGREGATESLMANAGER_MQH

#include "Defines.mqh"
#include "Logger.mqh"
#include "IDRFormatter.mqh"
#include "PositionScanner.mqh"
#include "PriceRiskCalculator.mqh"
#include "TradeExecutor.mqh"

class CEveAggregateSLManager
  {
private:
   CEveLogger             *m_log;
   CEveTradeExecutor      *m_exec;
   CEveNotifier           *m_notify;
   CEvePriceRiskCalculator m_calc;
   SEveConfig              m_cfg;
   bool                    m_active;
   double                  m_theoreticalLoss;
   int                     m_protected;
   int                     m_unprotected;
   int                     m_positions;
   bool                    m_compliant;
   string                  m_status;
   string                  m_lastCritical;
   ulong                   m_alertedTickets[];
   string                  m_lastAdvisorySig;
   ulong                   m_lastCalcErrorLogMs;

   static bool       ContainsTicket(const ulong &arr[], const ulong t);
   static void       AddTicket(ulong &arr[], const ulong t);
   void              PruneAlerts(const SEvePosition &all[]);
   void              Plan(const SEvePosition &all[]);
   void              ApplyFailSafe(const SEvePosition &grp[], const string why, const SEveSolveResult &res, const double budget);
   void              CalcErrorLog(const string msg);
   void              LogInfo(const string c, const string m)     { if(m_log != NULL) m_log.Info(c, m);     }
   void              LogWarning(const string c, const string m)  { if(m_log != NULL) m_log.Warning(c, m);  }
   void              LogError(const string c, const string m)    { if(m_log != NULL) m_log.Error(c, m);    }
   void              LogCritical(const string c, const string m) { if(m_log != NULL) m_log.Critical(c, m); }

public:
                     CEveAggregateSLManager(void);
   void              Init(CEveLogger *log, CEveTradeExecutor *exec, CEveNotifier *notify,
                          const SEveConfig &cfg, const bool active);
   void              Reconcile(CEvePositionScanner &scanner, const bool allowActions, const bool setChanged);

   bool              Active(void) const          { return m_active;          }
   double            TheoreticalLoss(void) const { return m_theoreticalLoss; }
   int               ProtectedCount(void) const  { return m_protected;       }
   int               UnprotectedCount(void) const { return m_unprotected;    }
   bool              Compliant(void) const       { return m_compliant;       }
   string            Status(void) const          { return m_status;          }
   string            LastCritical(void) const    { return m_lastCritical;    }
   CEvePriceRiskCalculator *Calculator(void)     { return GetPointer(m_calc); }

   // Budget of one group (whole Rupiah, rounded down = toward lower risk).
   // basket: the group's current floating loss + its volume share of the remaining headroom
   // proportional (spec literal): volume share of the available budget
   static double     GroupBudget(const bool basket, const double consumed, const double available,
                                 const double sumConsumed, const double weight)
     {
      if(basket)
         return MathFloor(consumed + MathMax(0.0, available - sumConsumed) * weight);
      return MathFloor(MathMax(0.0, available) * weight);
     }
  };

//+------------------------------------------------------------------+
CEveAggregateSLManager::CEveAggregateSLManager(void) : m_log(NULL),
                                                       m_exec(NULL),
                                                       m_notify(NULL),
                                                       m_active(false),
                                                       m_theoreticalLoss(0.0),
                                                       m_protected(0),
                                                       m_unprotected(0),
                                                       m_positions(0),
                                                       m_compliant(true),
                                                       m_status("OFF"),
                                                       m_lastCritical(""),
                                                       m_lastAdvisorySig(""),
                                                       m_lastCalcErrorLogMs(0)
  {
  }

//+------------------------------------------------------------------+
void CEveAggregateSLManager::Init(CEveLogger *log, CEveTradeExecutor *exec, CEveNotifier *notify,
                                  const SEveConfig &cfg, const bool active)
  {
   m_log = log;
   m_exec = exec;
   m_notify = notify;
   m_cfg = cfg;
   m_active = active;
   m_status = active ? "STARTING" : "OFF";
   ArrayResize(m_alertedTickets, 0);
  }

//+------------------------------------------------------------------+
bool CEveAggregateSLManager::ContainsTicket(const ulong &arr[], const ulong t)
  {
   int n = ArraySize(arr);
   for(int i = 0; i < n; i++)
      if(arr[i] == t)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
void CEveAggregateSLManager::AddTicket(ulong &arr[], const ulong t)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = t;
  }

//+------------------------------------------------------------------+
void CEveAggregateSLManager::PruneAlerts(const SEvePosition &all[])
  {
   int n = ArraySize(m_alertedTickets);
   int m = ArraySize(all);
   int w = 0;
   for(int r = 0; r < n; r++)
     {
      bool present = false;
      for(int k = 0; k < m; k++)
        {
         if(all[k].ticket == m_alertedTickets[r])
           {
            present = true;
            break;
           }
        }
      if(!present)
         continue;
      if(w != r)
         m_alertedTickets[w] = m_alertedTickets[r];
      w++;
     }
   if(w != n)
      ArrayResize(m_alertedTickets, w);
  }

//+------------------------------------------------------------------+
void CEveAggregateSLManager::CalcErrorLog(const string msg)
  {
   ulong now = GetTickCount64();
   if(m_lastCalcErrorLogMs == 0 || now - m_lastCalcErrorLogMs > 60000)
     {
      LogError("SL", msg);
      m_lastCalcErrorLogMs = now;
     }
  }

//+------------------------------------------------------------------+
//| Entry point, called every reconciliation cycle                   |
//+------------------------------------------------------------------+
void CEveAggregateSLManager::Reconcile(CEvePositionScanner &scanner, const bool allowActions, const bool setChanged)
  {
   m_positions = scanner.Count();
   if(!m_active)
     {
      m_status = "OFF";
      m_theoreticalLoss = 0.0;
      m_protected = 0;
      m_unprotected = 0;
      m_compliant = true;
      return;
     }
   SEvePosition all[];
   scanner.CopyAll(all);
   int n = ArraySize(all);
   PruneAlerts(all);
   if(n == 0)
     {
      m_status = "NO POSITIONS";
      m_theoreticalLoss = 0.0;
      m_protected = 0;
      m_unprotected = 0;
      m_compliant = true;
      m_lastCritical = "";
      return;
     }

   //--- 1. compliance gate (idempotent): theoretical loss at the CURRENT stops
   double B = (double)m_cfg.maxAggregateSLRiskIDR;
   double total = 0.0;
   int noSL = 0;
   int calcErr = 0;
   int prot = 0;
   for(int i = 0; i < n; i++)
     {
      if(all[i].sl <= 0.0)
        {
         noSL++;
         continue;
        }
      double li = 0.0;
      if(!m_calc.LossAt(all[i].type, all[i].symbol, all[i].volume, all[i].priceOpen, all[i].sl, li))
        {
         calcErr++;
         continue;
        }
      total += li;
      prot++;
     }
   m_theoreticalLoss = total;
   m_protected = prot;
   m_unprotected = n - prot;
   bool violated = (noSL > 0 || total > B + EVE_EPS);
   m_compliant = (!violated && calcErr == 0);
   if(calcErr > 0)
      CalcErrorLog("OrderCalcProfit failed for " + IntegerToString(calcErr) +
                   " position(s): SL risk cannot be verified - shown as UNPROTECTED (no fail-safe close for calculation errors)");
   if(m_compliant)
     {
      m_lastCritical = "";
      ArrayResize(m_alertedTickets, 0);
     }

   bool wantReplan = violated ||
                     (setChanged && !m_cfg.preserveMoreProtectiveSL && m_cfg.rebalanceOnNewEntry);
   if(!wantReplan)
     {
      m_status = (calcErr > 0) ? "CALC ERROR" : "COMPLIANT";
      return;
     }
   if(!allowActions)
     {
      m_status = violated ? "VIOLATION (paused)" : "PAUSED";
      return;
     }
   if(!m_cfg.autoApplySLToNewPositions)
     {
      m_status = "ADVISORY ONLY";
      string sig = IntegerToString(noSL) + "|" + ((total > B + EVE_EPS) ? "OVER" : "OK");
      if(sig != m_lastAdvisorySig)
        {
         LogWarning("SL", "ADVISORY (AutoApplySLToNewPositions=OFF): " + IntegerToString(noSL) +
                    " position(s) without SL, theoretical SL loss " + EveFormatIDR(total) + " vs budget " +
                    EveFormatIDR(B) + " - no SL is placed automatically");
         m_lastAdvisorySig = sig;
        }
      return;
     }
   m_lastAdvisorySig = "";
   if(m_exec == NULL)
      return;
   if(m_exec.HasActiveModifyOps())
     {
      m_status = "ADJUSTING (verifying)";
      return;
     }
   Plan(all);
  }

//+------------------------------------------------------------------+
//| Builds and applies the SL plan                                   |
//+------------------------------------------------------------------+
void CEveAggregateSLManager::Plan(const SEvePosition &all[])
  {
   int n = ArraySize(all);
   double B = (double)m_cfg.maxAggregateSLRiskIDR;
   double Bt = B * (1.0 - m_cfg.slSafetyMarginPct / 100.0);
   if(Bt < 0.0)
      Bt = 0.0;
   bool preserve = m_cfg.preserveMoreProtectiveSL;
   bool basket = (m_cfg.slAllocation == EVE_SL_ALLOC_BASKET_COMMON_PRICE);
   m_status = "ADJUSTING";

   //--- 1. classify positions
   int noSL = 0;
   for(int i = 0; i < n; i++)
      if(all[i].sl <= 0.0 && !m_exec.HasOp(all[i].ticket, EVE_OP_CLOSE))
         noSL++;

   SEvePosition adj[];
   int nAdj = 0;
   double fixedLoss = 0.0;
   for(int i = 0; i < n; i++)
     {
      SEvePosition p;
      p = all[i];
      if(m_exec.HasOp(p.ticket, EVE_OP_CLOSE))
         continue;   // being liquidated
      if(m_exec.ModifyFailures(p.ticket) >= m_cfg.slModifyFailuresBeforeFailSafe)
        {
         SEvePosition one[];
         ArrayResize(one, 1);
         one[0] = p;
         SEveSolveResult r;
         r.status = EVE_SOLVE_UNSATISFIABLE;
         r.slPrice = 0.0;
         r.lossAtSL = 0.0;
         r.closestLegalSL = 0.0;
         r.lossAtClosestLegal = 0.0;
         r.budget = 0.0;
         ApplyFailSafe(one, "SL modification failed " + IntegerToString(m_exec.ModifyFailures(p.ticket)) +
                       " times in a row (broker rejection)", r, 0.0);
         continue;
        }
      bool adjustable = (m_cfg.rebalanceOnNewEntry || p.sl <= 0.0 || noSL == 0);
      if(!adjustable || m_exec.IsModifyBlocked(p.ticket))
        {
         if(p.sl > 0.0)
           {
            double li = 0.0;
            if(!m_calc.PositionLossAt(p, p.sl, li))
              {
               m_status = "CALC ERROR";
               CalcErrorLog("SL plan aborted: OrderCalcProfit failed for " + EveTicketStr(p.ticket) + " " + p.symbol);
               return;
              }
            fixedLoss += li;
           }
         continue;
        }
      ArrayResize(adj, nAdj + 1);
      adj[nAdj] = p;
      nAdj++;
     }
   if(nAdj == 0)
     {
      m_status = "WAITING (blocked/closing)";
      return;
     }

   //--- 2. groups: symbol+direction (basket) or one per position (proportional)
   string gKey[];
   int    gOf[];
   ArrayResize(gOf, nAdj);
   int nG = 0;
   for(int i = 0; i < nAdj; i++)
     {
      string key = basket ? (adj[i].symbol + "|" + IntegerToString((int)adj[i].type))
                          : IntegerToString((long)adj[i].ticket);
      int g = -1;
      for(int k = 0; k < nG; k++)
        {
         if(gKey[k] == key)
           {
            g = k;
            break;
           }
        }
      if(g < 0)
        {
         ArrayResize(gKey, nG + 1);
         gKey[nG] = key;
         g = nG;
         nG++;
        }
      gOf[i] = g;
     }

   SEveSymbolSnapshot gSym[];
   double gVol[];
   double gConsumed[];
   bool   gOk[];
   ArrayResize(gSym, nG);
   ArrayResize(gVol, nG);
   ArrayResize(gConsumed, nG);
   ArrayResize(gOk, nG);
   double totalVol = 0.0;
   double sumConsumed = 0.0;
   for(int g = 0; g < nG; g++)
     {
      SEvePosition grp[];
      int cnt = 0;
      double vol = 0.0;
      for(int i = 0; i < nAdj; i++)
        {
         if(gOf[i] != g)
            continue;
         ArrayResize(grp, cnt + 1);
         grp[cnt] = adj[i];
         cnt++;
         vol += adj[i].volume;
        }
      gVol[g] = vol;
      gConsumed[g] = 0.0;
      SEveSymbolSnapshot snapRead;
      gOk[g] = EveReadSymbol(grp[0].symbol, snapRead);
      gSym[g] = snapRead;
      if(!gOk[g])
        {
         //--- no market data: keep this group's current stops, count their risk as fixed
         LogWarning("SL", "No market data for " + grp[0].symbol + " - SL plan for this symbol postponed");
         for(int k = 0; k < cnt; k++)
           {
            if(grp[k].sl <= 0.0)
               continue;
            double li = 0.0;
            if(!m_calc.LossAt(grp[k].type, grp[k].symbol, grp[k].volume, grp[k].priceOpen, grp[k].sl, li))
              {
               m_status = "CALC ERROR";
               CalcErrorLog("SL plan aborted: OrderCalcProfit failed for " + grp[0].symbol);
               return;
              }
            fixedLoss += li;
           }
         continue;
        }
      double exitPrice = (grp[0].type == POSITION_TYPE_BUY) ? snapRead.bid : snapRead.ask;
      double consumed = 0.0;
      if(!m_calc.GroupLossAt(grp, exitPrice, preserve, consumed))
        {
         m_status = "CALC ERROR";
         CalcErrorLog("SL plan aborted: OrderCalcProfit failed for " + grp[0].symbol);
         return;
        }
      gConsumed[g] = consumed;
      totalVol += vol;
      sumConsumed += consumed;
     }

   //--- 3. budgets: Bt (target with safety margin) and B (hard ceiling)
   double aT = Bt - fixedLoss;
   double aB = B - fixedLoss;
   bool overBudget = basket ? (aB - sumConsumed < 0.0) : (aB <= 0.0);

   //--- 4. solve and apply per group
   for(int g = 0; g < nG; g++)
     {
      if(!gOk[g])
         continue;
      SEvePosition grp[];
      int cnt = 0;
      for(int i = 0; i < nAdj; i++)
        {
         if(gOf[i] != g)
            continue;
         ArrayResize(grp, cnt + 1);
         grp[cnt] = adj[i];
         cnt++;
        }
      double w = (totalVol > 0.0) ? gVol[g] / totalVol : 0.0;
      double budgetT = 0.0;
      double budgetB = 0.0;
      budgetT = GroupBudget(basket, gConsumed[g], aT, sumConsumed, w);
      budgetB = GroupBudget(basket, gConsumed[g], aB, sumConsumed, w);
      string sym = grp[0].symbol;
      string dir = EvePositionTypeName(grp[0].type);
      SEveSymbolSnapshot snap;
      snap = gSym[g];
      int digits = snap.digits;

      SEveSolveResult res;
      res.status = EVE_SOLVE_MARKET_DATA_ERROR;
      res.slPrice = 0.0;
      res.lossAtSL = 0.0;
      res.closestLegalSL = 0.0;
      res.lossAtClosestLegal = 0.0;
      res.budget = 0.0;

      if(overBudget && gConsumed[g] > EVE_EPS)
        {
         //--- current floating loss already uses up the whole budget: no compliant SL can exist
         m_calc.SolveGroupSL(grp, snap, budgetB, m_cfg.slExtraBufferTicks, preserve, res);
         res.status = EVE_SOLVE_UNSATISFIABLE;
         ApplyFailSafe(grp, "CRITICAL_SL_BUDGET_UNSATISFIABLE (current floating loss " + EveFormatIDR(sumConsumed) +
                       " + fixed " + EveFormatIDR(fixedLoss) + " already exceeds the SL budget " + EveFormatIDR(B) + ")",
                       res, budgetB);
         continue;
        }

      double used = budgetT;
      bool ok = m_calc.SolveGroupSL(grp, snap, budgetT, m_cfg.slExtraBufferTicks, preserve, res);
      if(!ok && res.status == EVE_SOLVE_UNSATISFIABLE && budgetB > budgetT)
        {
         used = budgetB;
         ok = m_calc.SolveGroupSL(grp, snap, budgetB, m_cfg.slExtraBufferTicks, preserve, res);
        }
      if(ok)
        {
         int moves = 0;
         for(int k = 0; k < cnt; k++)
           {
            if(CEvePriceRiskCalculator::ShouldMoveSL(grp[k].type, grp[k].sl, grp[k].priceOpen, res.slPrice,
                                                     preserve, snap.tickSize))
              {
               if(m_exec.RequestModifySL(grp[k].ticket, res.slPrice, EVE_PURPOSE_SL_ENGINE))
                  moves++;
              }
           }
         if(moves > 0)
            LogInfo("SL", "SL PLAN " + sym + " " + dir + " | positions " + IntegerToString(cnt) +
                    " vol " + DoubleToString(gVol[g], 2) +
                    " | floating loss now " + EveFormatIDR(gConsumed[g]) +
                    " | allocated budget " + EveFormatIDR(used) + " (total " + EveFormatIDR(B) +
                    ", margin " + DoubleToString(m_cfg.slSafetyMarginPct, 2) + "%)" +
                    " | SL " + DoubleToString(res.slPrice, digits) +
                    " | theoretical loss at SL " + EveFormatIDR(res.lossAtSL) +
                    " | modifications " + IntegerToString(moves));
         continue;
        }
      if(res.status == EVE_SOLVE_UNSATISFIABLE)
        {
         ApplyFailSafe(grp, "CRITICAL_SL_BUDGET_UNSATISFIABLE", res, used);
         continue;
        }
      if(res.status == EVE_SOLVE_CALC_ERROR)
        {
         m_status = "CALC ERROR";
         CalcErrorLog("SL solver: OrderCalcProfit failed for " + sym + " - positions shown as UNPROTECTED");
         continue;
        }
      LogWarning("SL", "SL solver: invalid market data for " + sym + " - retry next cycle");
     }
  }

//+------------------------------------------------------------------+
//| Fail-safe when no broker-valid SL can respect the budget (11.1)  |
//+------------------------------------------------------------------+
void CEveAggregateSLManager::ApplyFailSafe(const SEvePosition &grp[], const string why,
                                           const SEveSolveResult &res, const double budget)
  {
   int n = ArraySize(grp);
   if(n <= 0)
      return;
   double vol = 0.0;
   string tickets = "";
   bool newAlert = false;
   for(int i = 0; i < n; i++)
     {
      vol += grp[i].volume;
      tickets += EveTicketStr(grp[i].ticket) + " ";
      if(!ContainsTicket(m_alertedTickets, grp[i].ticket))
        {
         newAlert = true;
         AddTicket(m_alertedTickets, grp[i].ticket);
        }
     }
   string sym = grp[0].symbol;
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   string detail = why + " | " + sym + " " + EvePositionTypeName(grp[0].type) + " | tickets " + tickets +
                   "| volume " + DoubleToString(vol, 2) +
                   " | allocated budget " + EveFormatIDR(budget) +
                   " | closest legal SL " + ((res.closestLegalSL > 0.0) ? DoubleToString(res.closestLegalSL, digits) : "n/a") +
                   " | theoretical loss at closest legal SL " + EveFormatIDR(res.lossAtClosestLegal);
   m_lastCritical = EveTruncate("SL UNSATISFIABLE " + sym + " " + tickets, 110);

   if(m_cfg.slFailSafe == EVE_FAILSAFE_CLOSE_POSITION)
     {
      LogCritical("SL", detail + " -> FAIL-SAFE CLOSE_POSITION: closing (the SL budget cannot be represented by a broker-valid SL)");
      for(int i = 0; i < n; i++)
         if(!m_exec.HasOp(grp[i].ticket, EVE_OP_CLOSE))
            m_exec.RequestClose(grp[i].ticket, EVE_PURPOSE_SL_FAILSAFE);
      if(newAlert && m_notify != NULL)
         m_notify.Notify("SL budget unsatisfiable: closing " + sym + " " + tickets, true);
      m_status = "FAIL-SAFE CLOSE";
      return;
     }
   if(newAlert)
     {
      LogCritical("SL", detail + " -> FailSafe=LEAVE_UNPROTECTED: position(s) left OPEN and UNPROTECTED");
      if(m_notify != NULL)
         m_notify.Notify("UNPROTECTED (SL budget unsatisfiable): " + sym + " " + tickets, true);
     }
   m_status = "UNPROTECTED";
  }

#endif // EVE_RISK_AGGREGATESLMANAGER_MQH
//+------------------------------------------------------------------+
