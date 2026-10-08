//+------------------------------------------------------------------+
//|                                                RiskDashboard.mqh |
//| Chart panel drawn on one bitmap (CCanvas), plain simple English.  |
//| - DPI aware: fonts in tenths of a point (scaled by Windows) and   |
//|   all spacing scaled by TERMINAL_SCREEN_DPI / 96                  |
//| - layout from MEASURED text: labels left, values right-aligned,  |
//|   the panel widens to fit, so text never overlaps                 |
//| - sections, progress bars, state badge, minimize button, corner  |
//|   placement, drawn two-click RESET button (audit G-07)            |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_RISKDASHBOARD_MQH
#define EVE_RISK_RISKDASHBOARD_MQH

#include <Canvas\Canvas.mqh>
#include "Defines.mqh"
#include "IDRFormatter.mqh"
#include "FloatingMonitor.mqh"

#define EVE_DB_OBJ          "EVERP_PANEL"
#define EVE_DB_FONT         "Segoe UI"

#define EVE_ROW_SECTION     0
#define EVE_ROW_KV          1
#define EVE_ROW_BIG         2
#define EVE_ROW_BAR         3
#define EVE_ROW_TEXT        4
#define EVE_ROW_NOTE        5

//--- palette
#define EVE_C_BG            C'16,20,27'
#define EVE_C_HEADER        C'24,30,40'
#define EVE_C_BORDER        C'48,58,74'
#define EVE_C_SECTION       C'96,165,250'
#define EVE_C_LINE          C'40,48,62'
#define EVE_C_LABEL         C'148,158,174'
#define EVE_C_VALUE         C'232,236,242'
#define EVE_C_DIM           C'108,118,134'
#define EVE_C_GREEN         C'46,204,113'
#define EVE_C_RED           C'239,83,80'
#define EVE_C_ORANGE        C'255,167,38'
#define EVE_C_BAR_BG        C'38,46,58'

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
   bool              trailActive;
   long              trailStart;
   int               trailGroups;
   double            lockedProfit;
   bool              tpActive;
   long              tpTarget;
   int               tpGroups;
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

struct SEveDbRow
  {
   int               kind;
   string            key;
   string            value;
   color             keyColor;
   color             valueColor;
   double            ratio;
  };

class CEveRiskDashboard
  {
private:
   CCanvas           m_canvas;
   bool              m_enabled;
   bool              m_created;
   bool              m_minimized;
   int               m_corner;
   int               m_offX;
   int               m_offY;
   int               m_posX;
   int               m_posY;
   int               m_w;
   int               m_h;
   double            m_scale;
   ulong             m_resetArmedUntil;
   int               m_minX1, m_minY1, m_minX2, m_minY2;
   int               m_rstX1, m_rstY1, m_rstX2, m_rstY2;
   bool              m_resetVisible;
   SEveDbRow         m_rows[];
   string            m_title;
   string            m_badge;
   color             m_badgeColor;

   int               S(const double v) const { return (int)MathRound(v * m_scale); }
   uint              ARGB(const color c) const { return ColorToARGB(c, 255); }
   static color      Mix(const color a, const color b, const double t);
   void              FontLabel(void)   { m_canvas.FontSet(EVE_DB_FONT, -90, FW_NORMAL);   }
   void              FontValue(void)   { m_canvas.FontSet(EVE_DB_FONT, -90, FW_SEMIBOLD); }
   void              FontTitle(void)   { m_canvas.FontSet(EVE_DB_FONT, -100, FW_BOLD);    }
   void              FontSection(void) { m_canvas.FontSet(EVE_DB_FONT, -75, FW_BOLD);     }
   void              FontBig(void)     { m_canvas.FontSet(EVE_DB_FONT, -140, FW_BOLD);    }
   void              FontSmall(void)   { m_canvas.FontSet(EVE_DB_FONT, -75, FW_NORMAL);   }
   void              AddRow(const int kind, const string key, const string value,
                            const color keyColor, const color valueColor, const double ratio);
   void              BuildRows(const SEveDashboardData &d);
   int               Render(const bool drawIt, const int width, int &neededWidth);
   bool              EnsureCanvas(const int w, const int h);
   void              Place(void);
   string            Fit(const string text, const int maxWidth);
   int               Wrap(const string text, const int maxWidth, string &lines[]);
   static string     SLStatusLabel(const string status, color &clr);

public:
                     CEveRiskDashboard(void);
   void              Init(const bool enabled, const int corner, const int x, const int y);
   void              Update(const SEveDashboardData &d);
   void              Destroy(void);
   void              OnChartChange(void) { if(m_created) Place(); }
   int               HandleClick(const string objectName, const int x, const int y);   // 0 none, 1 reset armed, 2 reset confirmed, 3 minimize toggled
   bool              ResetArmed(void) const { return (m_resetArmedUntil > GetTickCount64()); }
  };

