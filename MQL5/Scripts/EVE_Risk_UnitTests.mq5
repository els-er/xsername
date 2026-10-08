//+------------------------------------------------------------------+
//|                                           EVE_Risk_UnitTests.mq5 |
//| Deterministic unit tests for the EVE IDR Risk Protector logic.   |
//| No trading, no market data needed: the SL solver runs on an       |
//| injected linear profit model (Rp1.600.000 per 1.00 price unit per |
//| lot, i.e. XAUUSD 100 oz at USD/IDR 16.000).                       |
//| Output: Experts journal + MQL5\Files\EVE_Risk_UnitTests_Result.txt|
//+------------------------------------------------------------------+
#property copyright   "EVE"
#property version     "1.00"
#property description "EVE IDR Risk Protector - deterministic unit tests (no trading)."

#include <EVE_Risk\RiskProtectorApp.mqh>

int    g_pass = 0;
int    g_fail = 0;
string g_lines[];

//+------------------------------------------------------------------+
void AddLine(const string s)
  {
   int n = ArraySize(g_lines);
   ArrayResize(g_lines, n + 1);
   g_lines[n] = s;
   Print(s);
  }

void Check(const bool cond, const string name, const string detail)
  {
   if(cond)
      g_pass++;
   else
      g_fail++;
   AddLine((cond ? "PASS | " : "FAIL | ") + name + ((detail != "") ? " | " + detail : ""));
  }

void CheckStr(const string got, const string expected, const string name)
  {
   Check(got == expected, name, "got '" + got + "' expected '" + expected + "'");
  }

bool Near(const double a, const double b, const double tol)
  {
   return (MathAbs(a - b) <= tol);
  }

//+------------------------------------------------------------------+
//| Linear profit model used instead of OrderCalcProfit              |
//+------------------------------------------------------------------+
class CTestLinearModel : public CEveProfitModel
  {
public:
   double            m_k;   // IDR per 1.00 price unit per 1.00 lot
                     CTestLinearModel(void) : m_k(1600000.0) {}
   virtual bool      Profit(const ENUM_POSITION_TYPE type, const string symbol, const double volume,
                            const double priceOpen, const double priceClose, double &profit)
     {
      double diff = (type == POSITION_TYPE_BUY) ? (priceClose - priceOpen) : (priceOpen - priceClose);
      profit = diff * volume * m_k;
      return true;
     }
  };

//+------------------------------------------------------------------+
void MakePos(SEvePosition &p, const ulong ticket, const ENUM_POSITION_TYPE type, const double vol,
             const double open, const double sl)
  {
   p.ticket     = ticket;
   p.identifier = (long)ticket;
   p.symbol     = "TESTXAU";
   p.type       = type;
   p.volume     = vol;
   p.priceOpen  = open;
   p.sl         = sl;
   p.tp         = 0.0;
   p.profit     = 0.0;
   p.swap       = 0.0;
   p.magic      = 0;
   p.timeMsc    = 0;
  }

// Builds a position in a local struct and assigns it into the array
// (array elements are never passed by reference).
void SetPos(SEvePosition &arr[], const int idx, const ulong ticket, const ENUM_POSITION_TYPE type,
            const double vol, const double open, const double sl)
  {
   SEvePosition p;
   MakePos(p, ticket, type, vol, open, sl);
   arr[idx] = p;
  }

void MakeSym(SEveSymbolSnapshot &s, const double bid, const double ask, const int stopsLevel)
  {
   s.symbol      = "TESTXAU";
   s.valid       = true;
   s.bid         = bid;
   s.ask         = ask;
   s.point       = 0.01;
   s.tickSize    = 0.01;
   s.digits      = 2;
   s.stopsLevel  = stopsLevel;
   s.freezeLevel = 0;
   s.volumeMin   = 0.01;
   s.volumeMax   = 100.0;
   s.volumeStep  = 0.01;
   s.tradeMode   = 0;
   s.exeMode     = 0;
   s.fillingMode = 1;
  }

