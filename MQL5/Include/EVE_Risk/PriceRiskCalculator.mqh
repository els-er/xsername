//+------------------------------------------------------------------+
//|                                          PriceRiskCalculator.mqh |
//| Converts an IDR risk budget into a broker-valid SL price.        |
//|                                                                  |
//| Theoretical loss of a position closed at price X (audit B-01):   |
//|   Loss(X) = max(0, -OrderCalcProfit(type, sym, vol, OPEN, X))    |
//| measured from POSITION_PRICE_OPEN (spec 10), signed and clamped: |
//| a stop that locks profit counts as 0 loss and never offsets the  |
//| risk of other positions (audit B-03). Swap/commission excluded.  |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_PRICERISKCALCULATOR_MQH
#define EVE_RISK_PRICERISKCALCULATOR_MQH

#include "Defines.mqh"
#include "PositionScanner.mqh"

//+------------------------------------------------------------------+
//| Profit model. The default uses OrderCalcProfit (account currency, |
//| broker contract specification). Unit tests inject a linear model.|
//+------------------------------------------------------------------+
class CEveProfitModel
  {
public:
   virtual          ~CEveProfitModel(void) {}
   virtual bool      Profit(const ENUM_POSITION_TYPE type, const string symbol, const double volume,
                            const double priceOpen, const double priceClose, double &profit)
     {
      ENUM_ORDER_TYPE ot = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      profit = 0.0;
      ResetLastError();
      if(!OrderCalcProfit(ot, symbol, volume, priceOpen, priceClose, profit))
         return false;
      return MathIsValidNumber(profit);
     }
  };

//+------------------------------------------------------------------+
//| Symbol trading properties needed for SL validation               |
//+------------------------------------------------------------------+
struct SEveSymbolSnapshot
  {
   string            symbol;
   bool              valid;
   double            bid;
   double            ask;
   double            point;
   double            tickSize;
   int               digits;
   int               stopsLevel;
   int               freezeLevel;
   double            volumeMin;
   double            volumeMax;
   double            volumeStep;
   long              tradeMode;
   long              exeMode;
   long              fillingMode;
  };

bool EveReadSymbol(const string symbol, SEveSymbolSnapshot &s)
  {
   s.symbol      = symbol;
   s.valid       = false;
   s.bid         = 0.0;
   s.ask         = 0.0;
   s.point       = SymbolInfoDouble(symbol, SYMBOL_POINT);
   s.tickSize    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   s.digits      = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   s.stopsLevel  = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   s.freezeLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   s.volumeMin   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   s.volumeMax   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   s.volumeStep  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   s.tradeMode   = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   s.exeMode     = SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE);
   s.fillingMode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if(s.tickSize <= 0.0)
      s.tickSize = s.point;
   if(s.stopsLevel < 0)
      s.stopsLevel = 0;
   if(s.freezeLevel < 0)
      s.freezeLevel = 0;
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return false;
   s.bid = tick.bid;
   s.ask = tick.ask;
   s.valid = (s.bid > 0.0 && s.ask > 0.0 && s.tickSize > 0.0 && s.point > 0.0);
   return s.valid;
  }

//+------------------------------------------------------------------+
//| Solver result                                                    |
//+------------------------------------------------------------------+
enum ENUM_EVE_SOLVE_STATUS
  {
   EVE_SOLVE_OK                = 0,
   EVE_SOLVE_UNSATISFIABLE     = 1,
   EVE_SOLVE_CALC_ERROR        = 2,
   EVE_SOLVE_MARKET_DATA_ERROR = 3
  };

struct SEveSolveResult
  {
   int               status;
   double            slPrice;
   double            lossAtSL;
   double            closestLegalSL;
   double            lossAtClosestLegal;
   double            budget;
  };