//+------------------------------------------------------------------+
CEveRiskDashboard::CEveRiskDashboard(void) : m_enabled(true),
                                             m_created(false),
                                             m_minimized(false),
                                             m_corner(0),
                                             m_offX(10),
                                             m_offY(30),
                                             m_posX(0),
                                             m_posY(0),
                                             m_w(0),
                                             m_h(0),
                                             m_scale(1.0),
                                             m_resetArmedUntil(0),
                                             m_minX1(0), m_minY1(0), m_minX2(0), m_minY2(0),
                                             m_rstX1(0), m_rstY1(0), m_rstX2(0), m_rstY2(0),
                                             m_resetVisible(false),
                                             m_title(""),
                                             m_badge(""),
                                             m_badgeColor(clrGray)
  {
  }

//+------------------------------------------------------------------+
void CEveRiskDashboard::Init(const bool enabled, const int corner, const int x, const int y)
  {
   m_enabled = enabled;
   m_corner = corner;
   m_offX = x;
   m_offY = y;
   double dpi = (double)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   m_scale = (dpi > 0.0) ? dpi / 96.0 : 1.0;
   if(m_scale < 1.0)
      m_scale = 1.0;
   if(m_scale > 3.0)
      m_scale = 3.0;
   ObjectsDeleteAll(0, "EVERP_DB_");   // leftovers of the v1.00 label dashboard
  }

//+------------------------------------------------------------------+
color CEveRiskDashboard::Mix(const color a, const color b, const double t)
  {
   uint ua = (uint)a;
   uint ub = (uint)b;
   int ar = (int)(ua & 0xFF);
   int ag = (int)((ua >> 8) & 0xFF);
   int ab = (int)((ua >> 16) & 0xFF);
   int br = (int)(ub & 0xFF);
   int bg = (int)((ub >> 8) & 0xFF);
   int bb = (int)((ub >> 16) & 0xFF);
   int r = (int)MathRound(ar + (br - ar) * t);
   int g = (int)MathRound(ag + (bg - ag) * t);
   int bl = (int)MathRound(ab + (bb - ab) * t);
   return (color)(r | (g << 8) | (bl << 16));
  }

//+------------------------------------------------------------------+
string CEveRiskDashboard::SLStatusLabel(const string status, color &clr)
  {
   clr = EVE_C_ORANGE;
   if(status == "COMPLIANT")
     {
      clr = EVE_C_GREEN;
      return "SAFE";
     }
   if(status == "NO POSITIONS")
     {
      clr = EVE_C_DIM;
      return "NO POSITIONS";
     }
   if(StringFind(status, "UNPROTECTED") >= 0)
     {
      clr = EVE_C_RED;
      return "NOT PROTECTED";
     }
   if(StringFind(status, "FAIL-SAFE") >= 0)
     {
      clr = EVE_C_RED;
      return "FORCED CLOSE";
     }
   if(StringFind(status, "CALC") >= 0)
     {
      clr = EVE_C_RED;
      return "CALC ERROR";
     }
   if(StringFind(status, "ADVISORY") >= 0)
      return "WARNING ONLY";
   if(StringFind(status, "ADJUSTING") >= 0)
      return "ADJUSTING";
   if(StringFind(status, "STARTING") >= 0)
      return "STARTING";
   return "WAITING";
  }

//+------------------------------------------------------------------+
void CEveRiskDashboard::AddRow(const int kind, const string key, const string value,
                               const color keyColor, const color valueColor, const double ratio)
  {
   int n = ArraySize(m_rows);
   ArrayResize(m_rows, n + 1);
   m_rows[n].kind = kind;
   m_rows[n].key = key;
   m_rows[n].value = value;
   m_rows[n].keyColor = keyColor;
   m_rows[n].valueColor = valueColor;
   m_rows[n].ratio = ratio;
  }