//+------------------------------------------------------------------+
//| T9: IDR formatting                                               |
//+------------------------------------------------------------------+
void TestFormatter()
  {
   CheckStr(EveFormatIDR(0.0), "Rp0", "T9 format 0");
   CheckStr(EveFormatIDR(999.0), "Rp999", "T9 format 999");
   CheckStr(EveFormatIDR(1000.0), "Rp1.000", "T9 format 1000");
   CheckStr(EveFormatIDR(100000.0), "Rp100.000", "T9 format 100000");
   CheckStr(EveFormatIDR(500000.0), "Rp500.000", "T9 format 500000");
   CheckStr(EveFormatIDR(1000000.0), "Rp1.000.000", "T9 format 1000000");
   CheckStr(EveFormatIDR(2500000.0), "Rp2.500.000", "T9 format 2500000");
   CheckStr(EveFormatIDR(10500000.0), "Rp10.500.000", "T9 format 10500000");
   CheckStr(EveFormatIDR(-500000.0), "-Rp500.000", "T9 format -500000");
   CheckStr(EveFormatIDR(-0.4), "Rp0", "T9 format -0.4 (no negative zero)");
   CheckStr(EveFormatIDR(499999.5), "Rp500.000", "T9 format rounding half away from zero");
   CheckStr(EveFormatIDR(9000000000000.0), "Rp9.000.000.000.000", "T9 format large value");
   CheckStr(EveFormatIDRLong(-10000000), "-Rp10.000.000", "T9 format long negative");
   CheckStr(EveFormatIDRSigned(100000.0), "+Rp100.000", "T9 signed positive");
   CheckStr(EveFormatIDRSigned(-100000.0), "-Rp100.000", "T9 signed negative");
   CheckStr(EveFormatIDRSigned(0.0), "Rp0", "T9 signed zero");
  }

//+------------------------------------------------------------------+
//| T1-T8: global loss / profit triggers                             |
//+------------------------------------------------------------------+
void TestTriggers()
  {
   ENUM_EVE_REASON r;
   //--- T1 threshold crossing
   r = CEveFloatingMonitor::Evaluate(-499999.0, true, 500000, false, 500000);
   Check(r == EVE_REASON_NONE, "T1 loss -499.999 -> no trigger", EveReasonName(r));
   r = CEveFloatingMonitor::Evaluate(-500000.0, true, 500000, false, 500000);
   Check(r == EVE_REASON_GLOBAL_FLOATING_LOSS, "T1 loss -500.000 -> trigger", EveReasonName(r));
   r = CEveFloatingMonitor::Evaluate(-500001.0, true, 500000, false, 500000);
   Check(r == EVE_REASON_GLOBAL_FLOATING_LOSS, "T1 loss -500.001 -> trigger", EveReasonName(r));
   r = CEveFloatingMonitor::Evaluate(-600000.0, false, 500000, false, 500000);
   Check(r == EVE_REASON_NONE, "T1 loss protection OFF -> no trigger", EveReasonName(r));

   //--- T2 multiple positions
   double p2[3] = {-100000.0, -150000.0, -250000.0};
   double t2 = CEvePositionScanner::SumFloating(p2, 3, 2);
   r = CEveFloatingMonitor::Evaluate(t2, true, 500000, false, 500000);
   Check(Near(t2, -500000.0, 0.001) && r == EVE_REASON_GLOBAL_FLOATING_LOSS,
         "T2 -100k -150k -250k = -500k -> close all", "total " + DoubleToString(t2, 2));

   //--- T3 positive floating
   r = CEveFloatingMonitor::Evaluate(100000.0, true, 500000, false, 500000);
   Check(r == EVE_REASON_NONE, "T3 +100.000 -> no loss trigger", EveReasonName(r));

   //--- T4/T5 profit target
   r = CEveFloatingMonitor::Evaluate(500000.0, true, 500000, false, 500000);
   Check(r == EVE_REASON_NONE, "T4 profit OFF, +500.000 -> no trigger", EveReasonName(r));
   r = CEveFloatingMonitor::Evaluate(499999.0, true, 500000, true, 500000);
   Check(r == EVE_REASON_NONE, "T5 profit +499.999 -> no trigger", EveReasonName(r));
   r = CEveFloatingMonitor::Evaluate(500000.0, true, 500000, true, 500000);
   Check(r == EVE_REASON_GLOBAL_FLOATING_PROFIT_TARGET, "T5 profit +500.000 -> close all", EveReasonName(r));
   r = CEveFloatingMonitor::Evaluate(500001.0, true, 500000, true, 500000);
   Check(r == EVE_REASON_GLOBAL_FLOATING_PROFIT_TARGET, "T5 profit +500.001 -> close all", EveReasonName(r));

   //--- T6 account-wide NET (not winners only)
   double p6[3] = {700000.0, -200000.0, 50000.0};
   double t6 = CEvePositionScanner::SumFloating(p6, 3, 2);
   r = CEveFloatingMonitor::Evaluate(t6, true, 500000, true, 500000);
   Check(Near(t6, 550000.0, 0.001) && r == EVE_REASON_GLOBAL_FLOATING_PROFIT_TARGET,
         "T6 +700k -200k +50k = +550k net -> close all", "total " + DoubleToString(t6, 2));
   double p6b[2] = {700000.0, -300000.0};
   double t6b = CEvePositionScanner::SumFloating(p6b, 2, 2);
   r = CEveFloatingMonitor::Evaluate(t6b, true, 500000, true, 500000);
   Check(r == EVE_REASON_NONE, "T6 winners alone +700k but net +400k -> no trigger", "total " + DoubleToString(t6b, 2));

   //--- T7 swap / commission are not inputs of the trigger
   double profits[2] = {-300000.0, -150000.0};
   double swaps[2]   = {-30000.0, -40000.0};
   double t7 = CEvePositionScanner::SumFloating(profits, 2, 2);
   r = CEveFloatingMonitor::Evaluate(t7, true, 500000, false, 500000);
   double withSwap = t7 + swaps[0] + swaps[1];
   Check(r == EVE_REASON_NONE && withSwap <= -500000.0,
         "T7 POSITION_PROFIT -450k (swap -70k excluded) -> no trigger",
         "profit-only " + DoubleToString(t7, 0) + ", would-be with swap " + DoubleToString(withSwap, 0));

   //--- T8 decimal sums normalized to currency digits
   double p8[3] = {-166666.67, -166666.67, -166666.66};
   double t8 = CEvePositionScanner::SumFloating(p8, 3, 2);
   r = CEveFloatingMonitor::Evaluate(t8, true, 500000, false, 500000);
   Check(r == EVE_REASON_GLOBAL_FLOATING_LOSS, "T8 decimal sum = -500.000,00 -> trigger", "total " + DoubleToString(t8, 8));
   double p8b[3] = {-166666.67, -166666.67, -166666.65};
   double t8b = CEvePositionScanner::SumFloating(p8b, 3, 2);
   r = CEveFloatingMonitor::Evaluate(t8b, true, 500000, false, 500000);
   Check(r == EVE_REASON_NONE, "T8 decimal sum = -499.999,99 -> no trigger", "total " + DoubleToString(t8b, 8));
  }

