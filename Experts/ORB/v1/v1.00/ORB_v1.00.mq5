#property version   "1.00"
#property description "GOLD Open Range Breakout (ORB) Expert Advisor - (Recommended) H1 Timeframe"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ORB_STATE_ENUM {
   ORB_IDLE,      // Waiting for market open candle
   ORB_FORMING,   // Initial candle closed; collecting composition candles
   ORB_FINAL,     // Range finalized; watching for breakout
   ORB_TRADED     // Both sides triggered; waiting for next day
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "==== General Settings ===="
input long   InpMagicNumber          = 16;        // Magic Number
input int    InpSessionStartHour     = 21;        // Session start hour in UTC (DEFAULT: XAUUSD)
input int    InpMarketOpenHour       = 22;        // Market open hour in UTC (DEFAULT: XAUUSD)
input int    InpMinComposition       = 3;         // Min candles inside range to finalize (set 0 to care only 1 bar)

input group "==== TP/SL Settings ===="
input int    InpSLPoints             = 4000;      // Stop Loss in points (0=off)
input int    InpTPPoints             = 12000;     // Take Profit in points (0=off)

input group "==== Trailing Stop ===="
input bool   InpUseTrail             = false;     // Enable Trailing Stop
input int    InpTrailPoints          = 1500;      // Trailing Stop distance in points
input int    InpTrailStep            = 100;       // Trailing step in points (min move)

input group "==== Risk Management ===="
input double InpFixedLot             = 0.1;       // Fixed Lot Size
input int    InpRiskPerTradePercent  = 1;         // Risk Per Trade % (0=use FixedLot)

input group "==== Day Filter ===="
input bool   InpMonday               = true;
input bool   InpTuesday              = true;
input bool   InpWednesday            = true;
input bool   InpThursday             = true;
input bool   InpFriday               = true;

//+------------------------------------------------------------------+
//| Range Structure                                                  |
//+------------------------------------------------------------------+
struct ORB_RANGE {
   datetime initCandleTime;   // Opening time of the initial range candle
   datetime sessionStart;     // Start of the current trading session (InpSessionStartHour UTC)
   double   high;             // Range high (resistance level)
   double   low;              // Range low (support level)
   int      composition;      // Number of candles that stayed within range
   bool     buyDone;          // Buy signal already triggered today
   bool     sellDone;         // Sell signal already triggered today