//+------------------------------------------------------------------+
//| CEvePriceRiskCalculator                                          |
//+------------------------------------------------------------------+
class CEvePriceRiskCalculator
  {
private:
   CEveProfitModel   m_defaultModel;
   CEveProfitModel  *m_model;

public:
                     CEvePriceRiskCalculator(void);
   void              SetModel(CEveProfitModel *model);

   bool              LossAt(const ENUM_POSITION_TYPE type, const string symbol, const double volume,
                            const double priceOpen, const double price, double &loss);
   bool              PositionLossAt(const SEvePosition &p, const double price, double &loss);
   bool              GroupLossAt(const SEvePosition &grp[], const double price, const bool preserve, double &loss);
   bool              SolveGroupSL(const SEvePosition &grp[], const SEveSymbolSnapshot &s, const double budget,
                                  const int bufferTicks, const bool preserve, SEveSolveResult &res);

   static bool       IsMoreProtective(const ENUM_POSITION_TYPE type, const double candidateSL, const double referenceSL);
   static bool       StopLocksProfit(const ENUM_POSITION_TYPE type, const double sl, const double priceOpen);
   static double     EffectiveStop(const ENUM_POSITION_TYPE type, const double currentSL, const double priceOpen,
                                   const double price, const bool preserve);
   static bool       ShouldMoveSL(const ENUM_POSITION_TYPE type, const double currentSL, const double priceOpen,
                                  const double groupSL, const bool preserve, const double tickSize);
   static double     MinStopDistance(const SEveSymbolSnapshot &s, const int bufferTicks);
   static bool       IsLegalSL(const ENUM_POSITION_TYPE type, const double sl, const SEveSymbolSnapshot &s, const int bufferTicks);
   static double     PriceFromIndex(const long k, const SEveSymbolSnapshot &s);
  };

//+------------------------------------------------------------------+
CEvePriceRiskCalculator::CEvePriceRiskCalculator(void)
  {
   m_model = GetPointer(m_defaultModel);
  }

//+------------------------------------------------------------------+
void CEvePriceRiskCalculator::SetModel(CEveProfitModel *model)
  {
   if(model != NULL)
      m_model = model;
   else
      m_model = GetPointer(m_defaultModel);
  }

//+------------------------------------------------------------------+
//| BUY: higher SL is more protective. SELL: lower SL is more         |
//| protective. Any SL is more protective than no SL (0).            |
//+------------------------------------------------------------------+
bool CEvePriceRiskCalculator::IsMoreProtective(const ENUM_POSITION_TYPE type, const double candidateSL, const double referenceSL)
  {
   if(candidateSL <= 0.0)
      return false;
   if(referenceSL <= 0.0)
      return true;
   if(type == POSITION_TYPE_BUY)
      return (candidateSL > referenceSL);
   return (candidateSL < referenceSL);
  }

//+------------------------------------------------------------------+
//| True if the stop is at/beyond breakeven (theoretical loss 0).    |
//+------------------------------------------------------------------+
bool CEvePriceRiskCalculator::StopLocksProfit(const ENUM_POSITION_TYPE type, const double sl, const double priceOpen)
  {
   if(sl <= 0.0)
      return false;
   if(type == POSITION_TYPE_BUY)
      return (sl >= priceOpen);
   return (sl <= priceOpen);
  }

//+------------------------------------------------------------------+
//| Stop that applies to p if a common basket SL is placed at price. |
//| An existing SL that is more protective than price is kept when    |
//| preservation is on, and ALWAYS kept when it locks profit.        |
//+------------------------------------------------------------------+
double CEvePriceRiskCalculator::EffectiveStop(const ENUM_POSITION_TYPE type, const double currentSL, const double priceOpen,
                                              const double price, const bool preserve)
  {
   if(currentSL <= 0.0)
      return price;
   if(!preserve && !StopLocksProfit(type, currentSL, priceOpen))
      return price;
   if(IsMoreProtective(type, currentSL, price))
      return currentSL;
   return price;
  }

//+------------------------------------------------------------------+
//| Decision for one position once the group SL price is known.      |
//| Never widens unless preservation is disabled, and never widens a |
//| stop that locks profit.                                          |
//+------------------------------------------------------------------+
bool CEvePriceRiskCalculator::ShouldMoveSL(const ENUM_POSITION_TYPE type, const double currentSL, const double priceOpen,
                                           const double groupSL, const bool preserve, const double tickSize)
  {
   if(groupSL <= 0.0)
      return false;
   if(currentSL <= 0.0)
      return true;
   if(MathAbs(currentSL - groupSL) < tickSize * 0.5)
      return false;
   if(IsMoreProtective(type, groupSL, currentSL))
      return true;
   if(preserve)
      return false;
   if(StopLocksProfit(type, currentSL, priceOpen))
      return false;
   return true;
  }

//+------------------------------------------------------------------+
double CEvePriceRiskCalculator::MinStopDistance(const SEveSymbolSnapshot &s, const int bufferTicks)
  {
   int levelPoints = (s.stopsLevel > s.freezeLevel) ? s.stopsLevel : s.freezeLevel;
   int buffer = (bufferTicks > 0) ? bufferTicks : 0;
   return (double)levelPoints * s.point + (double)buffer * s.tickSize;
  }