//+------------------------------------------------------------------+
//| T10: state machine                                               |
//+------------------------------------------------------------------+
void TestStateMachine()
  {
   Check(CEveStateMachine::IsAllowed(EVE_STATE_ARMED, EVE_STATE_PROTECTION_TRIGGERED), "T10 ARMED -> PROTECTION_TRIGGERED", "");
   Check(CEveStateMachine::IsAllowed(EVE_STATE_PROTECTION_TRIGGERED, EVE_STATE_CLOSING_ALL), "T10 PROTECTION_TRIGGERED -> CLOSING_ALL", "");
   Check(CEveStateMachine::IsAllowed(EVE_STATE_CLOSING_ALL, EVE_STATE_CLOSE_FAILED), "T10 CLOSING_ALL -> CLOSE_FAILED", "");
   Check(CEveStateMachine::IsAllowed(EVE_STATE_CLOSE_FAILED, EVE_STATE_CLOSING_ALL), "T10 CLOSE_FAILED -> CLOSING_ALL", "");
   Check(CEveStateMachine::IsAllowed(EVE_STATE_CLOSING_ALL, EVE_STATE_ALL_POSITIONS_CLOSED), "T10 CLOSING_ALL -> ALL_POSITIONS_CLOSED", "");
   Check(CEveStateMachine::IsAllowed(EVE_STATE_ALL_POSITIONS_CLOSED, EVE_STATE_LOCKED), "T10 ALL_POSITIONS_CLOSED -> LOCKED", "");
   Check(CEveStateMachine::IsAllowed(EVE_STATE_ALL_POSITIONS_CLOSED, EVE_STATE_ARMED), "T10 ALL_POSITIONS_CLOSED -> ARMED (lock OFF)", "");
   Check(CEveStateMachine::IsAllowed(EVE_STATE_LOCKED, EVE_STATE_ARMED), "T10 LOCKED -> ARMED (manual reset)", "");
   Check(CEveStateMachine::IsAllowed(EVE_STATE_VALIDATING, EVE_STATE_LOCKED), "T10 VALIDATING -> LOCKED (restore)", "");
   Check(CEveStateMachine::IsAllowed(EVE_STATE_VALIDATING, EVE_STATE_CLOSING_ALL), "T10 VALIDATING -> CLOSING_ALL (restore)", "");
   Check(!CEveStateMachine::IsAllowed(EVE_STATE_ARMED, EVE_STATE_LOCKED), "T10 ARMED -> LOCKED refused", "");
   Check(!CEveStateMachine::IsAllowed(EVE_STATE_LOCKED, EVE_STATE_CLOSING_ALL), "T10 LOCKED -> CLOSING_ALL refused", "");
   Check(!CEveStateMachine::IsAllowed(EVE_STATE_CLOSING_ALL, EVE_STATE_ARMED), "T10 CLOSING_ALL -> ARMED refused (must verify first)", "");
   Check(!CEveStateMachine::IsAllowed(EVE_STATE_SAFE_DISABLED, EVE_STATE_ARMED), "T10 SAFE_DISABLED -> ARMED refused", "");
   Check(!CEveStateMachine::IsAllowed(EVE_STATE_SAFE_DISABLED, EVE_STATE_STANDBY), "T10 SAFE_DISABLED -> STANDBY refused", "");

   CEveStateMachine sm;
   bool ok = sm.TransitionTo(EVE_STATE_VALIDATING, "test") && sm.TransitionTo(EVE_STATE_ARMED, "test") &&
             sm.TransitionTo(EVE_STATE_PROTECTION_TRIGGERED, "test") && sm.TransitionTo(EVE_STATE_CLOSING_ALL, "test") &&
             sm.TransitionTo(EVE_STATE_ALL_POSITIONS_CLOSED, "test") && sm.TransitionTo(EVE_STATE_LOCKED, "test");
   Check(ok && sm.State() == EVE_STATE_LOCKED, "T18 lock path ARMED -> ... -> LOCKED", EveStateName(sm.State()));
   bool refused = !sm.TransitionTo(EVE_STATE_CLOSING_ALL, "test");
   Check(refused && sm.State() == EVE_STATE_LOCKED, "T18 LOCKED cannot jump to CLOSING_ALL", EveStateName(sm.State()));
   Check(sm.TransitionTo(EVE_STATE_ARMED, "manual reset") && sm.State() == EVE_STATE_ARMED, "T18 manual reset -> ARMED", "");
  }

