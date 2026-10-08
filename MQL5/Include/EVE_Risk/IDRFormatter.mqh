//+------------------------------------------------------------------+
//|                                                 IDRFormatter.mqh |
//|        Rupiah formatting: Rp500.000 / Rp1.000.000 / -Rp500.000   |
//+------------------------------------------------------------------+
#ifndef EVE_RISK_IDRFORMATTER_MQH
#define EVE_RISK_IDRFORMATTER_MQH

// Inserts '.' as thousands separator into a string of digits.
string EveGroupThousands(const string digits)
  {
   string out = "";
   int len = StringLen(digits);
   for(int i = 0; i < len; i++)
     {
      if(i > 0 && ((len - i) % 3) == 0)
         out += ".";
      out += StringSubstr(digits, i, 1);
     }
   return out;
  }

// Formats a whole Rupiah amount, e.g. 1000000 -> "Rp1.000.000", -500000 -> "-Rp500.000".
string EveFormatIDRLong(const long value)
  {
   if(value == LONG_MIN)
      return "-Rp9.223.372.036.854.775.808";
   bool neg = (value < 0);
   long a = neg ? -value : value;
   return (neg ? "-Rp" : "Rp") + EveGroupThousands(IntegerToString(a));
  }

// Formats a money value in IDR, rounded to whole Rupiah (half away from zero).
string EveFormatIDR(const double value)
  {
   if(!MathIsValidNumber(value))
      return "Rp?";
   double r = MathRound(value);
   if(r >= 9.0e18)
      return "Rp>9e18";
   if(r <= -9.0e18)
      return "-Rp>9e18";
   return EveFormatIDRLong((long)r);
  }

// Same as EveFormatIDR but with an explicit '+' for positive amounts (floating P/L display).
string EveFormatIDRSigned(const double value)
  {
   string s = EveFormatIDR(value);
   if(MathIsValidNumber(value) && MathRound(value) > 0.0)
      return "+" + s;
   return s;
  }

#endif // EVE_RISK_IDRFORMATTER_MQH
//+------------------------------------------------------------------+
