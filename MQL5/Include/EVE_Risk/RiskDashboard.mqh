//+------------------------------------------------------------------+
//|                                                RiskDashboard.mqh |
//| Chart panel drawn on one bitmap (CCanvas), plain simple English.  |
//| - compact layout (v1.12): small fonts, tight rows                 |
//| - "Panel size (%)" input scales fonts and spacing (50..200 %)     |
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
   double            m_zoom;    // "Panel size (%)" / 100
   double            m_scale;   // DPI / 96 x m_zoom
   ulong             m_resetArmedUntil;
   int               m_minX1, m_minY1, m_minX2, m_minY2;
   int               m_rstX1, m_rstY1, m_rstX2, m_rstY2;
   bool              m_resetVisible;
   SEveDbRow         m_rows[];
   string            m_title;
   string            m_badge;
   color             m_badgeColor;

   int               S(const double v) const { return (int)MathRound(v * m_scale); }
   uint              ToArgb(const color c) const { return ColorToARGB(c, 255); }   // not "ARGB": Canvas.mqh defines a macro with that name
   static color      Mix(const color a, const color b, const double t);
   void              Font(const int tenthsOfPoint, const uint weight);
   void              FontLabel(void)   { Font(60, FW_NORMAL);   }
   void              FontValue(void)   { Font(60, FW_SEMIBOLD); }
   void              FontTitle(void)   { Font(65, FW_BOLD);     }
   void              FontSection(void) { Font(50, FW_BOLD);     }
   void              FontBig(void)     { Font(85, FW_BOLD);     }
   void              FontSmall(void)   { Font(50, FW_NORMAL);   }
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
   void              Init(const bool enabled, const int corner, const int x, const int y, const int sizePct);
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
                                             m_zoom(1.0),
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
void CEveRiskDashboard::Init(const bool enabled, const int corner, const int x, const int y, const int sizePct)
  {
   m_enabled = enabled;
   m_corner = corner;
   m_offX = x;
   m_offY = y;
   int pct = sizePct;
   if(pct < 50)
      pct = 50;
   if(pct > 200)
      pct = 200;
   m_zoom = pct / 100.0;
   double dpi = (double)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   double dpiScale = (dpi > 0.0) ? dpi / 96.0 : 1.0;
   if(dpiScale < 1.0)
      dpiScale = 1.0;
   if(dpiScale > 3.0)
      dpiScale = 3.0;
   m_scale = dpiScale * m_zoom;
   ObjectsDeleteAll(0, "EVERP_DB_");   // leftovers of the v1.00 label dashboard
  }

