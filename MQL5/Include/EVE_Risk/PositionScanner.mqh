//+------------------------------------------------------------------+
//|                                              PositionScanner.mqh |
//| Account-wide position scan (spec 15A): iterates the FULL position |
//| pool - every symbol, magic, manual and EA position. Never limited |
//| to _Symbol.                                                       |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_POSITIONSCANNER_MQH
#define EVE_RISK_POSITIONSCANNER_MQH

#include "Defines.mqh"

struct SEvePosition
  {
   ulong              ticket;
   long               identifier;
   string             symbol;
   ENUM_POSITION_TYPE type;
   double             volume;
   double             priceOpen;
   double             sl;
   double             tp;
   double             profit;   // POSITION_PROFIT - the only value used by triggers
   double             swap;     // informational only, NEVER used by triggers
   long               magic;
   long               timeMsc;
  };

class CEvePositionScanner
  {
private:
   SEvePosition      m_list[];
   int               m_count;
   double            m_totalProfit;
   int               m_currencyDigits;
   ENUM_EVE_SCOPE    m_scope;
   ulong             m_prevTickets[];
   ulong             m_newTickets[];
   ulong             m_removedTickets[];
   string            m_signature;
   bool              m_changed;
   bool              m_firstScan;
   bool              m_hasScanned;

   bool              InScope(const SEvePosition &p) const;
   static bool       Contains(const ulong &arr[], const ulong value);

public:
                     CEvePositionScanner(void);
   void              Init(const int currencyDigits, const ENUM_EVE_SCOPE scope);
   int               Scan(void);
   int               Count(void) const        { return m_count;       }
   double            TotalProfit(void) const  { return m_totalProfit; }
   bool              Changed(void) const      { return m_changed;     }
   bool              WasFirstScan(void) const { return m_firstScan;   }
   bool              Get(const int index, SEvePosition &out) const;
   bool              FindByTicket(const ulong ticket, SEvePosition &out) const;
   bool              HasTicket(const ulong ticket) const;
   void              CopyAll(SEvePosition &out[]) const;
   int               NewTicketCount(void) const     { return ArraySize(m_newTickets);     }
   ulong             NewTicket(const int i) const   { return m_newTickets[i];             }
   int               RemovedTicketCount(void) const { return ArraySize(m_removedTickets); }
   ulong             RemovedTicket(const int i) const { return m_removedTickets[i];       }

   // Sum of floating profits, normalized to the account currency digits (audit B-04).
   static double     SumFloating(const double &profits[], const int count, const int digits);
   static int        PendingOrderCount(void);
  };

//+------------------------------------------------------------------+
CEvePositionScanner::CEvePositionScanner(void) : m_count(0),
                                                 m_totalProfit(0.0),
                                                 m_currencyDigits(2),
                                                 m_scope(EVE_SCOPE_ALL_ACCOUNT_POSITIONS),
                                                 m_signature(""),
                                                 m_changed(false),
                                                 m_firstScan(false),
                                                 m_hasScanned(false)
  {
  }

//+------------------------------------------------------------------+
void CEvePositionScanner::Init(const int currencyDigits, const ENUM_EVE_SCOPE scope)
  {
   m_currencyDigits = currencyDigits;
   m_scope = scope;
   m_hasScanned = false;
   m_signature = "";
   ArrayResize(m_prevTickets, 0);
  }

//+------------------------------------------------------------------+
//| Extension point for future scope modes (spec 28). The first       |
//| release implements ALL_ACCOUNT_POSITIONS only.                    |
//+------------------------------------------------------------------+
bool CEvePositionScanner::InScope(const SEvePosition &p) const
  {
   switch(m_scope)
     {
      case EVE_SCOPE_ALL_ACCOUNT_POSITIONS:
         return true;
     }
   return true;
  }