//+------------------------------------------------------------------+
//| T11-T17: aggregate SL solver and decisions                       |
//+------------------------------------------------------------------+
void TestSolver()
  {
   CTestLinearModel model;
   CEvePriceRiskCalculator calc;
   calc.SetModel(GetPointer(model));
   SEveSymbolSnapshot s;
   MakeSym(s, 2000.00, 2000.20, 0);
   SEveSolveResult res;
   double loss = 0.0;

   //--- T11 single BUY 0.10 @2000.00, budget 500k: loss/$ = 160.000 -> SL 1996.88 (rounded toward the market)
   SEvePosition g1[];
   ArrayResize(g1, 1);
   SetPos(g1, 0, 1, POSITION_TYPE_BUY, 0.10, 2000.00, 0.0);
   bool ok = calc.SolveGroupSL(g1, s, 500000.0, 1, true, res);
   Check(ok && Near(res.slPrice, 1996.88, 0.000001), "T11 BUY single SL price", "SL " + DoubleToString(res.slPrice, 2));
   Check(ok && res.lossAtSL <= 500000.0, "T11 BUY loss at SL <= budget", EveFormatIDR(res.lossAtSL));
   calc.GroupLossAt(g1, 1996.87, true, loss);
   Check(loss > 500000.0, "T11 BUY one tick further exceeds budget (furthest legal SL)", EveFormatIDR(loss));

   //--- T11 single SELL 0.10 @2000.00 -> SL 2003.12
   SEvePosition g2[];
   ArrayResize(g2, 1);
   SetPos(g2, 0, 2, POSITION_TYPE_SELL, 0.10, 2000.00, 0.0);
   ok = calc.SolveGroupSL(g2, s, 500000.0, 1, true, res);
   Check(ok && Near(res.slPrice, 2003.12, 0.000001), "T11 SELL single SL price", "SL " + DoubleToString(res.slPrice, 2));
   Check(ok && res.lossAtSL <= 500000.0, "T11 SELL loss at SL <= budget", EveFormatIDR(res.lossAtSL));
   calc.GroupLossAt(g2, 2003.13, true, loss);
   Check(loss > 500000.0, "T11 SELL one tick further exceeds budget", EveFormatIDR(loss));
   Check(CEvePriceRiskCalculator::IsLegalSL(POSITION_TYPE_SELL, res.slPrice, s, 1), "T11 SELL SL is above Ask (legal side)", "");

   //--- T12 basket of 3 BUYs with unequal volumes: one common SL, sum of losses <= budget
   SEvePosition g3[];
   ArrayResize(g3, 3);
   SetPos(g3, 0, 3, POSITION_TYPE_BUY, 0.10, 2000.00, 0.0);
   SetPos(g3, 1, 4, POSITION_TYPE_BUY, 0.20, 1999.00, 0.0);
   SetPos(g3, 2, 5, POSITION_TYPE_BUY, 0.30, 1998.00, 0.0);
   ok = calc.SolveGroupSL(g3, s, 500000.0, 1, true, res);
   double sum = 0.0;
   for(int i = 0; i < 3; i++)
     {
      double li = 0.0;
      calc.LossAt(g3[i].type, g3[i].symbol, g3[i].volume, g3[i].priceOpen, res.slPrice, li);
      sum += li;
     }
   Check(ok && sum <= 500000.0, "T12 basket 0.1/0.2/0.3: sum of SL losses <= budget",
         "SL " + DoubleToString(res.slPrice, 2) + " sum " + EveFormatIDR(sum));
   calc.GroupLossAt(g3, res.slPrice - 0.01, true, loss);
   Check(loss > 500000.0, "T12 basket SL is the furthest compliant price", EveFormatIDR(loss));
   // The 0.30 entry @1998.00 would be in profit at the SL: its profit is NOT used to widen the others (B-03).
   Check(Near(res.slPrice, 1998.30, 0.000001), "T12 profitable entry does not fund wider stops (clamped)",
         "SL " + DoubleToString(res.slPrice, 2));

   //--- T13 user example: 0.02 lot at -Rp200.000, then a new 0.05 lot entry
   SEvePosition g4[];
   ArrayResize(g4, 2);
   SetPos(g4, 0, 6, POSITION_TYPE_BUY, 0.02, 2006.25, 0.0);
   SetPos(g4, 1, 7, POSITION_TYPE_BUY, 0.05, 2000.20, 0.0);
   double first = 0.0;
   calc.LossAt(g4[0].type, g4[0].symbol, g4[0].volume, g4[0].priceOpen, s.bid, first);
   Check(Near(first, 200000.0, 0.01), "T13 entry #1 floating loss = Rp200.000", EveFormatIDR(first));
   double consumed = 0.0;
   calc.GroupLossAt(g4, s.bid, true, consumed);
   Check(Near(consumed, 216000.0, 0.01), "T13 basket floating loss now (incl. spread of entry #2)", EveFormatIDR(consumed));
   ok = calc.SolveGroupSL(g4, s, 500000.0, 1, true, res);
   Check(ok && Near(res.slPrice, 1997.47, 0.000001), "T13 common basket SL = 1997.47 (no forced close)",
         "SL " + DoubleToString(res.slPrice, 2));
   Check(ok && Near(res.lossAtSL, 499360.0, 0.01), "T13 total loss at SL = Rp499.360 <= Rp500.000", EveFormatIDR(res.lossAtSL));

   //--- T14 group budgets
   double w1 = 0.10 / 0.60;
   double w2 = 0.20 / 0.60;
   double w3 = 0.30 / 0.60;
   double b1 = CEveAggregateSLManager::GroupBudget(false, 0.0, 500000.0, 0.0, w1);
   double b2 = CEveAggregateSLManager::GroupBudget(false, 0.0, 500000.0, 0.0, w2);
   double b3 = CEveAggregateSLManager::GroupBudget(false, 0.0, 500000.0, 0.0, w3);
   Check(Near(b1, 83333.0, 0.001) && Near(b2, 166666.0, 0.001) && Near(b3, 250000.0, 0.001) && b1 + b2 + b3 <= 500000.0,
         "T14 proportional budgets 83.333/166.666/250.000 (sum <= budget)",
         EveFormatIDR(b1) + " " + EveFormatIDR(b2) + " " + EveFormatIDR(b3));
   // basket: group A consumed 300k, group B 0; headroom 200k split 50/50
   double ba = CEveAggregateSLManager::GroupBudget(true, 300000.0, 500000.0, 300000.0, 0.5);
   double bb = CEveAggregateSLManager::GroupBudget(true, 0.0, 500000.0, 300000.0, 0.5);
   Check(Near(ba, 400000.0, 0.001) && Near(bb, 100000.0, 0.001) && ba + bb <= 500000.0,
         "T14 basket budgets = consumed + headroom share (sum <= budget)", EveFormatIDR(ba) + " + " + EveFormatIDR(bb));

   //--- T15 broker stop level makes the budget impossible -> UNSATISFIABLE, nothing placed
   SEveSymbolSnapshot sWide;
   MakeSym(sWide, 2000.00, 2000.20, 500);
   SEvePosition g5[];
   ArrayResize(g5, 1);
   SetPos(g5, 0, 8, POSITION_TYPE_BUY, 1.00, 2000.00, 0.0);
   ok = calc.SolveGroupSL(g5, sWide, 500000.0, 1, true, res);
   Check(!ok && res.status == EVE_SOLVE_UNSATISFIABLE, "T15 stop level 500 pt, 1 lot: UNSATISFIABLE",
         "closest legal " + DoubleToString(res.closestLegalSL, 2) + " loss " + EveFormatIDR(res.lossAtClosestLegal));
   Check(Near(res.closestLegalSL, 1994.99, 0.000001) && res.lossAtClosestLegal > 500000.0,
         "T15 reports closest legal SL and its loss", "");
   // already beyond the budget (price moved through it)
   SEvePosition g6[];
   ArrayResize(g6, 1);
   SetPos(g6, 0, 9, POSITION_TYPE_BUY, 0.10, 2004.00, 0.0);   // floating -640k already
   ok = calc.SolveGroupSL(g6, s, 500000.0, 1, true, res);
   Check(!ok && res.status == EVE_SOLVE_UNSATISFIABLE, "T15 floating loss already above budget -> UNSATISFIABLE", "");

   //--- T16 stop that locks profit counts as 0 and is never widened (B-01)
   SEvePosition lp;
   MakePos(lp, 10, POSITION_TYPE_BUY, 0.10, 2000.00, 2003.00);
   double lpl = -1.0;
   calc.PositionLossAt(lp, lp.sl, lpl);
   Check(Near(lpl, 0.0, 0.000001), "T16 BUY SL above open: theoretical loss 0 (no abs())", EveFormatIDR(lpl));
   Check(!CEvePriceRiskCalculator::ShouldMoveSL(POSITION_TYPE_BUY, 2003.00, 2000.00, 1996.88, true, 0.01),
         "T16 profit-locking SL kept (preserve ON)", "");
   Check(!CEvePriceRiskCalculator::ShouldMoveSL(POSITION_TYPE_BUY, 2003.00, 2000.00, 1996.88, false, 0.01),
         "T16 profit-locking SL kept even with preserve OFF", "");
   Check(Near(CEvePriceRiskCalculator::EffectiveStop(POSITION_TYPE_BUY, 2003.00, 2000.00, 1996.88, false), 2003.00, 0.000001),
         "T16 effective stop stays at the profit-locking SL", "");
   SEvePosition lps;
   MakePos(lps, 11, POSITION_TYPE_SELL, 0.10, 2000.00, 1995.00);
   calc.PositionLossAt(lps, lps.sl, lpl);
   Check(Near(lpl, 0.0, 0.000001), "T16 SELL SL below open: theoretical loss 0", EveFormatIDR(lpl));

   //--- T17 preserve / tighten / widen decisions
   Check(!CEvePriceRiskCalculator::ShouldMoveSL(POSITION_TYPE_BUY, 1999.00, 2000.00, 1996.88, true, 0.01),
         "T17 tighter existing BUY SL preserved", "");
   Check(CEvePriceRiskCalculator::ShouldMoveSL(POSITION_TYPE_BUY, 1995.00, 2000.00, 1996.88, true, 0.01),
         "T17 wider existing BUY SL is tightened", "");
   Check(CEvePriceRiskCalculator::ShouldMoveSL(POSITION_TYPE_BUY, 0.0, 2000.00, 1996.88, true, 0.01),
         "T17 missing SL is set", "");
   Check(CEvePriceRiskCalculator::ShouldMoveSL(POSITION_TYPE_BUY, 1999.00, 2000.00, 1996.88, false, 0.01),
         "T17 preserve OFF: loss-side SL may be widened within budget", "");
   Check(!CEvePriceRiskCalculator::ShouldMoveSL(POSITION_TYPE_SELL, 2001.00, 2000.00, 2003.12, true, 0.01),
         "T17 tighter existing SELL SL preserved", "");
   Check(CEvePriceRiskCalculator::ShouldMoveSL(POSITION_TYPE_SELL, 2010.00, 2000.00, 2003.12, true, 0.01),
         "T17 wider existing SELL SL is tightened", "");
   Check(!CEvePriceRiskCalculator::ShouldMoveSL(POSITION_TYPE_BUY, 1996.88, 2000.00, 1996.88, true, 0.01),
         "T17 identical SL: no modification (idempotent)", "");
   Check(CEvePriceRiskCalculator::IsMoreProtective(POSITION_TYPE_BUY, 1999.0, 1998.0) &&
         CEvePriceRiskCalculator::IsMoreProtective(POSITION_TYPE_SELL, 2001.0, 2002.0) &&
         !CEvePriceRiskCalculator::IsMoreProtective(POSITION_TYPE_BUY, 1997.0, 1998.0),
         "T17 BUY higher / SELL lower SL is more protective", "");

   //--- preserved tighter SL inside a basket reduces the group loss
   SEvePosition g7[];
   ArrayResize(g7, 2);
   SetPos(g7, 0, 12, POSITION_TYPE_BUY, 0.10, 2000.00, 1999.00);
   SetPos(g7, 1, 13, POSITION_TYPE_BUY, 0.10, 2000.00, 0.0);
   ok = calc.SolveGroupSL(g7, s, 500000.0, 1, true, res);
   double withPreserved = 0.0;
   calc.GroupLossAt(g7, res.slPrice, true, withPreserved);
   Check(ok && withPreserved <= 500000.0, "T17 basket with one preserved tighter SL stays within budget",
         "SL " + DoubleToString(res.slPrice, 2) + " loss " + EveFormatIDR(withPreserved));

   //--- legality (B-02: relative to market, not to open price)
   Check(CEvePriceRiskCalculator::IsLegalSL(POSITION_TYPE_BUY, 1996.88, s, 1), "B-02 BUY SL below Bid is legal", "");
   Check(!CEvePriceRiskCalculator::IsLegalSL(POSITION_TYPE_BUY, 2000.01, s, 0), "B-02 BUY SL above Bid is illegal", "");
   Check(CEvePriceRiskCalculator::IsLegalSL(POSITION_TYPE_BUY, 1999.50, s, 1), "B-02 BUY SL legal even if above an older open price", "");
   Check(!CEvePriceRiskCalculator::IsLegalSL(POSITION_TYPE_SELL, 2000.10, s, 0), "B-02 SELL SL below Ask is illegal", "");
  }

