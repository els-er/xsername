//+------------------------------------------------------------------+
//|                                EVE_RiskProtector_TestHarness.mq5 |
//| STRATEGY TESTER ONLY. Runs the protector engine (the same         |
//| CEveRiskProtectorApp as the production EA) and opens SCRIPTED     |
//| positions to exercise it, while checking invariants on every     |
//| event. It refuses to run outside the Strategy Tester.            |
//|                                                                  |
//| This file is a test tool. The production EA                      |
//| (EVE_IDR_RiskProtector.mq5) contains no position-opening code.   |
//+------------------------------------------------------------------+
#property copyright   "EVE"
#property version     "1.10"
#property description "TEST HARNESS - Strategy Tester only. Opens scripted positions to test the protector."
#property description "NEVER attach to a live or demo chart (it refuses to start outside the tester)."

#include <EVE_Risk\RiskProtectorApp.mqh>

enum ENUM_HARNESS_SCENARIO
  {
   HS_BASKET_MULTI_ENTRY = 1, // 1: multi-entry basket (0.02 + 0.05 + SELL) - SL budget + loss trigger
   HS_LOCK_AND_REENTRY   = 2, // 2: loss trigger with LOCK ON, re-entry while locked, manual reset
   HS_PROFIT_TARGET      = 3, // 3: profit target close-all (lock OFF) and re-entry
   HS_LOCK_OFF_REENTRY   = 4, // 4: loss trigger with LOCK OFF, immediate re-entry allowed
   HS_TRAILING_AND_TP    = 5  // 5: basket trailing stop + basket TP (SL must never move away)
  };

input ENUM_HARNESS_SCENARIO Scenario       = HS_BASKET_MULTI_ENTRY; // SCENARIO
input long   LossLimit                     = 500000;  // LOSS LIMIT (deposit currency units)
input long   ProfitTarget                  = 500000;  // PROFIT TARGET (deposit currency units)
input long   SLBudget                      = 500000;  // SL BUDGET (deposit currency units)
input long   TrailStart                    = 100000;  // TRAILING START (deposit currency units)
input long   TrailDistance                 = 50000;   // TRAILING DISTANCE (deposit currency units)
input long   TrailStep                     = 10000;   // TRAILING STEP (deposit currency units)
input long   BasketTP                      = 300000;  // BASKET TP (deposit currency units)
input bool   ParallelOrders                = true;    // SEND ORDERS IN PARALLEL (async)
input double LotA                          = 0.02;    // LOT ENTRY A
input double LotB                          = 0.05;    // LOT ENTRY B
input double LotC                          = 0.03;    // LOT ENTRY C (SELL)
input int    MinutesBetweenEntries         = 30;      // MINUTES BETWEEN SCRIPTED ENTRIES
input bool   AllowNonIDRDepositForTest     = true;    // ACCEPT NON-IDR TESTER DEPOSIT (test only)

CEveRiskProtectorApp g_app;

int      g_step = 0;
datetime g_nextActionTime = 0;
int      g_invariantFailures = 0;
int      g_checks = 0;
int      g_triggers = 0;
int      g_locks = 0;
int      g_resets = 0;
ENUM_EVE_STATE g_prevState = EVE_STATE_INIT;
datetime g_lockedPositionSince = 0;
string   g_failLog[];
ulong    g_slTickets[];   // INV5: last SL seen per ticket
double   g_slValues[];
int      g_slTypes[];

//+------------------------------------------------------------------+
void HarnessFail(const string msg)
  {
   g_invariantFailures++;
   int n = ArraySize(g_failLog);
   if(n < 50)
     {
      ArrayResize(g_failLog, n + 1);
      g_failLog[n] = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " " + msg;
     }
   Print("HARNESS INVARIANT FAIL | ", msg);
  }