//+------------------------------------------------------------------+
bool CEvePositionScanner::Contains(const ulong &arr[], const ulong value)
  {
   int n = ArraySize(arr);
   for(int i = 0; i < n; i++)
      if(arr[i] == value)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
double CEvePositionScanner::SumFloating(const double &profits[], const int count, const int digits)
  {
   double sum = 0.0;
   for(int i = 0; i < count; i++)
      sum += profits[i];
   return NormalizeDouble(sum, digits);
  }

//+------------------------------------------------------------------+
int CEvePositionScanner::Scan(void)
  {
   int total = PositionsTotal();
   ArrayResize(m_list, total);
   double profits[];
   ArrayResize(profits, total);
   ulong current[];
   ArrayResize(current, total);
   string sig = "";
   m_count = 0;

   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      SEvePosition p;
      p.ticket     = ticket;
      p.identifier = PositionGetInteger(POSITION_IDENTIFIER);
      p.symbol     = PositionGetString(POSITION_SYMBOL);
      p.type       = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      p.volume     = PositionGetDouble(POSITION_VOLUME);
      p.priceOpen  = PositionGetDouble(POSITION_PRICE_OPEN);
      p.sl         = PositionGetDouble(POSITION_SL);
      p.tp         = PositionGetDouble(POSITION_TP);
      p.profit     = PositionGetDouble(POSITION_PROFIT);
      p.swap       = PositionGetDouble(POSITION_SWAP);
      p.magic      = PositionGetInteger(POSITION_MAGIC);
      p.timeMsc    = PositionGetInteger(POSITION_TIME_MSC);
      if(!InScope(p))
         continue;
      m_list[m_count] = p;
      profits[m_count] = p.profit;
      current[m_count] = ticket;
      m_count++;
      sig += IntegerToString((long)ticket) + ":" + DoubleToString(p.volume, 4) + ":" +
             DoubleToString(p.sl, 8) + ":" + DoubleToString(p.tp, 8) + ";";
     }
   ArrayResize(m_list, m_count);
   ArrayResize(current, m_count);
   m_totalProfit = SumFloating(profits, m_count, m_currencyDigits);

   //--- new / removed tickets
   ArrayResize(m_newTickets, 0);
   ArrayResize(m_removedTickets, 0);
   m_firstScan = !m_hasScanned;
   for(int i = 0; i < m_count; i++)
     {
      if(m_firstScan || !Contains(m_prevTickets, current[i]))
        {
         int n = ArraySize(m_newTickets);
         ArrayResize(m_newTickets, n + 1);
         m_newTickets[n] = current[i];
        }
     }
   int prevCount = ArraySize(m_prevTickets);
   for(int i = 0; i < prevCount; i++)
     {
      if(!Contains(current, m_prevTickets[i]))
        {
         int n = ArraySize(m_removedTickets);
         ArrayResize(m_removedTickets, n + 1);
         m_removedTickets[n] = m_prevTickets[i];
        }
     }
   ArrayResize(m_prevTickets, m_count);
   for(int i = 0; i < m_count; i++)
      m_prevTickets[i] = current[i];

   m_changed = (!m_hasScanned || sig != m_signature);
   m_signature = sig;
   m_hasScanned = true;
   return m_count;
  }

//+------------------------------------------------------------------+
bool CEvePositionScanner::Get(const int index, SEvePosition &out) const
  {
   if(index < 0 || index >= m_count)
      return false;
   out = m_list[index];
   return true;
  }

//+------------------------------------------------------------------+
bool CEvePositionScanner::FindByTicket(const ulong ticket, SEvePosition &out) const
  {
   for(int i = 0; i < m_count; i++)
     {
      if(m_list[i].ticket == ticket)
        {
         out = m_list[i];
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
bool CEvePositionScanner::HasTicket(const ulong ticket) const
  {
   for(int i = 0; i < m_count; i++)
      if(m_list[i].ticket == ticket)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
void CEvePositionScanner::CopyAll(SEvePosition &out[]) const
  {
   ArrayResize(out, m_count);
   for(int i = 0; i < m_count; i++)
      out[i] = m_list[i];
  }

//+------------------------------------------------------------------+
int CEvePositionScanner::PendingOrderCount(void)
  {
   int count = 0;
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0)
         continue;
      if(EveIsPendingOrderType((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)))
         count++;
     }
   return count;
  }

#endif // EVE_RISK_POSITIONSCANNER_MQH
//+------------------------------------------------------------------+