//+------------------------------------------------------------------+
//| T25: retcode classification                                      |
//+------------------------------------------------------------------+
void TestRetcodes()
  {
   Check(CEveTradeExecutor::ClassifyRetcode(TRADE_RETCODE_DONE) == EVE_RCC_SUCCESS, "T25 DONE -> success", "");
   Check(CEveTradeExecutor::ClassifyRetcode(TRADE_RETCODE_DONE_PARTIAL) == EVE_RCC_SUCCESS, "T25 DONE_PARTIAL -> success (remainder re-sent)", "");
   Check(CEveTradeExecutor::ClassifyRetcode(TRADE_RETCODE_REQUOTE) == EVE_RCC_RETRY, "T25 REQUOTE -> retry", "");
   Check(CEveTradeExecutor::ClassifyRetcode(TRADE_RETCODE_PRICE_OFF) == EVE_RCC_RETRY, "T25 PRICE_OFF -> retry", "");
   Check(CEveTradeExecutor::ClassifyRetcode(TRADE_RETCODE_MARKET_CLOSED) == EVE_RCC_RETRY_SLOW, "T25 MARKET_CLOSED -> slow retry (never give up)", "");
   Check(CEveTradeExecutor::ClassifyRetcode(TRADE_RETCODE_CLIENT_DISABLES_AT) == EVE_RCC_RETRY_SLOW, "T25 AutoTrading OFF -> slow retry", "");
   Check(CEveTradeExecutor::ClassifyRetcode(TRADE_RETCODE_POSITION_CLOSED) == EVE_RCC_GONE, "T25 POSITION_CLOSED -> verify gone", "");
   Check(CEveTradeExecutor::ClassifyRetcode(TRADE_RETCODE_INVALID_FILL) == EVE_RCC_REFILL, "T25 INVALID_FILL -> rotate filling", "");
   Check(CEveTradeExecutor::ClassifyRetcode(TRADE_RETCODE_NO_CHANGES) == EVE_RCC_NO_CHANGE, "T25 NO_CHANGES -> verify", "");
  }