//+------------------------------------------------------------------+
//| Content of the panel                                             |
//+------------------------------------------------------------------+
void CEveRiskDashboard::BuildRows(const SEveDashboardData &d)
  {
   ArrayResize(m_rows, 0);
   m_title = "EVE RISK PROTECTOR";
   m_badge = EveStateLabel(d.state);
   m_badgeColor = EVE_C_DIM;
   if(d.state == EVE_STATE_ARMED)
      m_badgeColor = EVE_C_GREEN;
   else
      if(EveIsClosingState(d.state) || d.state == EVE_STATE_SAFE_DISABLED || d.state == EVE_STATE_ALL_POSITIONS_CLOSED)
         m_badgeColor = EVE_C_RED;
      else
         if(d.state == EVE_STATE_LOCKED || d.state == EVE_STATE_STANDBY)
            m_badgeColor = EVE_C_ORANGE;

   if(!m_enabled)
     {
      //--- panel hidden by the user: only what is needed to reset a lock
      if(d.banner != "")
         AddRow(EVE_ROW_TEXT, d.banner, "", d.bannerColor, d.bannerColor, 0.0);
      return;
     }

   double fl = d.floating;
   double flLoss = CEveFloatingMonitor::FloatingLoss(fl);
   double flProfit = CEveFloatingMonitor::FloatingProfit(fl);

   //--- account
   AddRow(EVE_ROW_SECTION, "ACCOUNT", "", EVE_C_SECTION, EVE_C_SECTION, 0.0);
   AddRow(EVE_ROW_KV, "Currency", d.currency, EVE_C_LABEL,
          (d.currency == EVE_RP_REQUIRED_CURRENCY) ? EVE_C_VALUE : EVE_C_RED, 0.0);
   AddRow(EVE_ROW_KV, "Balance", EveFormatIDR(d.balance), EVE_C_LABEL, EVE_C_VALUE, 0.0);
   AddRow(EVE_ROW_KV, "Equity", EveFormatIDR(d.equity), EVE_C_LABEL, EVE_C_VALUE, 0.0);
   AddRow(EVE_ROW_BIG, "Floating", EveFormatIDRSigned(fl), EVE_C_LABEL,
          (fl < 0.0) ? EVE_C_RED : ((fl > 0.0) ? EVE_C_GREEN : EVE_C_VALUE), 0.0);
   AddRow(EVE_ROW_KV, "Positions", IntegerToString(d.positions) + " open  |  " + IntegerToString(d.pendingOrders) + " pending",
          EVE_C_LABEL, EVE_C_VALUE, 0.0);

   //--- protections
   AddRow(EVE_ROW_SECTION, "PROTECTION", "", EVE_C_SECTION, EVE_C_SECTION, 0.0);
   if(d.lossActive && d.lossLimit > 0)
     {
      double r = flLoss / (double)d.lossLimit;
      color c = (r >= 0.8) ? EVE_C_RED : ((r >= 0.5) ? EVE_C_ORANGE : EVE_C_GREEN);
      AddRow(EVE_ROW_KV, "Max total loss", EveFormatIDR(flLoss) + " / " + EveFormatIDRLong(d.lossLimit), EVE_C_LABEL, EVE_C_VALUE, 0.0);
      AddRow(EVE_ROW_BAR, "", "", c, c, r);
     }
   else
      AddRow(EVE_ROW_KV, "Max total loss", "OFF", EVE_C_LABEL, EVE_C_DIM, 0.0);

   if(d.profitActive && d.profitTarget > 0)
     {
      double r2 = flProfit / (double)d.profitTarget;
      AddRow(EVE_ROW_KV, "Profit target", EveFormatIDR(flProfit) + " / " + EveFormatIDRLong(d.profitTarget), EVE_C_LABEL, EVE_C_VALUE, 0.0);
      AddRow(EVE_ROW_BAR, "", "", EVE_C_GREEN, EVE_C_GREEN, r2);
     }
   else
      AddRow(EVE_ROW_KV, "Profit target", "OFF", EVE_C_LABEL, EVE_C_DIM, 0.0);

   if(d.slActive && d.slBudget > 0)
     {
      color sc = EVE_C_ORANGE;
      string st = SLStatusLabel(d.slStatus, sc);
      double r3 = d.slTheoretical / (double)d.slBudget;
      AddRow(EVE_ROW_KV, "Auto SL (loss if hit)", EveFormatIDR(d.slTheoretical) + " / " + EveFormatIDRLong(d.slBudget),
             EVE_C_LABEL, EVE_C_VALUE, 0.0);
      AddRow(EVE_ROW_BAR, "", "", sc, sc, r3);
      AddRow(EVE_ROW_KV, "SL status", st + ((d.slUnprotected > 0) ? "  (" + IntegerToString(d.slUnprotected) + " without SL)" : ""),
             EVE_C_LABEL, sc, 0.0);
     }
   else
      AddRow(EVE_ROW_KV, "Auto SL", "OFF", EVE_C_LABEL, EVE_C_DIM, 0.0);

   if(d.trailActive)
      AddRow(EVE_ROW_KV, "Trailing stop",
             (d.trailGroups > 0) ? "ON - running on " + IntegerToString(d.trailGroups) + " basket(s)"
                                 : "ON - starts at profit " + EveFormatIDRLong(d.trailStart),
             EVE_C_LABEL, (d.trailGroups > 0) ? EVE_C_GREEN : EVE_C_VALUE, 0.0);
   else
      AddRow(EVE_ROW_KV, "Trailing stop", "OFF", EVE_C_LABEL, EVE_C_DIM, 0.0);
   if(d.lockedProfit > 0.0)
      AddRow(EVE_ROW_KV, "Profit locked by SL", EveFormatIDR(d.lockedProfit), EVE_C_LABEL, EVE_C_GREEN, 0.0);
   if(d.tpActive)
      AddRow(EVE_ROW_KV, "Basket TP", EveFormatIDRLong(d.tpTarget) + " per basket", EVE_C_LABEL, EVE_C_VALUE, 0.0);
   else
      AddRow(EVE_ROW_KV, "Basket TP", "OFF", EVE_C_LABEL, EVE_C_DIM, 0.0);

   //--- system
   AddRow(EVE_ROW_SECTION, "SYSTEM", "", EVE_C_SECTION, EVE_C_SECTION, 0.0);
   AddRow(EVE_ROW_KV, "Auto Trading", d.tradeAllowed ? "OK (" + d.marginMode + ")" : "OFF - " + d.tradeBlock,
          EVE_C_LABEL, d.tradeAllowed ? EVE_C_GREEN : EVE_C_RED, 0.0);
   AddRow(EVE_ROW_KV, "Lock after close", "Loss " + EveBoolOnOff(d.lockLoss) + "  |  Profit " + EveBoolOnOff(d.lockProfit),
          EVE_C_LABEL, EVE_C_VALUE, 0.0);
   if((d.lockLoss || d.lockProfit) && !d.cancelPending)
      AddRow(EVE_ROW_KV, "Pending when locked", "NOT deleted", EVE_C_LABEL, EVE_C_ORANGE, 0.0);
   AddRow(EVE_ROW_KV, "Last event", (d.lastEvent != "") ? d.lastEvent : "-", EVE_C_LABEL, EVE_C_DIM, 0.0);
   if(d.banner != "")
      AddRow(EVE_ROW_TEXT, d.banner, "", d.bannerColor, d.bannerColor, 0.0);
   AddRow(EVE_ROW_NOTE, "Floating = POSITION_PROFIT (no swap, no commission). Covers all positions in the account.", "",
          EVE_C_DIM, EVE_C_DIM, 0.0);
  }

