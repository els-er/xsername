//+------------------------------------------------------------------+
//|                                                 StateMachine.mqh |
//| Explicit protection state machine (spec 16) with a whitelist of  |
//| legal transitions. LOCKED -> ARMED only through manual reset.    |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_STATEMACHINE_MQH
#define EVE_RISK_STATEMACHINE_MQH

#include "Defines.mqh"
#include "Logger.mqh"

class CEveStateMachine
  {
private:
   ENUM_EVE_STATE    m_state;
   ENUM_EVE_REASON   m_reason;
   datetime          m_triggerTime;
   ulong             m_sinceMs;
   CEveLogger       *m_log;

public:
                     CEveStateMachine(void);
   void              SetLogger(CEveLogger *log) { m_log = log; }
   void              Reset(void);
   ENUM_EVE_STATE    State(void) const       { return m_state;       }
   ENUM_EVE_REASON   Reason(void) const      { return m_reason;      }
   datetime          TriggerTime(void) const { return m_triggerTime; }
   ulong             SinceMs(void) const     { return m_sinceMs;     }
   void              SetReason(const ENUM_EVE_REASON reason, const datetime triggerTime);
   bool              TransitionTo(const ENUM_EVE_STATE next, const string why);
   static bool       IsAllowed(const ENUM_EVE_STATE from, const ENUM_EVE_STATE to);
  };

//+------------------------------------------------------------------+
CEveStateMachine::CEveStateMachine(void) : m_state(EVE_STATE_INIT),
                                           m_reason(EVE_REASON_NONE),
                                           m_triggerTime(0),
                                           m_sinceMs(0),
                                           m_log(NULL)
  {
  }

//+------------------------------------------------------------------+
//| Back to INIT. Used by OnInit: an EA object survives a parameter / |
//| chart change re-initialization, so its state must be reset and   |
//| then restored from persistent storage.                           |
//+------------------------------------------------------------------+
void CEveStateMachine::Reset(void)
  {
   m_state = EVE_STATE_INIT;
   m_reason = EVE_REASON_NONE;
   m_triggerTime = 0;
   m_sinceMs = GetTickCount64();
  }

//+------------------------------------------------------------------+
void CEveStateMachine::SetReason(const ENUM_EVE_REASON reason, const datetime triggerTime)
  {
   m_reason = reason;
   m_triggerTime = triggerTime;
  }

//+------------------------------------------------------------------+
bool CEveStateMachine::IsAllowed(const ENUM_EVE_STATE from, const ENUM_EVE_STATE to)
  {
   if(from == to)
      return true;
   //--- ownership can be lost from any active state (instance guard)
   if(to == EVE_STATE_STANDBY)
      return (from != EVE_STATE_SAFE_DISABLED && from != EVE_STATE_INIT);
   switch(from)
     {
      case EVE_STATE_INIT:
         return (to == EVE_STATE_VALIDATING);
      case EVE_STATE_VALIDATING:
         return (to == EVE_STATE_SAFE_DISABLED || to == EVE_STATE_ARMED ||
                 to == EVE_STATE_LOCKED || to == EVE_STATE_CLOSING_ALL);
      case EVE_STATE_SAFE_DISABLED:
         return false;
      case EVE_STATE_ARMED:
         return (to == EVE_STATE_PROTECTION_TRIGGERED || to == EVE_STATE_SAFE_DISABLED);
      case EVE_STATE_PROTECTION_TRIGGERED:
         return (to == EVE_STATE_CLOSING_ALL);
      case EVE_STATE_CLOSING_ALL:
         return (to == EVE_STATE_CLOSE_FAILED || to == EVE_STATE_ALL_POSITIONS_CLOSED);
      case EVE_STATE_CLOSE_FAILED:
         return (to == EVE_STATE_CLOSING_ALL || to == EVE_STATE_ALL_POSITIONS_CLOSED);
      case EVE_STATE_ALL_POSITIONS_CLOSED:
         return (to == EVE_STATE_LOCKED || to == EVE_STATE_ARMED);
      case EVE_STATE_LOCKED:
         return (to == EVE_STATE_ARMED);   // manual reset only (enforced by the caller)
      case EVE_STATE_STANDBY:
         return (to == EVE_STATE_VALIDATING);
     }
   return false;
  }

//+------------------------------------------------------------------+
bool CEveStateMachine::TransitionTo(const ENUM_EVE_STATE next, const string why)
  {
   if(next == m_state)
      return true;
   if(!IsAllowed(m_state, next))
     {
      if(m_log != NULL)
         m_log.Error("STATE", "ILLEGAL transition " + EveStateName(m_state) + " -> " + EveStateName(next) +
                     " refused (" + why + ")");
      return false;
     }
   if(m_log != NULL)
      m_log.Info("STATE", EveStateName(m_state) + " -> " + EveStateName(next) + " (" + why + ")");
   m_state = next;
   m_sinceMs = GetTickCount64();
   return true;
  }

#endif // EVE_RISK_STATEMACHINE_MQH
//+------------------------------------------------------------------+