//+------------------------------------------------------------------+
//| Opens a scripted market position (test tool only)                |
//+------------------------------------------------------------------+
bool HarnessOpen(const ENUM_ORDER_TYPE type, const double lots)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return false;
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = lots;
   req.type         = type;
   req.price        = (type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   req.deviation    = 100;
   req.magic        = 123456;
   req.comment      = "HARNESS";
   req.type_filling = CEveTradeExecutor::FillingFor(_Symbol, 0);
   bool ok = OrderSend(req, res);
   Print("HARNESS open ", EnumToString(type), " ", DoubleToString(lots, 2), " -> ", res.retcode);
   return (ok && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED));
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(MQLInfoInteger(MQL_TESTER) == 0)
     {
      Print("EVE TEST HARNESS refuses to run outside the Strategy Tester.");
      return INIT_FAILED;
     }
   SEveConfig c;
   EveConfigSetDefaults(c);
   c.maxGlobalLossIDR      = LossLimit;
   c.globalProfitTargetIDR = ProfitTarget;
   c.maxAggregateSLRiskIDR = SLBudget;
   c.enableGlobalProfit    = (Scenario == HS_PROFIT_TARGET);
   c.lockAfterGlobalLoss   = (Scenario == HS_LOCK_AND_REENTRY);
   c.requireManualResetLoss = true;
   c.enablePush            = false;
   c.enableAlerts          = false;
   c.enableFileLog         = true;
   c.testAllowAnyCurrency  = AllowNonIDRDepositForTest;
   if(Scenario == HS_PROFIT_TARGET)
      c.enableAggregateSL = false;   // let the profit target be reached instead of the SLs
   c.trailingEnabled       = (Scenario == HS_TRAILING_AND_TP);
   c.trailingStartIDR      = TrailStart;
   c.trailingDistanceIDR   = TrailDistance;
   c.trailingStepIDR       = TrailStep;
   c.tpEnabled             = (Scenario == HS_TRAILING_AND_TP);
   c.tpBasketIDR           = BasketTP;
   c.asyncSend             = ParallelOrders;
   g_nextActionTime = 0;
   g_step = 0;
   return g_app.Init(c);
  }

//+------------------------------------------------------------------+
void CheckInvariants(const bool afterFullCycle)
  {
   g_checks++;
   ENUM_EVE_STATE st = g_app.State();
   double fl = g_app.Floating();

   //--- INV1/INV2: an ARMED engine never sits beyond a threshold after its cycle
   if(st == EVE_STATE_ARMED && g_app.LossActive() && fl <= -(double)g_app.LossLimit())
      HarnessFail("ARMED while floating " + DoubleToString(fl, 2) + " <= -" + IntegerToString(g_app.LossLimit()));
   if(st == EVE_STATE_ARMED && g_app.ProfitActive() && fl >= (double)g_app.ProfitTarget())
      HarnessFail("ARMED while floating " + DoubleToString(fl, 2) + " >= " + IntegerToString(g_app.ProfitTarget()));

   //--- INV3: once every position carries an SL and nothing is in flight, the budget holds
   //--- (SL statistics are refreshed by timer cycles, so this is checked after OnTimer only)
   if(afterFullCycle && st == EVE_STATE_ARMED && g_app.SLActive() && g_app.Positions() > 0 && !g_app.HasActiveOps())
     {
      bool allHaveSL = true;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(PositionGetTicket(i) == 0)
            continue;
         if(PositionGetDouble(POSITION_SL) <= 0.0)
            allHaveSL = false;
        }
      if(allHaveSL && g_app.SLTheoretical() > (double)g_app.SLBudget() + 1.0)
         HarnessFail("SL theoretical loss " + DoubleToString(g_app.SLTheoretical(), 2) + " > budget " +
                     IntegerToString(g_app.SLBudget()));
     }

   //--- INV4: while LOCKED with the close policy, positions must disappear quickly
   if(st == EVE_STATE_LOCKED && PositionsTotal() > 0)
     {
      if(g_lockedPositionSince == 0)
         g_lockedPositionSince = TimeCurrent();
      else
         if(TimeCurrent() - g_lockedPositionSince > 60)
            HarnessFail("position still open 60 s after being detected while LOCKED");
     }
   else
      g_lockedPositionSince = 0;

   //--- INV5: with never-widen ON, an SL never moves further away from the market
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      double sl = PositionGetDouble(POSITION_SL);
      int type = (int)PositionGetInteger(POSITION_TYPE);
      int idx = -1;
      for(int k = 0; k < ArraySize(g_slTickets); k++)
         if(g_slTickets[k] == t)
           {
            idx = k;
            break;
           }
      if(idx < 0)
        {
         idx = ArraySize(g_slTickets);
         ArrayResize(g_slTickets, idx + 1);
         ArrayResize(g_slValues, idx + 1);
         ArrayResize(g_slTypes, idx + 1);
         g_slTickets[idx] = t;
         g_slValues[idx] = sl;
         g_slTypes[idx] = type;
         continue;
        }
      double prev = g_slValues[idx];
      if(prev > 0.0 && sl > 0.0)
        {
         bool looser = (type == (int)POSITION_TYPE_BUY) ? (sl < prev - 0.0000001) : (sl > prev + 0.0000001);
         if(looser)
            HarnessFail("SL of #" + IntegerToString((long)t) + " moved AWAY from the market: " +
                        DoubleToString(prev, 5) + " -> " + DoubleToString(sl, 5));
        }
      if(prev > 0.0 && sl <= 0.0)
         HarnessFail("SL of #" + IntegerToString((long)t) + " was REMOVED");
      g_slValues[idx] = sl;
     }

   //--- bookkeeping
   if(st != g_prevState)
     {
      if(st == EVE_STATE_PROTECTION_TRIGGERED || (st == EVE_STATE_CLOSING_ALL && g_prevState == EVE_STATE_ARMED))
         g_triggers++;
      if(st == EVE_STATE_LOCKED)
         g_locks++;
      g_prevState = st;
     }
  }