//+------------------------------------------------------------------+
//| Truncate with "..." so that the text fits (current font)         |
//+------------------------------------------------------------------+
string CEveRiskDashboard::Fit(const string text, const int maxWidth)
  {
   if(maxWidth <= 0)
      return "";
   if(m_canvas.TextWidth(text) <= maxWidth)
      return text;
   string t = text;
   while(StringLen(t) > 1)
     {
      t = StringSubstr(t, 0, StringLen(t) - 1);
      if(m_canvas.TextWidth(t + "...") <= maxWidth)
         return t + "...";
     }
   return "...";
  }

//+------------------------------------------------------------------+
//| Word wrap (current font). Returns the number of lines.           |
//+------------------------------------------------------------------+
int CEveRiskDashboard::Wrap(const string text, const int maxWidth, string &lines[])
  {
   ArrayResize(lines, 0);
   string words[];
   int nw = StringSplit(text, ' ', words);
   string line = "";
   for(int i = 0; i < nw; i++)
     {
      if(words[i] == "")
         continue;
      string candidate = (line == "") ? words[i] : line + " " + words[i];
      if(m_canvas.TextWidth(candidate) <= maxWidth)
        {
         line = candidate;
         continue;
        }
      if(line != "")
        {
         int n = ArraySize(lines);
         ArrayResize(lines, n + 1);
         lines[n] = line;
        }
      line = Fit(words[i], maxWidth);
     }
   if(line != "")
     {
      int n2 = ArraySize(lines);
      ArrayResize(lines, n2 + 1);
      lines[n2] = line;
     }
   return ArraySize(lines);
  }