//+------------------------------------------------------------------+
//| BUY SL must be below Bid, SELL SL above Ask, by the broker stop / |
//| freeze distance (audit B-02: relative to market, not open price). |
//+------------------------------------------------------------------+
bool CEvePriceRiskCalculator::IsLegalSL(const ENUM_POSITION_TYPE type, const double sl,
                                        const SEveSymbolSnapshot &s, const int bufferTicks)
  {
   if(sl <= 0.0 || !s.valid)
      return false;
   double d = MinStopDistance(s, bufferTicks);
   double tol = s.tickSize * 0.001;
   if(type == POSITION_TYPE_BUY)
      return (sl <= s.bid - d + tol);
   return (sl >= s.ask + d - tol);
  }

//+------------------------------------------------------------------+
double CEvePriceRiskCalculator::PriceFromIndex(const long k, const SEveSymbolSnapshot &s)
  {
   return NormalizeDouble((double)k * s.tickSize, s.digits);
  }

//+------------------------------------------------------------------+
bool CEvePriceRiskCalculator::LossAt(const ENUM_POSITION_TYPE type, const string symbol, const double volume,
                                     const double priceOpen, const double price, double &loss)
  {
   loss = 0.0;
   double profit = 0.0;
   if(!m_model.Profit(type, symbol, volume, priceOpen, price, profit))
      return false;
   loss = MathMax(0.0, -profit);
   return true;
  }

//+------------------------------------------------------------------+
bool CEvePriceRiskCalculator::PositionLossAt(const SEvePosition &p, const double price, double &loss)
  {
   return LossAt(p.type, p.symbol, p.volume, p.priceOpen, price, loss);
  }