//+------------------------------------------------------------------+
//| Scripted scenario steps                                          |
//+------------------------------------------------------------------+
void RunScenario(void)
  {
   datetime now = TimeCurrent();
   if(now < g_nextActionTime)
      return;
   ENUM_EVE_STATE st = g_app.State();
   int gap = MinutesBetweenEntries * 60;

   switch(Scenario)
     {
      case HS_BASKET_MULTI_ENTRY:
         if(st != EVE_STATE_ARMED)
            return;
         if(g_step == 0 && HarnessOpen(ORDER_TYPE_BUY, LotA))
            g_step = 1;
         else
            if(g_step == 1 && HarnessOpen(ORDER_TYPE_BUY, LotB))
               g_step = 2;
            else
               if(g_step == 2 && HarnessOpen(ORDER_TYPE_SELL, LotC))
                  g_step = 3;
               else
                  if(g_step == 3 && PositionsTotal() == 0)
                     g_step = 0;   // after a close-all / SL hit: start a new basket
         g_nextActionTime = now + gap;
         break;

      case HS_LOCK_AND_REENTRY:
         if(g_step == 0 && st == EVE_STATE_ARMED && HarnessOpen(ORDER_TYPE_BUY, LotB))
            g_step = 1;
         else
            if(g_step == 1 && st == EVE_STATE_LOCKED)
              {
               //--- re-entry while LOCKED: must be closed by the lock policy
               if(HarnessOpen(ORDER_TYPE_BUY, LotA))
                  g_step = 2;
              }
            else
               if(g_step == 2 && st == EVE_STATE_LOCKED && PositionsTotal() == 0 && !g_app.HasActiveOps())
                 {
                  g_app.TestManualReset();
                  if(g_app.State() == EVE_STATE_ARMED)
                    {
                     g_resets++;
                     g_step = 0;
                    }
                  else
                     HarnessFail("manual reset did not re-arm");
                 }
         g_nextActionTime = now + gap;
         break;

      case HS_PROFIT_TARGET:
      case HS_LOCK_OFF_REENTRY:
      case HS_TRAILING_AND_TP:
         if(st != EVE_STATE_ARMED)
            return;
         if(PositionsTotal() == 0)
           {
            HarnessOpen(ORDER_TYPE_BUY, LotA);
            HarnessOpen(ORDER_TYPE_BUY, LotB);
           }
         g_nextActionTime = now + gap;
         break;
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   g_app.OnTickEvent();
   CheckInvariants(false);
   RunScenario();
  }

void OnTimer()
  {
   g_app.OnTimerEvent();
   CheckInvariants(true);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   g_app.OnTradeTransactionEvent(trans, request, result);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_app.Deinit(reason);
   string summary = "HARNESS SUMMARY scenario " + IntegerToString((int)Scenario) +
                    " | invariant checks " + IntegerToString(g_checks) +
                    " | invariant FAILURES " + IntegerToString(g_invariantFailures) +
                    " | protection triggers " + IntegerToString(g_triggers) +
                    " | locks " + IntegerToString(g_locks) +
                    " | manual resets " + IntegerToString(g_resets);
   Print(summary);
   int h = FileOpen("EVE_Risk_Harness_Result_S" + IntegerToString((int)Scenario) + ".txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h != INVALID_HANDLE)
     {
      FileWriteString(h, summary + "\r\n");
      for(int i = 0; i < ArraySize(g_failLog); i++)
         FileWriteString(h, "FAIL " + g_failLog[i] + "\r\n");
      FileClose(h);
     }
  }

//+------------------------------------------------------------------+
double OnTester()
  {
   // custom criterion: 1 = all invariants held, 0 = at least one failure
   return (g_invariantFailures == 0) ? 1.0 : 0.0;
  }
//+------------------------------------------------------------------+