//+------------------------------------------------------------------+
//| Measures (drawIt = false) or draws (drawIt = true) the panel.    |
//| Returns the panel height; neededWidth = width the content needs. |
//+------------------------------------------------------------------+
int CEveRiskDashboard::Render(const bool drawIt, const int width, int &neededWidth)
  {
   int padX = S(12);
   int gap = S(18);
   int headerH = S(32);
   int maxW = S(470);
   neededWidth = S(300);

   //--- header: title + badge + minimize button
   FontTitle();
   int titleW = m_canvas.TextWidth(m_title);
   FontSmall();
   int verW = m_canvas.TextWidth("v" + EVE_RP_VERSION);
   FontSection();
   int badgeTextW = m_canvas.TextWidth(m_badge);
   int badgeW = badgeTextW + S(16);
   int badgeH = S(18);
   int btnW = S(20);
   int headerNeed = padX + titleW + S(6) + verW + S(10) + badgeW + S(8) + btnW + padX;
   if(headerNeed > neededWidth)
      neededWidth = headerNeed;

   if(drawIt)
     {
      m_canvas.Erase(ARGB(EVE_C_BG));
      m_canvas.FillRectangle(0, 0, width - 1, headerH, ARGB(EVE_C_HEADER));
      FontTitle();
      m_canvas.TextOut(padX, headerH / 2, m_title, ARGB(EVE_C_VALUE), TA_LEFT | TA_VCENTER);
      FontSmall();
      m_canvas.TextOut(padX + titleW + S(6), headerH / 2, "v" + EVE_RP_VERSION, ARGB(EVE_C_DIM), TA_LEFT | TA_VCENTER);
      //--- minimize button
      m_minX2 = width - padX;
      m_minX1 = m_minX2 - btnW;
      m_minY1 = (headerH - btnW) / 2;
      m_minY2 = m_minY1 + btnW;
      m_canvas.FillRectangle(m_minX1, m_minY1, m_minX2, m_minY2, ARGB(EVE_C_LINE));
      FontValue();
      m_canvas.TextOut((m_minX1 + m_minX2) / 2, (m_minY1 + m_minY2) / 2, m_minimized ? "+" : "-",
                       ARGB(EVE_C_VALUE), TA_CENTER | TA_VCENTER);
      //--- state badge (pill)
      int bx2 = m_minX1 - S(8);
      int bx1 = bx2 - badgeW;
      int by1 = (headerH - badgeH) / 2;
      int by2 = by1 + badgeH;
      int r = badgeH / 2;
      color badgeBg = Mix(EVE_C_HEADER, m_badgeColor, 0.30);
      m_canvas.FillRectangle(bx1 + r, by1, bx2 - r, by2, ARGB(badgeBg));
      m_canvas.FillCircle(bx1 + r, by1 + r, r, ARGB(badgeBg));
      m_canvas.FillCircle(bx2 - r, by1 + r, r, ARGB(badgeBg));
      FontSection();
      m_canvas.TextOut((bx1 + bx2) / 2, (by1 + by2) / 2, m_badge, ARGB(m_badgeColor), TA_CENTER | TA_VCENTER);
      m_canvas.LineHorizontal(0, width - 1, headerH, ARGB(EVE_C_BORDER));
     }

   int y = headerH + S(4);
   bool hideBody = (m_minimized && m_enabled);
   int n = ArraySize(m_rows);
   for(int i = 0; i < n && !hideBody; i++)
     {
      int kind = m_rows[i].kind;
      if(kind == EVE_ROW_SECTION)
        {
         y += S(6);
         FontSection();
         int th = m_canvas.TextHeight(m_rows[i].key);
         if(drawIt)
           {
            m_canvas.TextOut(padX, y, m_rows[i].key, ARGB(m_rows[i].keyColor), TA_LEFT | TA_TOP);
            int tw = m_canvas.TextWidth(m_rows[i].key);
            m_canvas.LineHorizontal(padX + tw + S(8), width - padX, y + th / 2, ARGB(EVE_C_LINE));
           }
         y += th + S(4);
         continue;
        }
      if(kind == EVE_ROW_KV || kind == EVE_ROW_BIG)
        {
         FontLabel();
         int kw = m_canvas.TextWidth(m_rows[i].key);
         int kh = m_canvas.TextHeight("Ag");
         if(kind == EVE_ROW_BIG)
            FontBig();
         else
            FontValue();
         int vw = m_canvas.TextWidth(m_rows[i].value);
         int vh = m_canvas.TextHeight("Ag");
         int need = padX + kw + gap + vw + padX;
         if(need > neededWidth)
            neededWidth = need;
         int rowH = (vh > kh) ? vh : kh;
         if(drawIt)
           {
            int valueMax = width - 2 * padX - kw - gap;
            string v = Fit(m_rows[i].value, valueMax);
            m_canvas.TextOut(width - padX, y + rowH / 2, v, ARGB(m_rows[i].valueColor), TA_RIGHT | TA_VCENTER);
            FontLabel();
            m_canvas.TextOut(padX, y + rowH / 2, m_rows[i].key, ARGB(m_rows[i].keyColor), TA_LEFT | TA_VCENTER);
           }
         y += rowH + S(3);
         continue;
        }
      if(kind == EVE_ROW_BAR)
        {
         int barH = S(5);
         if(drawIt)
           {
            double rr = m_rows[i].ratio;
            if(rr < 0.0)
               rr = 0.0;
            if(rr > 1.0)
               rr = 1.0;
            int x1 = padX;
            int x2 = width - padX;
            m_canvas.FillRectangle(x1, y, x2, y + barH, ARGB(EVE_C_BAR_BG));
            int fx = x1 + (int)MathRound((x2 - x1) * rr);
            if(fx > x1)
               m_canvas.FillRectangle(x1, y, fx, y + barH, ARGB(m_rows[i].valueColor));
           }
         y += barH + S(6);
         continue;
        }
      if(kind == EVE_ROW_TEXT)
        {
         FontValue();
         string lines[];
         int textW = ((width > 0) ? width : neededWidth) - 2 * padX - S(12);
         if(textW < S(100))
            textW = S(100);
         int nl = Wrap(m_rows[i].key, textW, lines);
         int lh = m_canvas.TextHeight("Ag") + S(2);
         int boxH = nl * lh + S(12);
         y += S(4);
         if(drawIt)
           {
            color boxBg = Mix(EVE_C_BG, m_rows[i].keyColor, 0.18);
            m_canvas.FillRectangle(padX - S(4), y, width - padX + S(4), y + boxH, ARGB(boxBg));
            m_canvas.FillRectangle(padX - S(4), y, padX - S(2), y + boxH, ARGB(m_rows[i].keyColor));
            for(int k = 0; k < nl; k++)
               m_canvas.TextOut(padX + S(6), y + S(6) + k * lh, lines[k], ARGB(m_rows[i].keyColor), TA_LEFT | TA_TOP);
           }
         y += boxH + S(4);
         continue;
        }
      if(kind == EVE_ROW_NOTE)
        {
         FontSmall();
         y += S(4);
         string noteLines[];
         int noteW = ((width > 0) ? width : neededWidth) - 2 * padX;
         int nn = Wrap(m_rows[i].key, noteW, noteLines);
         int nh = m_canvas.TextHeight("Ag") + S(1);
         if(drawIt)
            for(int k = 0; k < nn; k++)
               m_canvas.TextOut(padX, y + k * nh, noteLines[k], ARGB(m_rows[i].keyColor), TA_LEFT | TA_TOP);
         y += nn * nh;
         continue;
        }
     }

   //--- RESET button (only while LOCKED)
   if(m_resetVisible)
     {
      y += S(8);
      int bh = S(30);
      m_rstX1 = padX;
      m_rstX2 = ((width > 0) ? width : neededWidth) - padX;
      m_rstY1 = y;
      m_rstY2 = y + bh;
      if(drawIt)
        {
         bool armed = ResetArmed();
         color bc = armed ? EVE_C_ORANGE : EVE_C_RED;
         m_canvas.FillRectangle(m_rstX1, m_rstY1, m_rstX2, m_rstY2, ARGB(bc));
         FontValue();
         m_canvas.TextOut((m_rstX1 + m_rstX2) / 2, (m_rstY1 + m_rstY2) / 2,
                          armed ? "CLICK AGAIN TO CONFIRM RESET" : "RESET PROTECTION",
                          ARGB(clrWhite), TA_CENTER | TA_VCENTER);
        }
      y += bh;
     }
   y += S(10);
   if(neededWidth > maxW)
      neededWidth = maxW;
   if(drawIt)
      m_canvas.Rectangle(0, 0, width - 1, y - 1, ARGB(EVE_C_BORDER));
   return y;
  }