   ORB_RANGE() : initCandleTime(0), sessionStart(0),
                 high(0.0), low(DBL_MAX),
                 composition(0), buyDone(false), sellDone(false) {}
};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
ORB_RANGE      g_range;
ORB_STATE_ENUM g_state        = ORB_IDLE;
CTrade         g_trade;
MqlTick        g_lastTick;
datetime       g_lastBarTime  = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit() {
   if (InpMagicNumber <= 0) {
      Alert("[ORB] Magic Number must be greater than 0");
      return INIT_FAILED;
   }

   // ORB is an intraday strategy — D1 and above span multiple sessions per bar
   if (PeriodSeconds(_Period) >= 86400) {
      Alert("[ORB] Timeframe ", EnumToString(_Period), " is not supported. Use H4 or below.");
      return INIT_FAILED;
   }

   if (InpSessionStartHour < 0 || InpSessionStartHour > 23) {
      Alert("[ORB] InpSessionStartHour must be between 0 and 23");
      return INIT_FAILED;
   }

   if (InpMarketOpenHour < 0 || InpMarketOpenHour > 23) {
      Alert("[ORB] InpMarketOpenHour must be between 0 and 23");
      return INIT_FAILED;
   }

   if (InpMarketOpenHour == InpSessionStartHour) {
      Alert("[ORB] InpMarketOpenHour must differ from InpSessionStartHour");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);

   DrawObjects();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   ObjectsDeleteAll(NULL, "orb_");
   Comment("");
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick() {
   SymbolInfoTick(_Symbol, g_lastTick);

   // Trailing stop management on every tick
   if (InpUseTrail) ManageTrailingStop();

   // Detect new bar
   datetime curBar = iTime(_Symbol, _Period, 0); // opening time of the bar index
   if (curBar != g_lastBarTime) {
      g_lastBarTime = curBar;
      OnNewBar(curBar);
   }

   // Breakout detection on every tick when range is finalized
   if (g_state == ORB_FINAL) {
      CheckBreakout();
   }

   ShowComment();
}

//+------------------------------------------------------------------+
//| New bar handler                                                  |
//+------------------------------------------------------------------+
void OnNewBar(datetime barOpenTime) {
   CheckDayReset(barOpenTime);
   if (!IsTradingDay())        return;
   RunStateMachine();
}

//+------------------------------------------------------------------+
//| Compute session start timestamp for a given bar time             |
//+------------------------------------------------------------------+
// A "session day" starts at InpSessionStartHour UTC each day.
// E.g. InpSessionStartHour = 22 → session runs 22:00 UTC to 22:00 UTC next day.
datetime GetSessionStart(datetime barTime) {
   datetime offset       = (datetime)(InpSessionStartHour * 3600);
   datetime adjustedTime = barTime - offset;
   datetime sessionDay   = adjustedTime - (adjustedTime % 86400);  // UTC-day in adjusted time
   return sessionDay + offset;                                      // back to actual UTC
}

//+------------------------------------------------------------------+
//| Reset state when a new session day starts                        |
//+------------------------------------------------------------------+
void CheckDayReset(datetime barTime) {
   datetime sessionStart = GetSessionStart(barTime);
   if (sessionStart == g_range.sessionStart) return;

   g_range.initCandleTime = 0;
   g_range.sessionStart    = sessionStart;
   g_range.high           = 0.0;
   g_range.low            = DBL_MAX;
   g_range.composition    = 0;
   g_range.buyDone        = false;
   g_range.sellDone       = false;
   g_state                = ORB_IDLE;

   DrawObjects();
   Print("[ORB] New session day at ", TimeToString(sessionStart), " UTC. State reset to IDLE.");
}

//+------------------------------------------------------------------+
//| State machine — runs once per bar                                |
//+------------------------------------------------------------------+
void RunStateMachine() {
   // Read the bar that JUST CLOSED (index 1)
   datetime closedBarTime = iTime (_Symbol, _Period, 1);
   double   closedHigh    = iHigh (_Symbol, _Period, 1);
   double   closedLow     = iLow  (_Symbol, _Period, 1);

   // Calculate bar index from session start — period-agnostic, timezone-aware
   // targetBarIdx is derived from InpMarketOpenHour automatically for any timeframe:
   //   delta = (InpMarketOpenHour - InpSessionStartHour + 24) % 24 hours
   //   targetBarIdx = delta_seconds / periodSecs
   datetime sessionStart  = GetSessionStart(closedBarTime);
   int      periodSecs    = PeriodSeconds(_Period);
   int      barIndexOfDay = (int)((closedBarTime - sessionStart) / periodSecs);
   int      deltaSeconds  = ((InpMarketOpenHour - InpSessionStartHour + 24) % 24) * 3600;
   int      targetBarIdx  = deltaSeconds / periodSecs;  // bar containing market open

   if (g_state == ORB_IDLE) {
      // The initial range candle is the bar containing InpMarketOpenHour UTC
      if (barIndexOfDay == targetBarIdx) {
         g_range.initCandleTime = closedBarTime;
         g_range.high           = closedHigh;
         g_range.low            = closedLow;
         g_range.composition    = 0;
         DrawObjects();

         // InpMinComposition = 0: single-bar range mode
         // Skip FORMING entirely → range is locked to exactly this 1 candle
         if (InpMinComposition == 0) {
            g_state = ORB_FINAL;
            Print("[ORB] Single-bar range FINALIZED (", InpMarketOpenHour, ":00 UTC, bar #", targetBarIdx, "). High=", g_range.high, " Low=", g_range.low);
         } else {
            g_state = ORB_FORMING;
            Print("[ORB] Initial range set (", InpMarketOpenHour, ":00 UTC, bar #", targetBarIdx, " of day). High=", g_range.high, " Low=", g_range.low);
         }
      }
   }
   else if (g_state == ORB_FORMING) {
      bool extended = false;

      // Extend range if closed candle broke out
      if (closedHigh > g_range.high) {
         g_range.high = closedHigh;
         extended     = true;
         Print("[ORB] Range high extended to ", g_range.high);
      }
      if (closedLow < g_range.low) {
         g_range.low = closedLow;
         extended    = true;
         Print("[ORB] Range low extended to ", g_range.low);
      }

      // Candle composed (stayed within range) — count it
      if (!extended) {
         g_range.composition++;
         Print("[ORB] Composition: ", g_range.composition, "/", InpMinComposition);
      }

      if (g_range.composition >= InpMinComposition) {
         g_state = ORB_FINAL;
         Print("[ORB] Range FINALIZED. High=", g_range.high,
               " Low=", g_range.low,
               " Width=", DoubleToString(g_range.high - g_range.low, _Digits));
      }
      DrawObjects();
   }
   // ORB_FINAL and ORB_TRADED: breakout handled per-tick; nothing extra on bar
}

//+------------------------------------------------------------------+
//| Breakout detection — called on every tick when state == FINAL    |
//+------------------------------------------------------------------+
void CheckBreakout() {
   if (!IsTradingDay())        return;
   if (g_range.high <= 0 || g_range.low >= DBL_MAX) return;

   // BUY signal: price breaks above range high
   if (!g_range.buyDone && g_lastTick.ask >= g_range.high) {
      double sl   = InpSLPoints > 0 ? NormalizeDouble(g_lastTick.ask - InpSLPoints * _Point, _Digits) : 0;
      double tp   = InpTPPoints > 0 ? NormalizeDouble(g_lastTick.ask + InpTPPoints * _Point, _Digits) : 0;
      double lots = CalcLotSize(InpSLPoints);

      if (g_trade.Buy(lots, _Symbol, g_lastTick.ask, sl, tp, "ORB Buy")) {
         if (g_trade.ResultRetcode() == TRADE_RETCODE_DONE) {
            g_range.buyDone = true;
            Print("[ORB] BUY opened. Price=", g_lastTick.ask, " SL=", sl, " TP=", tp, " Lots=", lots);
         }
      } else {
         Print("[ORB] Buy failed: ", g_trade.ResultRetcodeDescription());
      }
   }

   // SELL signal: price breaks below range low
   if (!g_range.sellDone && g_lastTick.bid <= g_range.low) {
      double sl   = InpSLPoints > 0 ? NormalizeDouble(g_lastTick.bid + InpSLPoints * _Point, _Digits) : 0;
      double tp   = InpTPPoints > 0 ? NormalizeDouble(g_lastTick.bid - InpTPPoints * _Point, _Digits) : 0;
      double lots = CalcLotSize(InpSLPoints);

      if (g_trade.Sell(lots, _Symbol, g_lastTick.bid, sl, tp, "ORB Sell")) {
         if (g_trade.ResultRetcode() == TRADE_RETCODE_DONE) {
            g_range.sellDone = true;
            Print("[ORB] SELL opened. Price=", g_lastTick.bid, " SL=", sl, " TP=", tp, " Lots=", lots);
         }
      } else {
         Print("[ORB] Sell failed: ", g_trade.ResultRetcodeDescription());
      }
   }

   // Both sides done → move to TRADED
   if (g_range.buyDone && g_range.sellDone) {
      g_state = ORB_TRADED;
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size                                               |
//+------------------------------------------------------------------+
double CalcLotSize(int slPoints) {
   double lots = InpFixedLot;  // safe default — also avoids uninitialized warning

   if (InpRiskPerTradePercent > 0 && slPoints > 0) {
      double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount = balance * InpRiskPerTradePercent / 100.0;
      double tickVal    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double pointVal   = (tickSize > 0) ? tickVal * _Point / tickSize : 0;
      double slCost     = slPoints * pointVal;
      lots = (slCost > 0) ? riskAmount / slCost : InpFixedLot;
   }

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / stepLot) * stepLot;

   // MathFloor can give 0 if calculated lot < stepLot → warn and use minLot
   if (lots <= 0) {
      PrintFormat("[ORB] CalcLotSize: calculated lot too small → forced to minLot=%.2f. "
                  "Consider increasing InpRiskPerTradePercent or reducing InpSLPoints.", minLot);
      lots = minLot;
   }

   return MathMax(minLot, MathMin(maxLot, lots));
}

//+------------------------------------------------------------------+
//| Trailing stop — called on every tick                             |
//+------------------------------------------------------------------+
void ManageTrailingStop() {
   if (InpTrailPoints <= 0) return;
   double trail = InpTrailPoints * _Point;
   double step  = InpTrailStep  * _Point;

   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))                     continue;
      if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)        continue;

      long   posType  = PositionGetInteger(POSITION_TYPE);
      double curSL    = PositionGetDouble(POSITION_SL);
      double curTP    = PositionGetDouble(POSITION_TP);
      double openPx   = PositionGetDouble(POSITION_PRICE_OPEN);

      if (posType == POSITION_TYPE_BUY) {
         double newSL = NormalizeDouble(g_lastTick.bid - trail, _Digits);
         // Trail only when in profit; improve by at least one step
         if (newSL > openPx && (curSL == 0 || newSL >= curSL + step)) {
            g_trade.PositionModify(ticket, newSL, curTP);
         }
      }
      else if (posType == POSITION_TYPE_SELL) {
         double newSL = NormalizeDouble(g_lastTick.ask + trail, _Digits);
         if (newSL < openPx && (curSL == 0 || newSL <= curSL - step)) {
            g_trade.PositionModify(ticket, newSL, curTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Day filter                                                       |
//+------------------------------------------------------------------+
bool IsTradingDay() {
   MqlDateTime dt;
   TimeToStruct(g_lastTick.time, dt);
   if (dt.day_of_week == 1 && !InpMonday)    return false;
   if (dt.day_of_week == 2 && !InpTuesday)   return false;
   if (dt.day_of_week == 3 && !InpWednesday) return false;
   if (dt.day_of_week == 4 && !InpThursday)  return false;
   if (dt.day_of_week == 5 && !InpFriday)    return false;
   return true;
}

//+------------------------------------------------------------------+
//| Draw chart objects                                               |
//+------------------------------------------------------------------+
void DrawObjects() {
   ObjectsDeleteAll(NULL, "orb_");

   if (g_range.initCandleTime == 0) return;

   // Vertical line at range start
   ObjectCreate(NULL, "orb_start", OBJ_VLINE, 0, g_range.initCandleTime, 0);
   ObjectSetInteger(NULL, "orb_start", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(NULL, "orb_start", OBJPROP_WIDTH, 2);
   ObjectSetInteger(NULL, "orb_start", OBJPROP_BACK,  true);
   ObjectSetString (NULL, "orb_start", OBJPROP_TOOLTIP, "ORB Start: " + TimeToString(g_range.initCandleTime));

   // Horizontal line — range HIGH
   if (g_range.high > 0) {
      ObjectCreate(NULL, "orb_high", OBJ_HLINE, 0, 0, g_range.high);
      ObjectSetInteger(NULL, "orb_high", OBJPROP_COLOR, clrLimeGreen);
      ObjectSetInteger(NULL, "orb_high", OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(NULL, "orb_high", OBJPROP_WIDTH, 2);
      ObjectSetString (NULL, "orb_high", OBJPROP_TOOLTIP, "ORB High: " + DoubleToString(g_range.high, _Digits));
   }

   // Horizontal line — range LOW
   if (g_range.low < DBL_MAX) {
      ObjectCreate(NULL, "orb_low", OBJ_HLINE, 0, 0, g_range.low);
      ObjectSetInteger(NULL, "orb_low", OBJPROP_COLOR, clrOrangeRed);
      ObjectSetInteger(NULL, "orb_low", OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(NULL, "orb_low", OBJPROP_WIDTH, 2);
      ObjectSetString (NULL, "orb_low", OBJPROP_TOOLTIP, "ORB Low: " + DoubleToString(g_range.low, _Digits));
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Chart comment                                                    |
//+------------------------------------------------------------------+
void ShowComment() {
   string stateStr;
   switch (g_state) {
      case ORB_IDLE:    stateStr = "IDLE — Waiting for market open";                                      break;
      case ORB_FORMING: stateStr = "FORMING — Composition " + (string)g_range.composition + "/" + (string)InpMinComposition; break;
      case ORB_FINAL:   stateStr = "FINAL — Watching for breakout";                                       break;
      case ORB_TRADED:  stateStr = "TRADED — Both signals done";                                          break;
   }

   string highStr = (g_range.high > 0)        ? DoubleToString(g_range.high, _Digits) : "N/A";
   string lowStr  = (g_range.low < DBL_MAX)   ? DoubleToString(g_range.low,  _Digits) : "N/A";

   // Calculate barIndexOfDay and targetBarIdx for display
   datetime curBarTime    = iTime(_Symbol, _Period, 0);
   datetime curSession    = GetSessionStart(curBarTime);
   int      periodSecs    = PeriodSeconds(_Period);
   int      curBarIdx     = (int)((curBarTime - curSession) / periodSecs);
   int      targetBarIdx  = (((InpMarketOpenHour - InpSessionStartHour + 24) % 24) * 3600) / periodSecs;

   // Broker UTC offset
   int    offsetSec  = (int)(TimeCurrent() - TimeGMT());
   int    offsetHour = offsetSec / 3600;
   int    offsetMin  = MathAbs((offsetSec % 3600) / 60);
   string utcOffset  = StringFormat("UTC%+d", offsetHour);
   if (offsetMin != 0) utcOffset += StringFormat(":%02d", offsetMin);

   Comment(
      "=== GOLD ORB v1.00 ===\n",
      "Start time session: ", TimeToString(curSession, TIME_DATE|TIME_SECONDS), "\n",
      "Tick Time  : ", TimeToString(g_lastTick.time, TIME_DATE|TIME_SECONDS), " (broker ", utcOffset, ")\n",
      "Bar Index  : ", curBarIdx, " (target: bar #", targetBarIdx, " = ", InpMarketOpenHour, ":00 UTC)\n",
      "State      : ", stateStr,          "\n",
      "Range High : ", highStr,           "\n",
      "Range Low  : ", lowStr,            "\n",
      "Composition: ", g_range.composition, "/", InpMinComposition, "\n",
      "Buy Done   : ", g_range.buyDone  ? "Yes" : "No", "\n",
      "Sell Done  : ", g_range.sellDone ? "Yes" : "No", "\n",
      "Balance    : ", AccountInfoDouble(ACCOUNT_BALANCE), "\n",
      "Equity     : ", AccountInfoDouble(ACCOUNT_EQUITY)
   );
}
