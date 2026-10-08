//+------------------------------------------------------------------+
//|                                                RiskDashboard.mqh |
//| On-chart dashboard (spec 20). All money is shown in Rupiah.       |
//| RESET PROTECTION is a non-blocking two-click button (audit G-07); |
//| it is managed even when the panel itself is hidden.               |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_RISKDASHBOARD_MQH
#define EVE_RISK_RISKDASHBOARD_MQH

#include "Defines.mqh"
#include "IDRFormatter.mqh"
#include "FloatingMonitor.mqh"

#define EVE_DB_PREFIX     "EVERP_DB_"
#define EVE_DB_ROWS       21
#define EVE_DB_WIDTH      410
#define EVE_DB_ROW_H      17
#define EVE_DB_VALUE_X    150
#define EVE_DB_VALUE_LEN  36
#define EVE_DB_WIDE_LEN   58

struct SEveDashboardData
  {
   string            currency;
   double            balance;
   double            equity;
   double            floating;
   int               positions;
   int               pendingOrders;
   bool              lossActive;
   long              lossLimit;
   bool              profitActive;
   long              profitTarget;
   bool              slActive;
   long              slBudget;
   double            slTheoretical;
   int               slProtected;
   int               slUnprotected;
   string            slStatus;
   bool              lockLoss;
   bool              lockProfit;
   bool              cancelPending;
   ENUM_EVE_STATE    state;
   ENUM_EVE_REASON   reason;
   bool              tradeAllowed;
   string            tradeBlock;
   string            marginMode;
   string            lastEvent;
   string            banner;
   color             bannerColor;
   bool              showReset;
  };

class CEveRiskDashboard
  {
private:
   bool              m_enabled;
   bool              m_created;
   bool              m_buttonCreated;
   int               m_x;
   int               m_y;
   string            m_cache[];
   ulong             m_resetArmedUntil;

   string            Name(const string id) const { return EVE_DB_PREFIX + id; }
   void              CreatePanel(void);
   void              CreateButton(void);
   void              CreateLabel(const string id, const int x, const int y, const int size, const color clr, const string font);
   void              SetLabel(const int idx, const string id, const string text, const color clr);
   int               PanelHeight(void) const;

public:
                     CEveRiskDashboard(void);
   void              Init(const bool enabled, const int x, const int y);
   void              Update(const SEveDashboardData &d);
   void              Destroy(void);
   int               HandleClick(const string objectName);   // 0 = not ours, 1 = armed, 2 = confirmed
   bool              ResetArmed(void) const { return (m_resetArmedUntil > GetTickCount64()); }
  };

//+------------------------------------------------------------------+
CEveRiskDashboard::CEveRiskDashboard(void) : m_enabled(true),
                                             m_created(false),
                                             m_buttonCreated(false),
                                             m_x(10),
                                             m_y(25),
                                             m_resetArmedUntil(0)
  {
  }

//+------------------------------------------------------------------+
void CEveRiskDashboard::Init(const bool enabled, const int x, const int y)
  {
   m_enabled = enabled;
   m_x = x;
   m_y = y;
   m_created = false;
   m_buttonCreated = false;
   ArrayResize(m_cache, EVE_DB_ROWS + 10);
   for(int i = 0; i < ArraySize(m_cache); i++)
      m_cache[i] = "";
  }

//+------------------------------------------------------------------+
int CEveRiskDashboard::PanelHeight(void) const
  {
   return 32 + EVE_DB_ROWS * EVE_DB_ROW_H + 3 * EVE_DB_ROW_H + 8;
  }

//+------------------------------------------------------------------+
void CEveRiskDashboard::CreateLabel(const string id, const int x, const int y, const int size, const color clr, const string font)
  {
   string name = Name(id);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, " ");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1);
  }