//+------------------------------------------------------------------+
//| Configuration validation (K-03, K-04)                            |
//+------------------------------------------------------------------+
void TestConfig()
  {
   SEveConfig cfgIn;
   SEveConfig cfgOut;
   SEveFeatureFlags f;
   string errors[];
   string warnings[];

   EveConfigSetDefaults(cfgIn);
   cfgIn.maxAggregateSLRiskIDR = 0;
   CEveConfigurationValidator::Validate(cfgIn, cfgOut, f, errors, warnings);
   Check(!f.slActive && f.lossActive, "K-04 invalid SL budget disables ONLY the SL engine", IntegerToString(ArraySize(errors)) + " error(s)");

   EveConfigSetDefaults(cfgIn);
   cfgIn.maxGlobalLossIDR = -5;
   CEveConfigurationValidator::Validate(cfgIn, cfgOut, f, errors, warnings);
   Check(!f.lossActive && f.slActive, "K-04 invalid loss limit disables ONLY global loss protection", "");

   EveConfigSetDefaults(cfgIn);
   cfgIn.lockAfterGlobalLoss = true;
   cfgIn.requireManualResetLoss = false;
   CEveConfigurationValidator::Validate(cfgIn, cfgOut, f, errors, warnings);
   Check(cfgOut.requireManualResetLoss && ArraySize(errors) > 0, "K-03 lock ON without manual reset -> error, manual reset enforced", "");

   EveConfigSetDefaults(cfgIn);
   cfgIn.enableGlobalLoss = false;
   cfgIn.enableGlobalProfit = false;
   cfgIn.enableAggregateSL = false;
   CEveConfigurationValidator::Validate(cfgIn, cfgOut, f, errors, warnings);
   bool warned = false;
   for(int i = 0; i < ArraySize(warnings); i++)
      if(StringFind(warnings[i], "ALL AUTOMATIC RISK PROTECTION IS DISABLED") >= 0)
         warned = true;
   Check(!f.anyActive && warned, "Spec 19: all protection disabled -> warning", "");

   EveConfigSetDefaults(cfgIn);
   cfgIn.closeRetryCount = -1;
   cfgIn.reconciliationIntervalMs = 0;
   CEveConfigurationValidator::Validate(cfgIn, cfgOut, f, errors, warnings);
   Check(cfgOut.closeRetryCount == 5 && cfgOut.reconciliationIntervalMs == 250 && ArraySize(errors) == 2,
         "Spec 19: negative retry count / invalid timer -> error + safe default", IntegerToString(ArraySize(errors)) + " error(s)");

   EveConfigSetDefaults(cfgIn);
   CEveConfigurationValidator::Validate(cfgIn, cfgOut, f, errors, warnings);
   Check(ArraySize(errors) == 0 && f.lossActive && f.slActive && !f.profitActive && !cfgOut.lockAfterGlobalLoss,
         "Defaults valid: loss ON, profit OFF, SL ON, lock OFF (user decision Q4)", "");
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   ArrayResize(g_lines, 0);
   AddLine("=== " + EVE_RP_NAME + " v" + EVE_RP_VERSION + " unit tests ===");
   TestFormatter();
   TestTriggers();
   TestStateMachine();
   TestSolver();
   TestRetcodes();
   TestConfig();
   string summary = "=== RESULT: " + IntegerToString(g_pass) + " passed, " + IntegerToString(g_fail) + " failed ===";
   AddLine(summary);

   int h = FileOpen("EVE_Risk_UnitTests_Result.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h != INVALID_HANDLE)
     {
      for(int i = 0; i < ArraySize(g_lines); i++)
         FileWriteString(h, g_lines[i] + "\r\n");
      FileClose(h);
      Print("Result file: MQL5\\Files\\EVE_Risk_UnitTests_Result.txt");
     }
   Comment(summary);
   if(g_fail > 0)
      Alert(summary);
  }
//+------------------------------------------------------------------+
