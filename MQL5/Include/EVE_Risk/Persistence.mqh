//+------------------------------------------------------------------+
//|                                                  Persistence.mqh |
//| Persistent protection state (spec 17) in terminal Global          |
//| Variables, keyed by account login + server hash so that switching |
//| accounts never mixes states. GlobalVariablesFlush() after every   |
//| change so a crash / VPS power loss does not lose a LOCK (G-08).   |
//|                                                                  |
//| CEveInstanceGuard: one active protector per account per terminal  |
//| (audit G-09). A second instance runs in STANDBY.                 |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_PERSISTENCE_MQH
#define EVE_RISK_PERSISTENCE_MQH

#include "Defines.mqh"

struct SEvePersistedState
  {
   bool              found;
   int               state;
   int               reason;
   datetime          triggerTime;
   bool              locked;
   double            checksum;
   int               version;
   datetime          savedAt;
  };

class CEvePersistence
  {
private:
   string            m_prefix;
   string            Key(const string k) const { return m_prefix + k; }

public:
                     CEvePersistence(void) : m_prefix("") {}
   void              Init(const long login, const string server);
   string            Prefix(void) const { return m_prefix; }
   bool              Save(const ENUM_EVE_STATE state, const ENUM_EVE_REASON reason, const datetime triggerTime,
                          const bool locked, const double checksum);
   bool              Load(SEvePersistedState &st);
   void              Clear(void);
  };

//+------------------------------------------------------------------+
void CEvePersistence::Init(const long login, const string server)
  {
   m_prefix = "EVERP_" + IntegerToString(login) + "_" + StringFormat("%08X", EveFnv1a(server)) + "_";
  }

//+------------------------------------------------------------------+
bool CEvePersistence::Save(const ENUM_EVE_STATE state, const ENUM_EVE_REASON reason, const datetime triggerTime,
                           const bool locked, const double checksum)
  {
   bool ok = true;
   ResetLastError();
   if(GlobalVariableSet(Key("ST"), (double)state) == 0)
      ok = false;
   if(GlobalVariableSet(Key("RS"), (double)reason) == 0)
      ok = false;
   if(GlobalVariableSet(Key("TT"), (double)triggerTime) == 0)
      ok = false;
   if(GlobalVariableSet(Key("LK"), locked ? 1.0 : 0.0) == 0)
      ok = false;
   if(GlobalVariableSet(Key("CK"), checksum) == 0)
      ok = false;
   if(GlobalVariableSet(Key("VR"), 100.0) == 0)
      ok = false;
   if(GlobalVariableSet(Key("SA"), (double)TimeCurrent()) == 0)
      ok = false;
   GlobalVariablesFlush();
   return ok;
  }

//+------------------------------------------------------------------+
bool CEvePersistence::Load(SEvePersistedState &st)
  {
   st.found       = false;
   st.state       = (int)EVE_STATE_ARMED;
   st.reason      = (int)EVE_REASON_NONE;
   st.triggerTime = 0;
   st.locked      = false;
   st.checksum    = 0.0;
   st.version     = 0;
   st.savedAt     = 0;
   if(!GlobalVariableCheck(Key("ST")))
      return true;
   st.found       = true;
   st.state       = (int)GlobalVariableGet(Key("ST"));
   st.reason      = GlobalVariableCheck(Key("RS")) ? (int)GlobalVariableGet(Key("RS")) : 0;
   st.triggerTime = GlobalVariableCheck(Key("TT")) ? (datetime)(long)GlobalVariableGet(Key("TT")) : 0;
   st.locked      = GlobalVariableCheck(Key("LK")) ? (GlobalVariableGet(Key("LK")) > 0.5) : false;
   st.checksum    = GlobalVariableCheck(Key("CK")) ? GlobalVariableGet(Key("CK")) : 0.0;
   st.version     = GlobalVariableCheck(Key("VR")) ? (int)GlobalVariableGet(Key("VR")) : 0;
   st.savedAt     = GlobalVariableCheck(Key("SA")) ? (datetime)(long)GlobalVariableGet(Key("SA")) : 0;
   if(st.reason < (int)EVE_REASON_NONE || st.reason > (int)EVE_REASON_GLOBAL_FLOATING_PROFIT_TARGET)
      st.reason = (int)EVE_REASON_NONE;
   return true;
  }

//+------------------------------------------------------------------+
void CEvePersistence::Clear(void)
  {
   GlobalVariableDel(Key("ST"));
   GlobalVariableDel(Key("RS"));
   GlobalVariableDel(Key("TT"));
   GlobalVariableDel(Key("LK"));
   GlobalVariableDel(Key("CK"));
   GlobalVariableDel(Key("VR"));
   GlobalVariableDel(Key("SA"));
   GlobalVariablesFlush();
  }

//+------------------------------------------------------------------+
//| CEveInstanceGuard                                                |
//+------------------------------------------------------------------+
class CEveInstanceGuard
  {
private:
   string            m_keyOwner;
   string            m_keyBeat;
   double            m_id;
   bool              m_owner;
   bool              m_enabled;

public:
                     CEveInstanceGuard(void) : m_keyOwner(""), m_keyBeat(""), m_id(0.0), m_owner(false), m_enabled(true) {}
   void              Init(const string prefix, const bool enabled);
   bool              Acquire(void);
   void              Heartbeat(void);
   void              Release(void);
   bool              IsOwner(void) const { return m_owner; }
  };

//+------------------------------------------------------------------+
void CEveInstanceGuard::Init(const string prefix, const bool enabled)
  {
   m_keyOwner = prefix + "MX";
   m_keyBeat  = prefix + "HB";
   m_enabled  = enabled;
   m_owner    = false;
   long cid = ChartID();
   if(cid < 0)
      cid = -cid;
   m_id = (double)((cid % 900000000) + 1);
  }

//+------------------------------------------------------------------+
void CEveInstanceGuard::Heartbeat(void)
  {
   if(!m_enabled || !m_owner)
      return;
   GlobalVariableSet(m_keyBeat, (double)GetTickCount64());
  }

//+------------------------------------------------------------------+
bool CEveInstanceGuard::Acquire(void)
  {
   if(!m_enabled)
     {
      m_owner = true;
      return true;
     }
   if(!GlobalVariableCheck(m_keyOwner))
      GlobalVariableSet(m_keyOwner, 0.0);
   double owner = GlobalVariableGet(m_keyOwner);
   if(owner == m_id)
     {
      m_owner = true;
      Heartbeat();
      return true;
     }
   bool stale = true;
   if(owner != 0.0 && GlobalVariableCheck(m_keyBeat))
     {
      double beat = GlobalVariableGet(m_keyBeat);
      double age = (double)GetTickCount64() - beat;
      stale = (age < 0.0 || age > (double)EVE_HEARTBEAT_STALE_MS);
     }
   if(owner == 0.0 || stale)
     {
      if(GlobalVariableSetOnCondition(m_keyOwner, m_id, owner))
        {
         m_owner = true;
         Heartbeat();
         return true;
        }
     }
   m_owner = false;
   return false;
  }

//+------------------------------------------------------------------+
void CEveInstanceGuard::Release(void)
  {
   if(!m_enabled || !m_owner)
      return;
   if(GlobalVariableCheck(m_keyOwner) && GlobalVariableGet(m_keyOwner) == m_id)
      GlobalVariableSet(m_keyOwner, 0.0);
   m_owner = false;
  }

#endif // EVE_RISK_PERSISTENCE_MQH
//+------------------------------------------------------------------+