//+------------------------------------------------------------------+
bool CEveRiskDashboard::EnsureCanvas(const int w, const int h)
  {
   if(!m_created)
     {
      ObjectDelete(0, EVE_DB_OBJ);
      if(!m_canvas.CreateBitmapLabel(EVE_DB_OBJ, 0, 0, w, h, COLOR_FORMAT_ARGB_NORMALIZE))
         return false;
      ObjectSetInteger(0, EVE_DB_OBJ, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, EVE_DB_OBJ, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, EVE_DB_OBJ, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, EVE_DB_OBJ, OBJPROP_BACK, false);
      ObjectSetInteger(0, EVE_DB_OBJ, OBJPROP_ZORDER, 10);
      m_created = true;
      m_w = w;
      m_h = h;
     }
   else
      if(w != m_w || h != m_h)
        {
         if(!m_canvas.Resize(w, h))
            return false;
         ObjectSetInteger(0, EVE_DB_OBJ, OBJPROP_XSIZE, w);
         ObjectSetInteger(0, EVE_DB_OBJ, OBJPROP_YSIZE, h);
         m_w = w;
         m_h = h;
        }
   Place();
   return true;
  }

//+------------------------------------------------------------------+
//| Position from the chosen corner (object anchored top-left, so a  |
//| click maps to panel coordinates with a simple subtraction).      |
//+------------------------------------------------------------------+
void CEveRiskDashboard::Place(void)
  {
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int x = m_offX;
   int y = m_offY;
   if(m_corner == EVE_CORNER_RIGHT_UPPER || m_corner == EVE_CORNER_RIGHT_LOWER)
      x = cw - m_w - m_offX;
   if(m_corner == EVE_CORNER_LEFT_LOWER || m_corner == EVE_CORNER_RIGHT_LOWER)
      y = ch - m_h - m_offY;
   if(x < 0)
      x = 0;
   if(y < 0)
      y = 0;
   m_posX = x;
   m_posY = y;
   ObjectSetInteger(0, EVE_DB_OBJ, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, EVE_DB_OBJ, OBJPROP_YDISTANCE, y);
  }

