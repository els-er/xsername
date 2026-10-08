//+------------------------------------------------------------------+
//|                                             AccountValidator.mqh |
//|   Account currency validation and trading-permission environment  |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_ACCOUNTVALIDATOR_MQH
#define EVE_RISK_ACCOUNTVALIDATOR_MQH

#include "Defines.mqh"

struct SEveEnvironment
  {
   string            currency;
   int               currencyDigits;
   bool              terminalTradeAllowed;   // AutoTrading / Algo Trading button
   bool              mqlTradeAllowed;        // "Allow Algo Trading" in EA properties
   bool              accountTradeAllowed;    // account allows trading
   bool              accountExpertAllowed;   // account allows EA trading
   bool              connected;
   bool              hedging;
   int               marginMode;
   bool              tester;
  };

class CEveAccountValidator
  {
public:
   static bool       IsCurrencyIDR(const string currency);
   static void       ReadEnvironment(SEveEnvironment &env);
   static bool       CanTrade(const SEveEnvironment &env);
   static string     TradeBlockReason(const SEveEnvironment &env);
   static string     MarginModeName(const int mode);
  };

//+------------------------------------------------------------------+
bool CEveAccountValidator::IsCurrencyIDR(const string currency)
  {
   string c = currency;
   StringTrimLeft(c);
   StringTrimRight(c);
   StringToUpper(c);
   return (c == EVE_RP_REQUIRED_CURRENCY);
  }

//+------------------------------------------------------------------+
void CEveAccountValidator::ReadEnvironment(SEveEnvironment &env)
  {
   env.currency             = AccountInfoString(ACCOUNT_CURRENCY);
   env.currencyDigits       = (int)AccountInfoInteger(ACCOUNT_CURRENCY_DIGITS);
   if(env.currencyDigits < 0 || env.currencyDigits > 8)
      env.currencyDigits = 2;
   env.terminalTradeAllowed = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0);
   env.mqlTradeAllowed      = (MQLInfoInteger(MQL_TRADE_ALLOWED) != 0);
   env.accountTradeAllowed  = (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0);
   env.accountExpertAllowed = (AccountInfoInteger(ACCOUNT_TRADE_EXPERT) != 0);
   env.connected            = (TerminalInfoInteger(TERMINAL_CONNECTED) != 0);
   env.marginMode           = (int)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   env.hedging              = (env.marginMode == (int)ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   env.tester               = (MQLInfoInteger(MQL_TESTER) != 0);
  }

//+------------------------------------------------------------------+
bool CEveAccountValidator::CanTrade(const SEveEnvironment &env)
  {
   return (env.terminalTradeAllowed && env.mqlTradeAllowed &&
           env.accountTradeAllowed && env.accountExpertAllowed && env.connected);
  }

//+------------------------------------------------------------------+
string CEveAccountValidator::TradeBlockReason(const SEveEnvironment &env)
  {
   if(!env.connected)
      return "terminal not connected to trade server";
   if(!env.terminalTradeAllowed)
      return "AutoTrading (Algo Trading) button is OFF";
   if(!env.mqlTradeAllowed)
      return "'Allow Algo Trading' is OFF in EA properties";
   if(!env.accountTradeAllowed)
      return "trading is disabled for this account";
   if(!env.accountExpertAllowed)
      return "EA trading is disabled for this account";
   return "";
  }

//+------------------------------------------------------------------+
string CEveAccountValidator::MarginModeName(const int mode)
  {
   if(mode == (int)ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return "HEDGING";
   if(mode == (int)ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
      return "NETTING";
   if(mode == (int)ACCOUNT_MARGIN_MODE_EXCHANGE)
      return "EXCHANGE";
   return "UNKNOWN(" + IntegerToString(mode) + ")";
  }

#endif // EVE_RISK_ACCOUNTVALIDATOR_MQH
//+------------------------------------------------------------------+
