//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//|     Leveled logging (journal + daily file) and push notifications |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_LOGGER_MQH
#define EVE_RISK_LOGGER_MQH

#include "Defines.mqh"

//+------------------------------------------------------------------+
//| CEveLogger                                                       |
//| Every line carries local time, server time, level and category.  |
//| The Experts journal adds its own millisecond timestamp as well.  |
//+------------------------------------------------------------------+
class CEveLogger
  {
private:
   bool              m_fileEnabled;
   long              m_login;
   bool              m_fileErrorReported;
   string            m_lastMessage;
   string            m_lastCritical;
   datetime          m_lastCriticalTime;

   string            CurrentFileName(void) const;
   void              WriteFile(const string line);

public:
                     CEveLogger(void);
   void              Init(const bool fileEnabled, const long login);
   void              Log(const ENUM_EVE_LOG_LEVEL level, const string category, const string message);
   void              Info(const string category, const string message)     { Log(EVE_LOG_INFO, category, message);     }
   void              Warning(const string category, const string message)  { Log(EVE_LOG_WARNING, category, message);  }
   void              Error(const string category, const string message)    { Log(EVE_LOG_ERROR, category, message);    }
   void              Critical(const string category, const string message) { Log(EVE_LOG_CRITICAL, category, message); }
   string            LastMessage(void) const      { return m_lastMessage;      }
   string            LastCritical(void) const     { return m_lastCritical;     }
   datetime          LastCriticalTime(void) const { return m_lastCriticalTime; }
  };

//+------------------------------------------------------------------+
CEveLogger::CEveLogger(void) : m_fileEnabled(false),
                               m_login(0),
                               m_fileErrorReported(false),
                               m_lastMessage(""),
                               m_lastCritical(""),
                               m_lastCriticalTime(0)
  {
  }

//+------------------------------------------------------------------+
void CEveLogger::Init(const bool fileEnabled, const long login)
  {
   m_fileEnabled = fileEnabled;
   m_login = login;
   m_fileErrorReported = false;
  }

//+------------------------------------------------------------------+
string CEveLogger::CurrentFileName(void) const
  {
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   return StringFormat("EVE_RiskProtector_%s_%04d%02d%02d.log",
                       IntegerToString(m_login), dt.year, dt.mon, dt.day);
  }

//+------------------------------------------------------------------+
void CEveLogger::WriteFile(const string line)
  {
   if(!m_fileEnabled)
      return;
   string name = CurrentFileName();
   int h = FileOpen(name, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
     {
      if(!m_fileErrorReported)
        {
         Print("EVE-RP | WARNING | LOG | cannot open log file ", name, " (error ", GetLastError(), "); journal logging continues");
         m_fileErrorReported = true;
        }
      return;
     }
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, line + "\r\n");
   FileClose(h);
  }

//+------------------------------------------------------------------+
void CEveLogger::Log(const ENUM_EVE_LOG_LEVEL level, const string category, const string message)
  {
   string body = EveLevelName(level) + " | " + category + " | " + message;
   Print("EVE-RP | ", body);
   string line = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS) +
                 " | srv " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) +
                 " | " + body;
   WriteFile(line);
   m_lastMessage = category + ": " + message;
   if(level == EVE_LOG_CRITICAL)
     {
      m_lastCritical = message;
      m_lastCriticalTime = TimeCurrent();
     }
  }

//+------------------------------------------------------------------+
//| CEveNotifier                                                     |
//| Alert() for critical events and MT5 push notifications.          |
//| Push is rate limited: MT5 allows at most 10 per minute.          |
//+------------------------------------------------------------------+
class CEveNotifier
  {
private:
   bool              m_pushEnabled;
   bool              m_alertEnabled;
   bool              m_tester;
   string            m_queue[];
   ulong             m_lastSendMs;
   bool              m_pushErrorReported;

public:
                     CEveNotifier(void);
   void              Init(const bool pushEnabled, const bool alertEnabled);
   void              Notify(const string text, const bool alsoAlert);
   void              Flush(void);
  };

//+------------------------------------------------------------------+
CEveNotifier::CEveNotifier(void) : m_pushEnabled(false),
                                   m_alertEnabled(false),
                                   m_tester(false),
                                   m_lastSendMs(0),
                                   m_pushErrorReported(false)
  {
  }

//+------------------------------------------------------------------+
void CEveNotifier::Init(const bool pushEnabled, const bool alertEnabled)
  {
   m_pushEnabled = pushEnabled;
   m_alertEnabled = alertEnabled;
   m_tester = (MQLInfoInteger(MQL_TESTER) != 0);
   ArrayResize(m_queue, 0);
   m_lastSendMs = 0;
  }

//+------------------------------------------------------------------+
void CEveNotifier::Notify(const string text, const bool alsoAlert)
  {
   if(m_tester)
      return;
   if(alsoAlert && m_alertEnabled)
      Alert(EVE_RP_NAME, ": ", text);
   if(!m_pushEnabled)
      return;
   int n = ArraySize(m_queue);
   if(n >= 10)
     {
      // drop the oldest message; the newest state matters most
      for(int i = 1; i < n; i++)
         m_queue[i - 1] = m_queue[i];
      n--;
      ArrayResize(m_queue, n);
     }
   ArrayResize(m_queue, n + 1);
   m_queue[n] = text;
  }

//+------------------------------------------------------------------+
void CEveNotifier::Flush(void)
  {
   if(m_tester || !m_pushEnabled)
      return;
   int n = ArraySize(m_queue);
   if(n == 0)
      return;
   ulong now = GetTickCount64();
   if(m_lastSendMs != 0 && now - m_lastSendMs < 6500)
      return;
   string msg = EveTruncate("EVE-RP " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ": " + m_queue[0], 255);
   ResetLastError();
   if(!SendNotification(msg))
     {
      if(!m_pushErrorReported)
        {
         Print("EVE-RP | WARNING | PUSH | SendNotification failed (error ", GetLastError(),
               "). Check Tools > Options > Notifications (MetaQuotes ID). Alerts and logs continue.");
         m_pushErrorReported = true;
        }
     }
   m_lastSendMs = now;
   for(int i = 1; i < n; i++)
      m_queue[i - 1] = m_queue[i];
   ArrayResize(m_queue, n - 1);
  }

#endif // EVE_RISK_LOGGER_MQH
//+------------------------------------------------------------------+