//+------------------------------------------------------------------+
void CEveRiskDashboard::CreatePanel(void)
  {
   string bg = Name("BG");
   if(ObjectFind(0, bg) >= 0)
      ObjectDelete(0, bg);
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, m_x);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, m_y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, EVE_DB_WIDTH);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, PanelHeight());
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'18,22,30');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'70,80,100');
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bg, OBJPROP_ZORDER, 0);

   CreateLabel("TITLE", m_x + 10, m_y + 8, 10, C'0,190,255', "Segoe UI Semibold");
   for(int i = 0; i < EVE_DB_ROWS; i++)
     {
      int y = m_y + 32 + i * EVE_DB_ROW_H;
      CreateLabel("K" + IntegerToString(i), m_x + 10, y, 9, C'150,160,180', "Consolas");
      CreateLabel("V" + IntegerToString(i), m_x + EVE_DB_VALUE_X, y, 9, clrWhite, "Consolas");
     }
   int yb = m_y + 32 + EVE_DB_ROWS * EVE_DB_ROW_H;
   CreateLabel("B1", m_x + 10, yb, 9, clrOrange, "Consolas");
   CreateLabel("B2", m_x + 10, yb + EVE_DB_ROW_H, 9, clrOrange, "Consolas");
   CreateLabel("NOTE", m_x + 10, yb + 2 * EVE_DB_ROW_H, 8, C'110,120,140', "Consolas");

   string keys[EVE_DB_ROWS] =
     {
      "Account Currency", "Account Balance", "Equity", "Floating P/L", "Floating Loss",
      "Loss Limit", "Loss Remaining", "Profit Auto-Close", "Profit Target", "Profit Progress",
      "Aggregate SL", "SL Risk Budget", "SL Risk @ Stops", "SL Status", "Positions",
      "Pending Orders", "Lock Loss/Profit", "AutoTrading", "Scope", "State", "Last Event"
     };
   for(int i = 0; i < EVE_DB_ROWS; i++)
      ObjectSetString(0, Name("K" + IntegerToString(i)), OBJPROP_TEXT, keys[i]);
   for(int i = 0; i < ArraySize(m_cache); i++)
      m_cache[i] = "";
   m_created = true;
  }