//+------------------------------------------------------------------+
//| Negative size = tenths of a point, so Windows applies its own    |
//| display scaling; the panel size input scales it further.         |
//+------------------------------------------------------------------+
void CEveRiskDashboard::Font(const int tenthsOfPoint, const uint weight)
  {
   int size = (int)MathRound(tenthsOfPoint * m_zoom);
   if(size < 30)
      size = 30;
   m_canvas.FontSet(EVE_DB_FONT, -size, weight);
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
   bool currencyOK = (d.currency == EVE_RP_REQUIRED_CURRENCY);

   //--- account (the account currency is part of the section title)
   AddRow(EVE_ROW_SECTION, (d.currency != "") ? "ACCOUNT (" + d.currency + ")" : "ACCOUNT", "",
          EVE_C_SECTION, EVE_C_SECTION, 0.0);
   if(!currencyOK)
      AddRow(EVE_ROW_KV, "Currency", d.currency + " - IDR required", EVE_C_LABEL, EVE_C_RED, 0.0);
   AddRow(EVE_ROW_KV, "Balance", EveFormatIDR(d.balance), EVE_C_LABEL, EVE_C_VALUE, 0.0);
   AddRow(EVE_ROW_KV, "Equity", EveFormatIDR(d.equity), EVE_C_LABEL, EVE_C_VALUE, 0.0);
   AddRow(EVE_ROW_BIG, "Floating", EveFormatIDRSigned(fl), EVE_C_LABEL,
          (fl < 0.0) ? EVE_C_RED : ((fl > 0.0) ? EVE_C_GREEN : EVE_C_VALUE), 0.0);
   AddRow(EVE_ROW_KV, "Positions", IntegerToString(d.positions) + " open | " + IntegerToString(d.pendingOrders) + " pending",
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
      AddRow(EVE_ROW_KV, "SL status", st + ((d.slUnprotected > 0) ? " (" + IntegerToString(d.slUnprotected) + " without SL)" : ""),
             EVE_C_LABEL, sc, 0.0);
     }
   else
      AddRow(EVE_ROW_KV, "Auto SL", "OFF", EVE_C_LABEL, EVE_C_DIM, 0.0);

   if(d.trailActive)
      AddRow(EVE_ROW_KV, "Trailing stop",
             (d.trailGroups > 0) ? "ON - running on " + IntegerToString(d.trailGroups) + " basket(s)"
                                 : "ON - starts at " + EveFormatIDRLong(d.trailStart),
             EVE_C_LABEL, (d.trailGroups > 0) ? EVE_C_GREEN : EVE_C_VALUE, 0.0);
   else
      AddRow(EVE_ROW_KV, "Trailing stop", "OFF", EVE_C_LABEL, EVE_C_DIM, 0.0);
   if(d.lockedProfit > 0.0)
      AddRow(EVE_ROW_KV, "Profit locked by SL", EveFormatIDR(d.lockedProfit), EVE_C_LABEL, EVE_C_GREEN, 0.0);
   if(d.tpActive)
      AddRow(EVE_ROW_KV, "Basket TP", EveFormatIDRLong(d.tpTarget), EVE_C_LABEL, EVE_C_VALUE, 0.0);
   else
      AddRow(EVE_ROW_KV, "Basket TP", "OFF", EVE_C_LABEL, EVE_C_DIM, 0.0);

   //--- system
   AddRow(EVE_ROW_SECTION, "SYSTEM", "", EVE_C_SECTION, EVE_C_SECTION, 0.0);
   AddRow(EVE_ROW_KV, "Auto Trading", d.tradeAllowed ? "OK (" + d.marginMode + ")" : "OFF - " + d.tradeBlock,
          EVE_C_LABEL, d.tradeAllowed ? EVE_C_GREEN : EVE_C_RED, 0.0);
   AddRow(EVE_ROW_KV, "Lock after close", "Loss " + EveBoolOnOff(d.lockLoss) + " | Profit " + EveBoolOnOff(d.lockProfit),
          EVE_C_LABEL, EVE_C_VALUE, 0.0);
   if((d.lockLoss || d.lockProfit) && !d.cancelPending)
      AddRow(EVE_ROW_KV, "Pending when locked", "NOT deleted", EVE_C_LABEL, EVE_C_ORANGE, 0.0);
   AddRow(EVE_ROW_KV, "Last event", (d.lastEvent != "") ? d.lastEvent : "-", EVE_C_LABEL, EVE_C_DIM, 0.0);
   if(d.banner != "")
      AddRow(EVE_ROW_TEXT, d.banner, "", d.bannerColor, d.bannerColor, 0.0);
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
   int padX = S(7);
   int gap = S(10);
   int headerH = S(20);
   int maxW = S(300);
   neededWidth = S(170);

   //--- header: title + version + badge + minimize button
   string ver = "v" + EVE_RP_VERSION;
   FontTitle();
   int titleW = m_canvas.TextWidth(m_title);
   FontSmall();
   int verW = m_canvas.TextWidth(ver);
   FontSection();
   int badgeTextW = m_canvas.TextWidth(m_badge);
   int badgeW = badgeTextW + S(10);
   int badgeH = S(13);
   int btnW = S(13);
   int headerNeed = padX + titleW + S(4) + verW + S(8) + badgeW + S(6) + btnW + padX;
   if(headerNeed > neededWidth)
      neededWidth = headerNeed;

   if(drawIt)
     {
      m_canvas.Erase(ToArgb(EVE_C_BG));
      m_canvas.FillRectangle(0, 0, width - 1, headerH, ToArgb(EVE_C_HEADER));
      FontTitle();
      m_canvas.TextOut(padX, headerH / 2, m_title, ToArgb(EVE_C_VALUE), TA_LEFT | TA_VCENTER);
      FontSmall();
      m_canvas.TextOut(padX + titleW + S(4), headerH / 2, ver, ToArgb(EVE_C_DIM), TA_LEFT | TA_VCENTER);
      //--- minimize button
      m_minX2 = width - padX;
      m_minX1 = m_minX2 - btnW;
      m_minY1 = (headerH - btnW) / 2;
      m_minY2 = m_minY1 + btnW;
      m_canvas.FillRectangle(m_minX1, m_minY1, m_minX2, m_minY2, ToArgb(EVE_C_LINE));
      FontValue();
      m_canvas.TextOut((m_minX1 + m_minX2) / 2, (m_minY1 + m_minY2) / 2, m_minimized ? "+" : "-",
                       ToArgb(EVE_C_VALUE), TA_CENTER | TA_VCENTER);
      //--- state badge (pill)
      int bx2 = m_minX1 - S(6);
      int bx1 = bx2 - badgeW;
      int by1 = (headerH - badgeH) / 2;
      int by2 = by1 + badgeH;
      int r = badgeH / 2;
      color badgeBg = Mix(EVE_C_HEADER, m_badgeColor, 0.30);
      m_canvas.FillRectangle(bx1 + r, by1, bx2 - r, by2, ToArgb(badgeBg));
      m_canvas.FillCircle(bx1 + r, by1 + r, r, ToArgb(badgeBg));
      m_canvas.FillCircle(bx2 - r, by1 + r, r, ToArgb(badgeBg));
      FontSection();
      m_canvas.TextOut((bx1 + bx2) / 2, (by1 + by2) / 2, m_badge, ToArgb(m_badgeColor), TA_CENTER | TA_VCENTER);
      m_canvas.LineHorizontal(0, width - 1, headerH, ToArgb(EVE_C_BORDER));
     }

   bool hideBody = (m_minimized && m_enabled);
   int y = headerH + 1;
   if(!hideBody)
      y += S(1);
   int n = ArraySize(m_rows);
   for(int i = 0; i < n && !hideBody; i++)
     {
      int kind = m_rows[i].kind;
      if(kind == EVE_ROW_SECTION)
        {
         y += S(3);
         FontSection();
         int th = m_canvas.TextHeight(m_rows[i].key);
         if(drawIt)
           {
            m_canvas.TextOut(padX, y, m_rows[i].key, ToArgb(m_rows[i].keyColor), TA_LEFT | TA_TOP);
            int tw = m_canvas.TextWidth(m_rows[i].key);
            m_canvas.LineHorizontal(padX + tw + S(6), width - padX, y + th / 2, ToArgb(EVE_C_LINE));
           }
         y += th + S(1);
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
            m_canvas.TextOut(width - padX, y + rowH / 2, v, ToArgb(m_rows[i].valueColor), TA_RIGHT | TA_VCENTER);
            FontLabel();
            m_canvas.TextOut(padX, y + rowH / 2, m_rows[i].key, ToArgb(m_rows[i].keyColor), TA_LEFT | TA_VCENTER);
           }
         y += rowH + S(1);
         continue;
        }
      if(kind == EVE_ROW_BAR)
        {
         int barH = S(2);
         if(drawIt)
           {
            double rr = m_rows[i].ratio;
            if(rr < 0.0)
               rr = 0.0;
            if(rr > 1.0)
               rr = 1.0;
            int x1 = padX;
            int x2 = width - padX;
            m_canvas.FillRectangle(x1, y, x2, y + barH, ToArgb(EVE_C_BAR_BG));
            int fx = x1 + (int)MathRound((x2 - x1) * rr);
            if(fx > x1)
               m_canvas.FillRectangle(x1, y, fx, y + barH, ToArgb(m_rows[i].valueColor));
           }
         y += barH + S(3);
         continue;
        }
      if(kind == EVE_ROW_TEXT)
        {
         FontValue();
         string lines[];
         int textW = ((width > 0) ? width : neededWidth) - 2 * padX - S(8);
         if(textW < S(80))
            textW = S(80);
         int nl = Wrap(m_rows[i].key, textW, lines);
         int lh = m_canvas.TextHeight("Ag") + S(1);
         int boxH = nl * lh + S(8);
         y += S(3);
         if(drawIt)
           {
            color boxBg = Mix(EVE_C_BG, m_rows[i].keyColor, 0.18);
            m_canvas.FillRectangle(padX - S(3), y, width - padX + S(3), y + boxH, ToArgb(boxBg));
            m_canvas.FillRectangle(padX - S(3), y, padX - S(2), y + boxH, ToArgb(m_rows[i].keyColor));
            for(int k = 0; k < nl; k++)
               m_canvas.TextOut(padX + S(4), y + S(4) + k * lh, lines[k], ToArgb(m_rows[i].keyColor), TA_LEFT | TA_TOP);
           }
         y += boxH + S(3);
         continue;
        }
     }

   //--- RESET button (only while LOCKED, also when the panel is minimized)
   if(m_resetVisible)
     {
      y += S(5);
      int bh = S(20);
      m_rstX1 = padX;
      m_rstX2 = ((width > 0) ? width : neededWidth) - padX;
      m_rstY1 = y;
      m_rstY2 = y + bh;
      if(drawIt)
        {
         bool armed = ResetArmed();
         color bc = armed ? EVE_C_ORANGE : EVE_C_RED;
         m_canvas.FillRectangle(m_rstX1, m_rstY1, m_rstX2, m_rstY2, ToArgb(bc));
         FontValue();
         m_canvas.TextOut((m_rstX1 + m_rstX2) / 2, (m_rstY1 + m_rstY2) / 2,
                          armed ? "CLICK AGAIN TO CONFIRM RESET" : "RESET PROTECTION",
                          ToArgb(clrWhite), TA_CENTER | TA_VCENTER);
        }
      y += bh;
     }
   if(!hideBody || m_resetVisible)
      y += S(5);
   if(neededWidth > maxW)
      neededWidth = maxW;
   if(drawIt)
      m_canvas.Rectangle(0, 0, width - 1, y - 1, ToArgb(EVE_C_BORDER));
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
   int tol = S(3);   // the minimize button is small: accept clicks just around it
   if(lx >= m_minX1 - tol && lx <= m_minX2 + tol && ly >= m_minY1 - tol && ly <= m_minY2 + tol)
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