//+------------------------------------------------------------------+
bool CEvePriceRiskCalculator::GroupLossAt(const SEvePosition &grp[], const double price, const bool preserve, double &loss)
  {
   loss = 0.0;
   int n = ArraySize(grp);
   for(int i = 0; i < n; i++)
     {
      double stop = EffectiveStop(grp[i].type, grp[i].sl, grp[i].priceOpen, price, preserve);
      double li = 0.0;
      if(!LossAt(grp[i].type, grp[i].symbol, grp[i].volume, grp[i].priceOpen, stop, li))
         return false;
      loss += li;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Finds the FURTHEST legal common SL price for a group (same symbol |
//| and direction) whose total theoretical loss is <= budget.         |
//| Binary search on tick indices; result is a multiple of           |
//| SYMBOL_TRADE_TICK_SIZE and always rounded toward lower risk.     |
//+------------------------------------------------------------------+
bool CEvePriceRiskCalculator::SolveGroupSL(const SEvePosition &grp[], const SEveSymbolSnapshot &s, const double budget,
                                           const int bufferTicks, const bool preserve, SEveSolveResult &res)
  {
   res.status             = EVE_SOLVE_MARKET_DATA_ERROR;
   res.slPrice            = 0.0;
   res.lossAtSL           = 0.0;
   res.closestLegalSL     = 0.0;
   res.lossAtClosestLegal = 0.0;
   res.budget             = budget;

   int n = ArraySize(grp);
   if(n <= 0 || !s.valid || s.tickSize <= 0.0)
      return false;

   ENUM_POSITION_TYPE type = grp[0].type;
   double ts = s.tickSize;
   double minDist = MinStopDistance(s, bufferTicks);
   double loss = 0.0;
   long kBest = 0;

   if(type == POSITION_TYPE_BUY)
     {
      //--- closest legal SL (highest allowed price)
      double maxLegal = s.bid - minDist;
      long kLegal = (long)MathFloor(maxLegal / ts + 1e-9);
      while(kLegal > 0 && (double)kLegal * ts > maxLegal + ts * 1e-6)
         kLegal--;
      if(kLegal < 1)
        {
         res.status = EVE_SOLVE_UNSATISFIABLE;
         return false;
        }
      double pLegal = PriceFromIndex(kLegal, s);
      if(!GroupLossAt(grp, pLegal, preserve, loss))
        {
         res.status = EVE_SOLVE_CALC_ERROR;
         return false;
        }
      res.closestLegalSL = pLegal;
      res.lossAtClosestLegal = loss;
      if(loss > budget + EVE_EPS)
        {
         res.status = EVE_SOLVE_UNSATISFIABLE;
         return false;
        }
      //--- search for the lowest (furthest) k with loss <= budget
      long kLow = 1;
      long kHigh = kLegal;
      double lossLow = 0.0;
      if(!GroupLossAt(grp, PriceFromIndex(kLow, s), preserve, lossLow))
        {
         res.status = EVE_SOLVE_CALC_ERROR;
         return false;
        }
      if(lossLow <= budget + EVE_EPS)
         kBest = kLow;
      else
        {
         // invariant: loss(kLow) > budget, loss(kHigh) <= budget
         while(kHigh - kLow > 1)
           {
            long mid = kLow + (kHigh - kLow) / 2;
            double lm = 0.0;
            if(!GroupLossAt(grp, PriceFromIndex(mid, s), preserve, lm))
              {
               res.status = EVE_SOLVE_CALC_ERROR;
               return false;
              }
            if(lm <= budget + EVE_EPS)
               kHigh = mid;
            else
               kLow = mid;
           }
         kBest = kHigh;
        }
      //--- final verification on the normalized price, stepping toward the market if needed
      double sl = PriceFromIndex(kBest, s);
      if(!GroupLossAt(grp, sl, preserve, loss))
        {
         res.status = EVE_SOLVE_CALC_ERROR;
         return false;
        }
      while(loss > budget + EVE_EPS && kBest < kLegal)
        {
         kBest++;
         sl = PriceFromIndex(kBest, s);
         if(!GroupLossAt(grp, sl, preserve, loss))
           {
            res.status = EVE_SOLVE_CALC_ERROR;
            return false;
           }
        }
      if(loss > budget + EVE_EPS)
        {
         res.status = EVE_SOLVE_UNSATISFIABLE;
         return false;
        }
      res.slPrice = sl;
      res.lossAtSL = loss;
      res.status = EVE_SOLVE_OK;
      return true;
     }

   //--- SELL: closest legal SL (lowest allowed price above Ask)
   double minLegal = s.ask + minDist;
   long kLegalS = (long)MathCeil(minLegal / ts - 1e-9);
   while((double)kLegalS * ts < minLegal - ts * 1e-6)
      kLegalS++;
   if(kLegalS < 1)
      kLegalS = 1;
   double pLegalS = PriceFromIndex(kLegalS, s);
   if(!GroupLossAt(grp, pLegalS, preserve, loss))
     {
      res.status = EVE_SOLVE_CALC_ERROR;
      return false;
     }
   res.closestLegalSL = pLegalS;
   res.lossAtClosestLegal = loss;
   if(loss > budget + EVE_EPS)
     {
      res.status = EVE_SOLVE_UNSATISFIABLE;
      return false;
     }
   //--- expand an upper bound where loss exceeds the budget
   long kLo = kLegalS;
   long kHi = kLegalS;
   long step = (kLegalS > 1) ? kLegalS : 1;
   bool bounded = false;
   double maxPrice = MathMax(s.ask, 1.0) * 10000.0;
   for(int it = 0; it < 64; it++)
     {
      long cand = kHi + step;
      if((double)cand * ts > maxPrice)
         break;
      double lc = 0.0;
      if(!GroupLossAt(grp, PriceFromIndex(cand, s), preserve, lc))
        {
         res.status = EVE_SOLVE_CALC_ERROR;
         return false;
        }
      if(lc > budget + EVE_EPS)
        {
         kHi = cand;
         bounded = true;
         break;
        }
      kLo = cand;
      kHi = cand;
      if(step < 1000000000000)
         step *= 2;
     }
   if(!bounded)
      kBest = kLo;
   else
     {
      // invariant: loss(kLo) <= budget < loss(kHi)
      while(kHi - kLo > 1)
        {
         long midS = kLo + (kHi - kLo) / 2;
         double lms = 0.0;
         if(!GroupLossAt(grp, PriceFromIndex(midS, s), preserve, lms))
           {
            res.status = EVE_SOLVE_CALC_ERROR;
            return false;
           }
         if(lms <= budget + EVE_EPS)
            kLo = midS;
         else
            kHi = midS;
        }
      kBest = kLo;
     }
   double slS = PriceFromIndex(kBest, s);
   if(!GroupLossAt(grp, slS, preserve, loss))
     {
      res.status = EVE_SOLVE_CALC_ERROR;
      return false;
     }
   while(loss > budget + EVE_EPS && kBest > kLegalS)
     {
      kBest--;
      slS = PriceFromIndex(kBest, s);
      if(!GroupLossAt(grp, slS, preserve, loss))
        {
         res.status = EVE_SOLVE_CALC_ERROR;
         return false;
        }
     }
   if(loss > budget + EVE_EPS)
     {
      res.status = EVE_SOLVE_UNSATISFIABLE;
      return false;
     }
   res.slPrice = slS;
   res.lossAtSL = loss;
   res.status = EVE_SOLVE_OK;
   return true;
  }

#endif // EVE_RISK_PRICERISKCALCULATOR_MQH
//+------------------------------------------------------------------+