//+------------------------------------------------------------------+
void CEveRiskDashboard::CreateButton(void)
  {
   string btn = Name("RESET");
   if(ObjectFind(0, btn) >= 0)
      ObjectDelete(0, btn);
   int y = m_enabled ? (m_y + PanelHeight() + 4) : m_y;
   ObjectCreate(0, btn, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, btn, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, btn, OBJPROP_XDISTANCE, m_x);
   ObjectSetInteger(0, btn, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, btn, OBJPROP_XSIZE, EVE_DB_WIDTH);
   ObjectSetInteger(0, btn, OBJPROP_YSIZE, 28);
   ObjectSetString(0, btn, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, btn, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, btn, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, btn, OBJPROP_BGCOLOR, C'170,40,40');
   ObjectSetInteger(0, btn, OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetString(0, btn, OBJPROP_TEXT, "RESET PROTECTION");
   ObjectSetInteger(0, btn, OBJPROP_STATE, false);
   ObjectSetInteger(0, btn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, btn, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, btn, OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, btn, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   m_cache[EVE_DB_ROWS + 5] = "";
   m_buttonCreated = true;
  }

//+------------------------------------------------------------------+
void CEveRiskDashboard::SetLabel(const int idx, const string id, const string text, const color clr)
  {
   string key = text + "|" + IntegerToString((long)clr);
   if(m_cache[idx] == key)
      return;
   m_cache[idx] = key;
   string name = Name(id);
   ObjectSetString(0, name, OBJPROP_TEXT, (text == "") ? " " : text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
void CEveRiskDashboard::Update(const SEveDashboardData &d)
  {
   //--- reset button (always managed, even without the panel)
   if(!m_buttonCreated || ObjectFind(0, Name("RESET")) < 0)
      CreateButton();
   string btnText = ResetArmed() ? "CLICK AGAIN TO CONFIRM RESET (10 s)" : "RESET PROTECTION";
   string btnKey = (d.showReset ? "1" : "0") + btnText;
   if(m_cache[EVE_DB_ROWS + 5] != btnKey)
     {
      m_cache[EVE_DB_ROWS + 5] = btnKey;
      string btn = Name("RESET");
      ObjectSetInteger(0, btn, OBJPROP_TIMEFRAMES, d.showReset ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
      ObjectSetString(0, btn, OBJPROP_TEXT, btnText);
      ObjectSetInteger(0, btn, OBJPROP_BGCOLOR, ResetArmed() ? C'200,120,0' : C'170,40,40');
     }

   if(!m_enabled)
     {
      ChartRedraw(0);
      return;
     }
   if(!m_created || ObjectFind(0, Name("BG")) < 0)
      CreatePanel();

   color cText = clrWhite;
   color cPos  = C'60,220,120';
   color cNeg  = C'255,90,90';
   color cWarn = clrOrange;
   color cDim  = C'120,130,150';

   SetLabel(EVE_DB_ROWS + 0, "TITLE", EVE_RP_NAME + "  v" + EVE_RP_VERSION, C'0,190,255');

   double fl = d.floating;
   double floatingLoss = CEveFloatingMonitor::FloatingLoss(fl);
   double floatingProfit = CEveFloatingMonitor::FloatingProfit(fl);

   SetLabel(0, "V0", d.currency, (d.currency == EVE_RP_REQUIRED_CURRENCY) ? cText : cNeg);
   SetLabel(1, "V1", EveFormatIDR(d.balance), cText);
   SetLabel(2, "V2", EveFormatIDR(d.equity), cText);
   SetLabel(3, "V3", EveFormatIDRSigned(fl), (fl < 0.0) ? cNeg : ((fl > 0.0) ? cPos : cText));
   SetLabel(4, "V4", EveFormatIDR(floatingLoss), (floatingLoss > 0.0) ? cNeg : cText);

   if(d.lossActive)
     {
      double remaining = CEveFloatingMonitor::LossRemaining(fl, d.lossLimit);
      double ratio = (d.lossLimit > 0) ? remaining / (double)d.lossLimit : 1.0;
      SetLabel(5, "V5", EveFormatIDRLong(d.lossLimit), cText);
      SetLabel(6, "V6", EveFormatIDR(remaining), (ratio < 0.2) ? cNeg : ((ratio < 0.5) ? cWarn : cPos));
     }
   else
     {
      SetLabel(5, "V5", "OFF", cWarn);
      SetLabel(6, "V6", "-", cDim);
     }

   if(d.profitActive)
     {
      SetLabel(7, "V7", "ON", cPos);
      SetLabel(8, "V8", EveFormatIDRLong(d.profitTarget), cText);
      double pct = CEveFloatingMonitor::ProfitProgressPct(fl, d.profitTarget);
      SetLabel(9, "V9", EveFormatIDR(floatingProfit) + " (" + DoubleToString(pct, 1) + "%)", (floatingProfit > 0.0) ? cPos : cText);
     }
   else
     {
      SetLabel(7, "V7", "OFF", cDim);
      SetLabel(8, "V8", "-", cDim);
      SetLabel(9, "V9", "-", cDim);
     }

   if(d.slActive)
     {
      SetLabel(10, "V10", "ON", cPos);
      SetLabel(11, "V11", EveFormatIDRLong(d.slBudget), cText);
      SetLabel(12, "V12", EveTruncate(EveFormatIDR(d.slTheoretical) + " (" + IntegerToString(d.slProtected) + " ok/" +
                                      IntegerToString(d.slUnprotected) + " unprot)", EVE_DB_VALUE_LEN),
               (d.slUnprotected > 0) ? cWarn : cText);
      bool slBad = (StringFind(d.slStatus, "UNPROTECTED") >= 0 || StringFind(d.slStatus, "FAIL") >= 0 ||
                    StringFind(d.slStatus, "ERROR") >= 0 || StringFind(d.slStatus, "VIOLATION") >= 0);
      SetLabel(13, "V13", EveTruncate(d.slStatus, EVE_DB_VALUE_LEN), slBad ? cNeg : ((d.slStatus == "COMPLIANT") ? cPos : cWarn));
     }
   else
     {
      SetLabel(10, "V10", "OFF", cWarn);
      SetLabel(11, "V11", "-", cDim);
      SetLabel(12, "V12", "-", cDim);
      SetLabel(13, "V13", "-", cDim);
     }

   SetLabel(14, "V14", IntegerToString(d.positions) + " (all symbols)", cText);
   string pend = IntegerToString(d.pendingOrders);
   if(!d.lockLoss && !d.lockProfit)
      pend += " (lock OFF: never cancelled)";
   else
      if(!d.cancelPending)
         pend += " (NOT cancelled on lock!)";
   SetLabel(15, "V15", EveTruncate(pend, EVE_DB_VALUE_LEN), (d.cancelPending || (!d.lockLoss && !d.lockProfit)) ? cText : cWarn);
   SetLabel(16, "V16", "Loss " + EveBoolOnOff(d.lockLoss) + " / Profit " + EveBoolOnOff(d.lockProfit), cText);
   SetLabel(17, "V17", EveTruncate(d.tradeAllowed ? "OK (" + d.marginMode + ")" : "OFF - " + d.tradeBlock, EVE_DB_VALUE_LEN),
            d.tradeAllowed ? cPos : cNeg);
   SetLabel(18, "V18", "ALL ACCOUNT POSITIONS", cText);

   string st = EveStateDashboardLabel(d.state);
   if(d.reason != EVE_REASON_NONE && (EveIsClosingState(d.state) || d.state == EVE_STATE_LOCKED))
      st += (d.reason == EVE_REASON_GLOBAL_FLOATING_LOSS) ? " (LOSS)" : " (PROFIT)";
   color stColor = cText;
   if(d.state == EVE_STATE_ARMED)
      stColor = cPos;
   else
      if(EveIsClosingState(d.state) || d.state == EVE_STATE_SAFE_DISABLED)
         stColor = cNeg;
      else
         if(d.state == EVE_STATE_LOCKED || d.state == EVE_STATE_STANDBY)
            stColor = cWarn;
   SetLabel(19, "V19", EveTruncate(st, EVE_DB_VALUE_LEN), stColor);
   SetLabel(20, "V20", EveTruncate(d.lastEvent, EVE_DB_VALUE_LEN), cDim);

   //--- banner (two lines)
   string b1 = "";
   string b2 = "";
   if(StringLen(d.banner) <= EVE_DB_WIDE_LEN)
      b1 = d.banner;
   else
     {
      b1 = StringSubstr(d.banner, 0, EVE_DB_WIDE_LEN);
      b2 = EveTruncate(StringSubstr(d.banner, EVE_DB_WIDE_LEN), EVE_DB_WIDE_LEN);
     }
   SetLabel(EVE_DB_ROWS + 1, "B1", b1, d.bannerColor);
   SetLabel(EVE_DB_ROWS + 2, "B2", b2, d.bannerColor);
   SetLabel(EVE_DB_ROWS + 3, "NOTE", "P/L = POSITION_PROFIT only (no swap, no commission)", cDim);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
void CEveRiskDashboard::Destroy(void)
  {
   ObjectsDeleteAll(0, EVE_DB_PREFIX);
   m_created = false;
   m_buttonCreated = false;
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
int CEveRiskDashboard::HandleClick(const string objectName)
  {
   if(objectName != Name("RESET"))
      return 0;
   ObjectSetInteger(0, objectName, OBJPROP_STATE, false);
   ulong now = GetTickCount64();
   if(m_resetArmedUntil > now)
     {
      m_resetArmedUntil = 0;
      return 2;
     }
   m_resetArmedUntil = now + 10000;
   return 1;
  }

#endif // EVE_RISK_RISKDASHBOARD_MQH
//+------------------------------------------------------------------+