//+------------------------------------------------------------------+
void CEveRiskDashboard::Update(const SEveDashboardData &d)
  {
   m_resetVisible = d.showReset;
   if(!m_enabled && !d.showReset)
     {
      if(m_created)
         Destroy();
      return;
     }
   if(!m_created)
     {
      //--- a 1x1 canvas is needed to measure text with the canvas fonts
      if(!EnsureCanvas(1, 1))
         return;
     }
   BuildRows(d);
   int needed = 0;
   Render(false, m_w, needed);
   int w = needed;
   int h = Render(false, w, needed);
   if(!EnsureCanvas(w, h))
      return;
   Render(true, w, needed);
   m_canvas.Update(true);
  }

//+------------------------------------------------------------------+
void CEveRiskDashboard::Destroy(void)
  {
   if(m_created)
      m_canvas.Destroy();
   ObjectDelete(0, EVE_DB_OBJ);
   m_created = false;
   m_w = 0;
   m_h = 0;
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
int CEveRiskDashboard::HandleClick(const string objectName, const int x, const int y)
  {
   if(objectName != EVE_DB_OBJ || !m_created)
      return 0;
   int lx = x - m_posX;
   int ly = y - m_posY;
   if(lx >= m_minX1 && lx <= m_minX2 && ly >= m_minY1 && ly <= m_minY2)
     {
      m_minimized = !m_minimized;
      return 3;
     }
   if(m_resetVisible && lx >= m_rstX1 && lx <= m_rstX2 && ly >= m_rstY1 && ly <= m_rstY2)
     {
      ulong now = GetTickCount64();
      if(m_resetArmedUntil > now)
        {
         m_resetArmedUntil = 0;
         return 2;
        }
      m_resetArmedUntil = now + 10000;
      return 1;
     }
   return 0;
  }

#endif // EVE_RISK_RISKDASHBOARD_MQH
//+------------------------------------------------------------------+
