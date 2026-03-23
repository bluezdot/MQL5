//+------------------------------------------------------------------+
//|                                          AlphaTrendBot.mq5   |
//|   AlphaTrend Bot – S/R Monitor + AlphaTrend Engine               |
//|   Phase 1: S/R & AlphaTrend drawing via OnTimer                  |
//+------------------------------------------------------------------+
#property copyright "AlphaTrend Bot"
#property version   "2.00"
#property description "AlphaTrend DCA Expert Advisor - v2.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//=== Input parameters =============================================

input group "=== S/R Settings ==="
input int       InpSR_Lookback     = 100;      // S/R Lookback candles (n)
input ENUM_TIMEFRAMES InpSR_TF     = PERIOD_M5; // S/R Timeframe
input color     InpResistColor     = clrRed;     // Resistance line color
input color     InpSupportColor    = clrDodgerBlue;   // Support line color
input color     InpSR_AvgColor     = clrGold;    // S/R Average line color
input int       InpSR_LineWidth    = 2;          // S/R line width
input ENUM_LINE_STYLE InpSR_LineStyle = STYLE_SOLID; // S/R line style

input group "=== Position Sizing ==="
input double InpBaseLot      = 0.01; // Base lot (Fibonacci level 0)
input int    InpMaxDCA       = 9;    // Max DCA levels (incl. initial entry)

input group "=== DCA Grid ==="
input int    InpGrid         = 100;  // Minimum grid floor (Points)

input group "=== Take Profit ==="
input double InpTpMax        = 1.5;  // TP multiplier at level 1 (fewest positions)
input double InpTpMin        = 1.05; // TP multiplier at max DCA (most positions)

input group "=== Stop Loss ==="
input int    InpSLCandle     = 12;   // SL candle lookback
input int    InpSLPoint      = 10;   // Extra SL buffer beyond candle extreme (Points)
input int    InpSLFlex       = 50;   // SL flex tolerance (Points)

input group "=== Signal Confirmation ==="
input int    InpConfirmBars  = 2;    // Bars trend must persist before entry

input group "=== Risk Control ==="
input bool   InpCloseOnRev   = true;  // Liquidate basket immediately on reversal signal
input bool   InpUseSL        = true;  // Use hard Stop Loss on all positions

input group "=== AlphaTrend Settings ==="
input double    InpATCoeff         = 1.0;        // AT Multiplier
input int       InpATPeriod        = 14;         // AT Period
input bool      InpATNoVol         = false;      // Use RSI instead of MFI
input int       InpAT_DrawBars     = 300;        // AT bars to calculate

input group "=== EA Settings ==="
input int       InpMagic           = 2;
input bool      InpPrintLog        = true;

//=== Object name prefixes =========================================
#define SR_PREFIX       "AlphaBot_SR_"
#define OBJ_RESIST      SR_PREFIX "Resist"
#define OBJ_SUPPORT     SR_PREFIX "Support"
#define OBJ_SR_AVG      SR_PREFIX "Average"
#define OBJ_RESIST_LBL  SR_PREFIX "ResistLbl"
#define OBJ_SUPPORT_LBL SR_PREFIX "SupportLbl"
#define OBJ_SR_AVG_LBL  SR_PREFIX "AvgLbl"

#define AT_PREFIX       "AlphaBot_AT_"
#define AT_LINE_PREFIX  AT_PREFIX "Line_"
#define AT_BUY_PREFIX   AT_PREFIX "Buy_"
#define AT_SELL_PREFIX  AT_PREFIX "Sell_"
#define AT_DIR_LABEL    AT_PREFIX "DirLabel"

//=== Global objects ===============================================
CTrade        g_trade;
CPositionInfo g_pos;
COrderInfo    g_ord;

int           g_oscHandle      = INVALID_HANDLE;  // MFI or RSI handle for AT calc
datetime      g_lastBarTime    = 0;

// Signal confirmation state
int      g_pendingDir    = 0;   // +1 = BUY pending, -1 = SELL pending, 0 = none
int      g_pendingCount  = 0;   // how many bars this pending direction has held

// Basket state
bool     g_inTrade       = false;
int      g_tradeDir      = 0;   // +1 = BUY basket active, -1 = SELL basket active
double   g_dynamicGrid   = 0;   // Auto-computed grid size for current basket (in price units)

//=== AlphaTrend Global State (available for trading logic) ========
// Core AT arrays – recalculated in OnTimer, stored for multi-purpose use
double        g_atValues[];     // AlphaTrend line values [0..DrawBars-1] (oldest→newest)
double        g_atATR[];        // SMA(TrueRange) values  [0..DrawBars-1]
double        g_atColor[];      // 0=bull, 1=bear per bar [0..DrawBars-1]
datetime      g_atTimes[];      // Bar open times         [0..DrawBars-1]

// Latest AT snapshot – single values for quick access
double        g_atCurrent      = 0.0;   // AT value of last completed bar
double        g_atPrev         = 0.0;   // AT value 1 bar before current
double        g_atrCurrent     = 0.0;   // ATR (SMA of TR) of last completed bar
int           g_atDirection    = 0;     // +1=bullish (green), -1=bearish (red), 0=unknown
int           g_atSignal       = 0;     // Latest signal: +1=BUY, -1=SELL, 0=none
datetime      g_atSignalTime   = 0;     // Time of latest signal bar
double        g_atSignalPrice  = 0.0;   // Price level of latest signal
bool          g_atInitialized  = false;  // Whether AT has been computed at least once
int           g_atLastBuyIdx   = -1;    // Index of last buy signal in AT arrays
int           g_atLastSellIdx  = -1;    // Index of last sell signal in AT arrays

//=== S/R Global State (cached for reuse) ==========================
// Cached highest/lowest values and their bar times
double        g_resistance     = 0.0;    // Current resistance (highest high of n bars)
double        g_support        = 0.0;    // Current support (lowest low of n bars)
double        g_srAverage      = 0.0;    // (Resistance + Support) / 2
datetime      g_resistTime     = 0;      // Time of the bar that formed resistance
datetime      g_supportTime    = 0;      // Time of the bar that formed support
datetime      g_srCalcTime     = 0;      // Last time S/R was fully recalculated
bool          g_srInitialized  = false;  // Whether S/R has been computed at least once

// Cache window: store the oldest bar time in the lookback window
// If the cached peak/valley falls outside the window → full recalc
datetime      g_windowOldest   = 0;      // Oldest bar time in current lookback window

//+------------------------------------------------------------------+
//| Log helper                                                        |
//+------------------------------------------------------------------+
void Log(string msg)
{
   if(InpPrintLog)
      PrintFormat("[AlphaBot] %s | %s",
                  TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), msg);
}

//+------------------------------------------------------------------+
//| Normalize lot                                                     |
//+------------------------------------------------------------------+
double NormLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   return MathMax(mn, MathMin(mx, MathRound(lot / step) * step));
}

//+------------------------------------------------------------------+
//| Fibonacci number (0-indexed): F(0)=1,F(1)=1,F(2)=2,F(3)=3,...   |
//+------------------------------------------------------------------+
double FibNum(int n)
{
   if(n <= 1) return 1.0;
   double a = 1.0, b = 1.0, c;
   for(int i = 2; i <= n; i++) { c = a + b; a = b; b = c; }
   return b;
}

//+------------------------------------------------------------------+
//| Count open positions by direction (-1 = any)                      |
//+------------------------------------------------------------------+
int CountPos(int typeFilter = -1)
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(g_pos.SelectByIndex(i) && g_pos.Symbol() == _Symbol && g_pos.Magic() == InpMagic)
         if(typeFilter == -1
            || (typeFilter == ORDER_TYPE_BUY  && g_pos.PositionType() == POSITION_TYPE_BUY)
            || (typeFilter == ORDER_TYPE_SELL && g_pos.PositionType() == POSITION_TYPE_SELL))
            cnt++;
   return cnt;
}

//+------------------------------------------------------------------+
//| Close ALL our positions                                           |
//+------------------------------------------------------------------+
void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(g_pos.SelectByIndex(i) && g_pos.Symbol() == _Symbol && g_pos.Magic() == InpMagic)
         if(!g_trade.PositionClose(g_pos.Ticket()))
            Log(StringFormat("CloseAll FAILED ticket=%d err=%d", g_pos.Ticket(), GetLastError()));
}

//+------------------------------------------------------------------+
//| Delete ALL pending limit orders                                   |
//+------------------------------------------------------------------+
void DeleteAllOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(g_ord.SelectByIndex(i) && g_ord.Symbol() == _Symbol && g_ord.Magic() == InpMagic)
         if(!g_trade.OrderDelete(g_ord.Ticket()))
            Log(StringFormat("DeleteOrder FAILED ticket=%d err=%d", g_ord.Ticket(), GetLastError()));
}

//+------------------------------------------------------------------+
//| Close basket + delete pending orders + reset state               |
//+------------------------------------------------------------------+
void ResetBasket(string reason)
{
   Log(StringFormat("ResetBasket: %s", reason));
   CloseAll();
   DeleteAllOrders();
   g_inTrade      = false;
   g_tradeDir     = 0;
}

//+------------------------------------------------------------------+
//| Compute SL price                                                  |
//+------------------------------------------------------------------+
double GetSL(bool isBuy)
{
   if(!InpUseSL) return 0.0;
   double sl = isBuy ? DBL_MAX : 0.0;
   for(int i = 1; i <= InpSLCandle; i++)
      sl = isBuy ? MathMin(sl, iLow(_Symbol, PERIOD_CURRENT, i))
                 : MathMax(sl, iHigh(_Symbol, PERIOD_CURRENT, i));
   sl += isBuy ? -(InpSLPoint + InpSLFlex) * _Point
               :  (InpSLPoint + InpSLFlex) * _Point;
   return NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
//| Basket weighted-average statistics                               |
//+------------------------------------------------------------------+
bool GetBasketStats(bool isBuy, double &avgEntry, double &totalLots, double &totalProfit)
{
   double sumLP  = 0.0;
   totalLots     = 0.0;
   totalProfit   = 0.0;
   ENUM_POSITION_TYPE pt = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(g_pos.SelectByIndex(i) && g_pos.Symbol() == _Symbol && g_pos.Magic() == InpMagic
         && g_pos.PositionType() == pt)
      {
         sumLP       += g_pos.PriceOpen() * g_pos.Volume();
         totalLots   += g_pos.Volume();
         totalProfit += g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
      }
   if(totalLots <= 0) return false;
   avgEntry = sumLP / totalLots;
   return true;
}

//+------------------------------------------------------------------+
//| Check if basket reached TP                                       |
//+------------------------------------------------------------------+
bool CheckBasketTP(bool isBuy)
{
   double avgEntry, totalLots, totalProfit;
   if(!GetBasketStats(isBuy, avgEntry, totalLots, totalProfit)) return false;

   int n = CountPos(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(n <= 0) return false;

   double tpRatio;
   if(InpMaxDCA <= 1 || n <= 1)
      tpRatio = InpTpMax;
   else
      tpRatio = InpTpMax - (InpTpMax - InpTpMin) * (double)(n - 1) / (double)(InpMaxDCA - 1);
   tpRatio = MathMax(tpRatio, InpTpMin);

   double tpDist  = tpRatio * g_dynamicGrid;
   double tpPrice = isBuy ? avgEntry + tpDist : avgEntry - tpDist;
   double cur     = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   bool hit = isBuy ? (cur >= tpPrice) : (cur <= tpPrice);
   if(hit)
      Log(StringFormat("BasketTP n=%d ratio=%.2f avg=%.5f tp=%.5f cur=%.5f PnL=%.2f",
                       n, tpRatio, avgEntry, tpPrice, cur, totalProfit));
   return hit;
}

//+------------------------------------------------------------------+
//| Enter DCA basket                                                  |
//+------------------------------------------------------------------+
void EnterBasket(bool isBuy)
{
   double entry = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl    = GetSL(isBuy);

   // Enforce minimum SL distance
   double stopMin = (double)(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 3) * _Point;
   if(InpUseSL)
   {
      if(isBuy  && entry - sl < stopMin) sl = NormalizeDouble(entry - stopMin, _Digits);
      if(!isBuy && sl - entry < stopMin) sl = NormalizeDouble(entry + stopMin, _Digits);
   }

   // Auto-compute dynamic grid
   double extreme = entry;
   for(int i = 1; i <= InpSLCandle; i++)
      extreme = isBuy ? MathMin(extreme, iLow(_Symbol,  PERIOD_CURRENT, i))
                      : MathMax(extreme, iHigh(_Symbol, PERIOD_CURRENT, i));
   double range = MathAbs(entry - extreme);
   g_dynamicGrid = MathMax(range / InpMaxDCA, InpGrid * _Point);

   // Fibonacci lot weights
   double fib[];
   ArrayResize(fib, InpMaxDCA);
   for(int i = 0; i < InpMaxDCA; i++) fib[i] = FibNum(i);

   Log(StringFormat("EnterBasket %s entry=%.5f sl=%.5f SLrange=%.0fpts dynGrid=%.0fpts",
                    isBuy ? "BUY" : "SELL", entry, sl,
                    range / _Point, g_dynamicGrid / _Point));

   // Level 0 – market
   double lot0 = NormLot(InpBaseLot * fib[0]);
   bool ok = isBuy ? g_trade.Buy(lot0,  _Symbol, 0, sl, 0, "AT_DCA_B_0")
                   : g_trade.Sell(lot0, _Symbol, 0, sl, 0, "AT_DCA_S_0");
   if(!ok) Log(StringFormat("  L0 MARKET FAILED err=%d", GetLastError()));
   else    Log(StringFormat("  L0 market lot=%.2f sl=%.5f", lot0, sl));

   // Levels 1..MaxDCA-1 – evenly spaced by g_dynamicGrid
   double stopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   for(int i = 1; i < InpMaxDCA; i++)
   {
      double offset   = g_dynamicGrid * i;
      double dcaPrice = isBuy ? NormalizeDouble(entry - offset, _Digits)
                               : NormalizeDouble(entry + offset, _Digits);

      if(isBuy  && entry - dcaPrice <= stopLevel) continue;
      if(!isBuy && dcaPrice - entry <= stopLevel) continue;

      double lotI = NormLot(InpBaseLot * fib[i]);
      string cmt  = StringFormat("AT_DCA_%s_%d", isBuy ? "B" : "S", i);

      ok = isBuy ? g_trade.BuyLimit(lotI,  dcaPrice, _Symbol, sl, 0, ORDER_TIME_GTC, 0, cmt)
                 : g_trade.SellLimit(lotI, dcaPrice, _Symbol, sl, 0, ORDER_TIME_GTC, 0, cmt);
      if(!ok) Log(StringFormat("  L%d LIMIT FAILED err=%d price=%.5f lot=%.2f", i, GetLastError(), dcaPrice, lotI));
      else    Log(StringFormat("  L%d limit=%.5f offset=%.0fpts lot=%.2f", i, dcaPrice, offset / _Point, lotI));
   }

   g_inTrade  = true;
   g_tradeDir = isBuy ? 1 : -1;
}

//+------------------------------------------------------------------+
//| Create or move a horizontal line                                  |
//+------------------------------------------------------------------+
void DrawHLine(string name, double price, color clr, int width, ENUM_LINE_STYLE style, string tooltip = "")
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
   }
   else
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
   }
}

//+------------------------------------------------------------------+
//| Create or update a price label (right side of chart)              |
//+------------------------------------------------------------------+
void DrawPriceLabel(string name, double price, color clr, string text)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_ARROW_RIGHT_PRICE, 0, TimeCurrent(), price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }
   else
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      ObjectMove(0, name, 0, TimeCurrent(), price);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }
}

//+------------------------------------------------------------------+
//| Delete all S/R objects from chart                                 |
//+------------------------------------------------------------------+
void DeleteSRObjects()
{
   ObjectsDeleteAll(0, SR_PREFIX);
}

//+------------------------------------------------------------------+
//| Delete all AlphaTrend objects from chart                          |
//+------------------------------------------------------------------+
void DeleteATObjects()
{
   ObjectsDeleteAll(0, AT_PREFIX);
}

//+------------------------------------------------------------------+
//| Full recalculation of S/R from n candles                         |
//| Scans all InpSR_Lookback bars and finds the absolute high/low    |
//+------------------------------------------------------------------+
bool FullRecalcSR()
{
   double highs[], lows[];
   datetime times[];
   
   int copied_h = CopyHigh(_Symbol, InpSR_TF, 1, InpSR_Lookback, highs);
   int copied_l = CopyLow(_Symbol, InpSR_TF, 1, InpSR_Lookback, lows);
   int copied_t = CopyTime(_Symbol, InpSR_TF, 1, InpSR_Lookback, times);
   
   if(copied_h < InpSR_Lookback || copied_l < InpSR_Lookback || copied_t < InpSR_Lookback)
   {
      Log(StringFormat("FullRecalcSR: Not enough data. H=%d L=%d T=%d need=%d",
                       copied_h, copied_l, copied_t, InpSR_Lookback));
      return false;
   }
   
   // Find highest high and lowest low
   double maxH = highs[0];
   double minL = lows[0];
   int    maxIdx = 0;
   int    minIdx = 0;

   for(int i = 1; i < InpSR_Lookback; i++)
   {
      if(highs[i] > maxH)
      {
         maxH   = highs[i];
         maxIdx = i;
      }
      if(lows[i] < minL)
      {
         minL   = lows[i];
         minIdx = i;
      }
   }
   
   // Update global cached values
   g_resistance   = maxH;
   g_support      = minL;
   g_srAverage    = NormalizeDouble((maxH + minL) / 2.0, _Digits);
   g_resistTime   = times[maxIdx];
   g_supportTime  = times[minIdx];
   g_windowOldest = times[0];
   g_srCalcTime   = TimeCurrent();
   g_srInitialized = true;
   
   Log(StringFormat("FullRecalcSR: R=%.5f [%s] S=%.5f [%s] Avg=%.5f Window=%s..now",
       g_resistance, TimeToString(g_resistTime, TIME_DATE|TIME_MINUTES),
       g_support,    TimeToString(g_supportTime, TIME_DATE|TIME_MINUTES),
       g_srAverage,  TimeToString(g_windowOldest, TIME_DATE|TIME_MINUTES)));
   
   return true;
}

//+------------------------------------------------------------------+
//| Incremental S/R update (optimized)                                |
//| Only checks if the newest bar creates a new peak/valley           |
//| or if the cached peak/valley has expired (out of window)          |
//| Returns true if values changed, false if unchanged                |
//+------------------------------------------------------------------+
bool IncrementalUpdateSR()
{
   // If not initialized, do full recalc
   if(!g_srInitialized)
      return FullRecalcSR();
   
   // Get the oldest bar's time in the current lookback window
   datetime windowTimes[];
   int copied_t = CopyTime(_Symbol, InpSR_TF, 1, 1, windowTimes);
   if(copied_t < 1) return false;
   
   // Get the newest bar (index 1 = last completed bar)
   datetime newestTime[];
   double   newestHigh[], newestLow[];
   copied_t      = CopyTime(_Symbol, InpSR_TF, 1, 1, newestTime);
   int copied_h  = CopyHigh(_Symbol, InpSR_TF, 1, 1, newestHigh);
   int copied_l  = CopyLow(_Symbol, InpSR_TF, 1, 1, newestLow);
   if(copied_t < 1 || copied_h < 1 || copied_l < 1) return false;
   
   // Get the oldest bar time in current window
   datetime oldestTime[];
   CopyTime(_Symbol, InpSR_TF, InpSR_Lookback, 1, oldestTime);
   if(ArraySize(oldestTime) < 1) return false;
   
   g_windowOldest = oldestTime[0];
   
   // ---- Check if cached peaks/valleys are still in the window ----
   bool resistExpired  = (g_resistTime < g_windowOldest);
   bool supportExpired = (g_supportTime < g_windowOldest);
   
   // If any cached value expired → full recalc needed
   if(resistExpired || supportExpired)
   {
      Log(StringFormat("IncrementalSR: Cache expired (R_exp=%s S_exp=%s) → full recalc",
                       resistExpired ? "YES" : "NO", supportExpired ? "YES" : "NO"));
      return FullRecalcSR();
   }
   
   // ---- Check if the newest bar creates a new peak or valley ----
   bool changed = false;
   
   if(newestHigh[0] > g_resistance)
   {
      g_resistance = newestHigh[0];
      g_resistTime = newestTime[0];
      changed = true;
      Log(StringFormat("IncrementalSR: New Resistance=%.5f at %s",
          g_resistance, TimeToString(g_resistTime, TIME_DATE|TIME_MINUTES)));
   }
   
   if(newestLow[0] < g_support)
   {
      g_support    = newestLow[0];
      g_supportTime = newestTime[0];
      changed = true;
      Log(StringFormat("IncrementalSR: New Support=%.5f at %s",
          g_support, TimeToString(g_supportTime, TIME_DATE|TIME_MINUTES)));
   }
   
   if(changed)
   {
      g_srAverage = NormalizeDouble((g_resistance + g_support) / 2.0, _Digits);
      g_srCalcTime = TimeCurrent();
   }
   
   return changed;
}

//+------------------------------------------------------------------+
//| Calculate AlphaTrend from raw OHLC data (no external indicator)   |
//| Populates g_atValues[], g_atATR[], g_atColor[], g_atTimes[]       |
//| and sets all g_at* snapshot globals                               |
//+------------------------------------------------------------------+
bool CalcAlphaTrend()
{
   int bars = InpAT_DrawBars;
   // Need extra bars for seed + lookback: period + 4 bars before draw window
   int need = bars + InpATPeriod + 4;
   
   double highs[], lows[], closes[];
   datetime times[];
   
   int ch = CopyHigh (_Symbol, PERIOD_CURRENT, 0, need, highs);
   int cl = CopyLow  (_Symbol, PERIOD_CURRENT, 0, need, lows);
   int cc = CopyClose(_Symbol, PERIOD_CURRENT, 0, need, closes);
   int ct = CopyTime (_Symbol, PERIOD_CURRENT, 0, need, times);
   
   if(ch < need || cl < need || cc < need || ct < need)
   {
      Log(StringFormat("CalcAT: Not enough data. H=%d L=%d C=%d T=%d need=%d",
                       ch, cl, cc, ct, need));
      return false;
   }
   
   // Copy oscillator (MFI or RSI) values
   double oscBuf[];
   if(CopyBuffer(g_oscHandle, 0, 0, need, oscBuf) < need)
   {
      Log("CalcAT: Oscillator data not ready");
      return false;
   }
   
   // --- Compute AT for all 'need' bars ---
   double atFull[], atrFull[];
   ArrayResize(atFull, need);
   ArrayResize(atrFull, need);
   ArrayInitialize(atFull, 0.0);
   ArrayInitialize(atrFull, 0.0);
   
   // Seed
   int seedBar = InpATPeriod;
   atFull[seedBar] = closes[seedBar];
   
   for(int i = seedBar; i < need; i++)
   {
      // SMA of True Range over InpATPeriod
      double trSum = 0.0;
      bool valid = true;
      for(int j = 0; j < InpATPeriod; j++)
      {
         int k = i - j;
         if(k < 1) { valid = false; break; }
         double tr = MathMax(highs[k] - lows[k],
                    MathMax(MathAbs(highs[k] - closes[k - 1]),
                            MathAbs(lows[k]  - closes[k - 1])));
         trSum += tr;
      }
      if(!valid) { atrFull[i] = 0; continue; }
      atrFull[i] = trSum / InpATPeriod;
      
      double upT   = lows[i]  - atrFull[i] * InpATCoeff;
      double downT = highs[i] + atrFull[i] * InpATCoeff;
      double prevAT = (i > seedBar) ? atFull[i - 1] : closes[i];
      
      bool bullish = (oscBuf[i] >= 50.0);
      if(bullish)
         atFull[i] = (upT < prevAT) ? prevAT : upT;
      else
         atFull[i] = (downT > prevAT) ? prevAT : downT;
   }
   
   // --- Extract the last 'bars' values into global arrays ---
   int offset = need - bars;  // start index in full arrays
   ArrayResize(g_atValues, bars);
   ArrayResize(g_atATR,    bars);
   ArrayResize(g_atColor,  bars);
   ArrayResize(g_atTimes,  bars);
   
   for(int i = 0; i < bars; i++)
   {
      int fi = offset + i;
      g_atValues[i] = atFull[fi];
      g_atATR[i]    = atrFull[fi];
      g_atTimes[i]  = times[fi];
      
      // Color: compare AT[i] vs AT[i-2]
      if(fi >= 2)
      {
         if(atFull[fi] > atFull[fi - 2])
            g_atColor[i] = 0; // bullish
         else if(atFull[fi] < atFull[fi - 2])
            g_atColor[i] = 1; // bearish
         else
         {
            // Tie: inherit from previous
            if(fi >= 3)
               g_atColor[i] = (atFull[fi - 1] > atFull[fi - 3]) ? 0.0 : 1.0;
            else
               g_atColor[i] = 0;
         }
      }
      else
         g_atColor[i] = 0;
   }
   
   // --- Buy/Sell signal detection (alternating filter) ---
   g_atLastBuyIdx  = -1;
   g_atLastSellIdx = -1;
   int lastBuy = -1, lastSell = -1;  // indices in full array
   
   // Scan full array to find signals
   int sigStart = InpATPeriod + 3;
   for(int i = sigStart; i < need; i++)
   {
      if(i < 3) continue;
      
      bool buySignal  = (atFull[i] >  atFull[i - 2]) && (atFull[i - 1] <= atFull[i - 3]);
      bool sellSignal = (atFull[i] <  atFull[i - 2]) && (atFull[i - 1] >= atFull[i - 3]);
      
      if(buySignal)
      {
         int O1 = (lastBuy  >= 0) ? (i - lastBuy)  : INT_MAX;
         int K2 = (lastSell >= 0) ? (i - lastSell) : INT_MAX;
         if(O1 > K2)  // alternating filter: buy only after sell
         {
            // Map to local array index
            int li = i - offset;
            if(li >= 0 && li < bars)
               g_atLastBuyIdx = li;
         }
         lastBuy = i;
      }
      
      if(sellSignal)
      {
         int O2 = (lastSell >= 0) ? (i - lastSell) : INT_MAX;
         int K1 = (lastBuy  >= 0) ? (i - lastBuy)  : INT_MAX;
         if(O2 > K1)  // alternating filter: sell only after buy
         {
            int li = i - offset;
            if(li >= 0 && li < bars)
               g_atLastSellIdx = li;
         }
         lastSell = i;
      }
   }
   
   // --- Set snapshot globals ---
   // Last completed bar = bars-2 (index bars-1 is current forming bar)
   int last = bars - 2;
   if(last < 1) last = 1;
   g_atCurrent   = g_atValues[last];
   g_atPrev      = g_atValues[last - 1];
   g_atrCurrent  = g_atATR[last];
   
   // Direction from color
   if(g_atColor[last] == 0)
      g_atDirection = 1;   // bullish
   else if(g_atColor[last] == 1)
      g_atDirection = -1;  // bearish
   else
      g_atDirection = 0;
   
   // Latest signal: which came later, buy or sell?
   if(g_atLastBuyIdx > g_atLastSellIdx)
   {
      g_atSignal      = 1;
      g_atSignalTime  = g_atTimes[g_atLastBuyIdx];
      g_atSignalPrice = g_atValues[MathMax(0, g_atLastBuyIdx - 2)];
   }
   else if(g_atLastSellIdx > g_atLastBuyIdx)
   {
      g_atSignal      = -1;
      g_atSignalTime  = g_atTimes[g_atLastSellIdx];
      g_atSignalPrice = g_atValues[MathMax(0, g_atLastSellIdx - 2)];
   }
   else
   {
      g_atSignal      = 0;
      g_atSignalTime  = 0;
      g_atSignalPrice = 0;
   }
   
   g_atInitialized = true;
   return true;
}

//+------------------------------------------------------------------+
//| Draw AlphaTrend BUY/SELL signal labels on chart                   |
//+------------------------------------------------------------------+
void DrawAlphaTrendOnChart()
{
   if(!g_atInitialized) return;
   int bars = ArraySize(g_atValues);
   if(bars < 3) return;
   
   // Delete old signal labels
   ObjectsDeleteAll(0, AT_BUY_PREFIX);
   ObjectsDeleteAll(0, AT_SELL_PREFIX);
   
   // Draw latest Buy signal label
   if(g_atLastBuyIdx >= 2 && g_atLastBuyIdx < bars)
   {
      string bName = AT_BUY_PREFIX + "last";
      double bPrice = g_atValues[g_atLastBuyIdx - 2] * 0.9999;
      datetime bTime = g_atTimes[g_atLastBuyIdx];
      
      ObjectDelete(0, bName);
      if(ObjectCreate(0, bName, OBJ_TEXT, 0, bTime, bPrice))
      {
         ObjectSetString (0, bName, OBJPROP_TEXT,       "BUY");
         ObjectSetString (0, bName, OBJPROP_FONT,       "Arial Bold");
         ObjectSetInteger(0, bName, OBJPROP_FONTSIZE,   10);
         ObjectSetInteger(0, bName, OBJPROP_COLOR,      clrLime);
         ObjectSetInteger(0, bName, OBJPROP_ANCHOR,     ANCHOR_TOP);
         ObjectSetInteger(0, bName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, bName, OBJPROP_HIDDEN,     true);
      }
   }
   
   // Draw latest Sell signal label
   if(g_atLastSellIdx >= 2 && g_atLastSellIdx < bars)
   {
      string sName = AT_SELL_PREFIX + "last";
      double sPrice = g_atValues[g_atLastSellIdx - 2] * 1.0001;
      datetime sTime = g_atTimes[g_atLastSellIdx];
      
      ObjectDelete(0, sName);
      if(ObjectCreate(0, sName, OBJ_TEXT, 0, sTime, sPrice))
      {
         ObjectSetString (0, sName, OBJPROP_TEXT,       "SELL");
         ObjectSetString (0, sName, OBJPROP_FONT,       "Arial Bold");
         ObjectSetInteger(0, sName, OBJPROP_FONTSIZE,   10);
         ObjectSetInteger(0, sName, OBJPROP_COLOR,      clrRed);
         ObjectSetInteger(0, sName, OBJPROP_ANCHOR,     ANCHOR_BOTTOM);
         ObjectSetInteger(0, sName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, sName, OBJPROP_HIDDEN,     true);
      }
   }
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw S/R lines and labels on chart                                |
//+------------------------------------------------------------------+
void DrawSROnChart()
{
   if(!g_srInitialized) return;
   
   string rTooltip = StringFormat("Resistance: %.5f\nTime: %s\nLookback: %d bars on %s",
                      g_resistance, TimeToString(g_resistTime, TIME_DATE|TIME_MINUTES),
                      InpSR_Lookback, EnumToString(InpSR_TF));
   
   string sTooltip = StringFormat("Support: %.5f\nTime: %s\nLookback: %d bars on %s",
                      g_support, TimeToString(g_supportTime, TIME_DATE|TIME_MINUTES),
                      InpSR_Lookback, EnumToString(InpSR_TF));
   
   string aTooltip = StringFormat("S/R Average: %.5f\n(R=%.5f + S=%.5f) / 2",
                      g_srAverage, g_resistance, g_support);
   
   // Draw horizontal lines
   DrawHLine(OBJ_RESIST,  g_resistance, InpResistColor,  InpSR_LineWidth, InpSR_LineStyle, rTooltip);
   DrawHLine(OBJ_SUPPORT, g_support,    InpSupportColor, InpSR_LineWidth, InpSR_LineStyle, sTooltip);
   DrawHLine(OBJ_SR_AVG,  g_srAverage,  InpSR_AvgColor,  1, STYLE_DASH, aTooltip);
   
   // Draw price labels (right side of chart)
   DrawPriceLabel(OBJ_RESIST_LBL,  g_resistance, InpResistColor,
                  StringFormat("R %.5f", g_resistance));
   DrawPriceLabel(OBJ_SUPPORT_LBL, g_support,    InpSupportColor,
                  StringFormat("S %.5f", g_support));
   DrawPriceLabel(OBJ_SR_AVG_LBL,  g_srAverage,  InpSR_AvgColor,
                  StringFormat("Avg %.5f", g_srAverage));
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw info panel on chart (top-left corner)                        |
//+------------------------------------------------------------------+
void DrawInfoPanel()
{
   if(!g_srInitialized) return;
   
   string panelName = SR_PREFIX + "Panel";
   double spread  = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double rDist   = (g_resistance - bid) / _Point;
   double sDist   = (bid - g_support) / _Point;
   
   // AlphaTrend info
   string atDir   = (g_atDirection == 1) ? "BULL" : (g_atDirection == -1) ? "BEAR" : "---";
   string atSig   = (g_atSignal == 1) ? "BUY" : (g_atSignal == -1) ? "SELL" : "---";
   string atSigTm = (g_atSignalTime > 0) ? TimeToString(g_atSignalTime, TIME_DATE|TIME_MINUTES) : "---";
   
   // Basket PnL
   double basketAvg, basketLots, basketPnl;
   basketPnl = 0.0;
   if(g_inTrade)
      GetBasketStats(g_tradeDir == 1, basketAvg, basketLots, basketPnl);
   
   string info = StringFormat(
      "━━━ S/R Monitor ━━━\n"
      "R: %.5f  (%.0f pts)\n"
      "S: %.5f  (%.0f pts)\n"
      "Avg: %.5f\n"
      "Range: %.0f pts\n"
      "Spread: %.1f pts\n"
      "TF: %s | Bars: %d\n"
      "R time: %s\n"
      "S time: %s\n"
      "━━━ AlphaTrend ━━━\n"
      "AT: %.5f | ATR: %.5f\n"
      "Dir: %s | Signal: %s\n"
      "Sig time: %s\n"
      "Sig price: %.5f\n"
      "━━━ DCA Basket ━━━\n"
      "Trade: %s | Dir: %s\n"
      "Positions: %d\n"
      "Grid: %.0f pts\n"
      "PnL: %.2f\n"
      "Updated: %s",
      g_resistance, rDist,
      g_support, sDist,
      g_srAverage,
      (g_resistance - g_support) / _Point,
      spread / _Point,
      EnumToString(InpSR_TF), InpSR_Lookback,
      TimeToString(g_resistTime, TIME_DATE|TIME_MINUTES),
      TimeToString(g_supportTime, TIME_DATE|TIME_MINUTES),
      g_atCurrent, g_atrCurrent,
      atDir, atSig,
      atSigTm,
      g_atSignalPrice,
      g_inTrade ? "ACTIVE" : "IDLE",
      g_tradeDir == 1 ? "BUY" : (g_tradeDir == -1 ? "SELL" : "---"),
      CountPos(-1),
      g_dynamicGrid / _Point,
      basketPnl,
      TimeToString(g_srCalcTime, TIME_MINUTES)
   );
   
   if(ObjectFind(0, panelName) < 0)
   {
      ObjectCreate(0, panelName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, panelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, panelName, OBJPROP_XDISTANCE, 15);
      ObjectSetInteger(0, panelName, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, panelName, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, panelName, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, panelName, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, panelName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, panelName, OBJPROP_BACK, false);
   }
   ObjectSetString(0, panelName, OBJPROP_TEXT, info);
   
   // --- Large direction label (top-right corner) ---
   string dirText;
   color  dirColor;
   if(g_atSignal == 1)
   {
      dirText  = "▲ BUY";
      dirColor = clrLime;
   }
   else if(g_atSignal == -1)
   {
      dirText  = "▼ SELL";
      dirColor = clrRed;
   }
   else
   {
      dirText  = "― WAIT";
      dirColor = clrGray;
   }
   
   if(ObjectFind(0, AT_DIR_LABEL) < 0)
   {
      ObjectCreate(0, AT_DIR_LABEL, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, AT_DIR_LABEL, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, AT_DIR_LABEL, OBJPROP_XDISTANCE, 15);
      ObjectSetInteger(0, AT_DIR_LABEL, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, AT_DIR_LABEL, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, AT_DIR_LABEL, OBJPROP_FONTSIZE, 20);
      ObjectSetString (0, AT_DIR_LABEL, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, AT_DIR_LABEL, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, AT_DIR_LABEL, OBJPROP_BACK, false);
   }
   ObjectSetString (0, AT_DIR_LABEL, OBJPROP_TEXT, dirText);
   ObjectSetInteger(0, AT_DIR_LABEL, OBJPROP_COLOR, dirColor);
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Create oscillator handle for AlphaTrend calculation (MFI or RSI)
   if(InpATNoVol)
      g_oscHandle = iRSI(_Symbol, PERIOD_CURRENT, InpATPeriod, PRICE_CLOSE);
   else
      g_oscHandle = iMFI(_Symbol, PERIOD_CURRENT, InpATPeriod, VOLUME_TICK);
   
   if(g_oscHandle == INVALID_HANDLE)
   {
      Alert("AlphaTrendBot: Cannot create oscillator handle! Error=", GetLastError());
      return INIT_FAILED;
   }


   // Initialize DCA state
   g_pendingDir   = 0;
   g_pendingCount = 0;
   g_inTrade      = false;
   g_tradeDir     = 0;
   g_dynamicGrid  = 0;

   // Initialize S/R state
   g_resistance    = 0.0;
   g_support       = 0.0;
   g_srAverage     = 0.0;
   g_resistTime    = 0;
   g_supportTime   = 0;
   g_srCalcTime    = 0;
   g_srInitialized = false;
   g_windowOldest  = 0;
   
   // Initialize AT state
   g_atCurrent     = 0.0;
   g_atPrev        = 0.0;
   g_atrCurrent    = 0.0;
   g_atDirection   = 0;
   g_atSignal      = 0;
   g_atSignalTime  = 0;
   g_atSignalPrice = 0.0;
   g_atInitialized = false;
   g_atLastBuyIdx  = -1;
   g_atLastSellIdx = -1;
   
   // First full S/R calculation
   if(FullRecalcSR())
   {
      DrawSROnChart();
   }
   
   // First AlphaTrend calculation
   if(CalcAlphaTrend())
   {
      DrawAlphaTrendOnChart();
   }
   
   DrawInfoPanel();
   
   // Set timer to 60 seconds (1 minute) for S/R updates
   EventSetTimer(60);
   
   Log(StringFormat("Init OK | S/R TF=%s Lookback=%d | R=%.5f S=%.5f Avg=%.5f",
       EnumToString(InpSR_TF), InpSR_Lookback,
       g_resistance, g_support, g_srAverage));
   Log(StringFormat("Init OK | AT=%s Period=%d Coeff=%.1f | Dir=%d Signal=%d",
       InpATNoVol ? "RSI" : "MFI", InpATPeriod, InpATCoeff,
       g_atDirection, g_atSignal));
   Log(StringFormat("Init OK | DCA MaxLvl=%d Grid=%d BaseLot=%.2f CloseOnRev=%s UseSL=%s Confirm=%d",
       InpMaxDCA, InpGrid, InpBaseLot,
       InpCloseOnRev ? "YES" : "NO", InpUseSL ? "YES" : "NO", InpConfirmBars));
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(g_oscHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_oscHandle);
      g_oscHandle = INVALID_HANDLE;
   }
   
   // Kill timer
   EventKillTimer();
   
   // Clean up chart objects
   DeleteSRObjects();
   DeleteATObjects();
   
   Log("Deinit – all chart objects removed");
}

//+------------------------------------------------------------------+
//| OnTimer – fires every 60 seconds                                  |
//| Performs incremental S/R update with caching optimization          |
//+------------------------------------------------------------------+
void OnTimer()
{
   // --- S/R: Incremental update with caching optimization ---
   bool srChanged = IncrementalUpdateSR();
   
   // --- AlphaTrend: Full recalc (fast O(DrawBars) scan) ---
   bool atChanged = CalcAlphaTrend();
   
   // Always redraw (update distances from current price, panel info, AT line)
   DrawSROnChart();
   if(atChanged)
      DrawAlphaTrendOnChart();
   DrawInfoPanel();
   
   if(srChanged)
      Log(StringFormat("Timer: S/R updated → R=%.5f S=%.5f Avg=%.5f",
          g_resistance, g_support, g_srAverage));
   if(atChanged)
      Log(StringFormat("Timer: AT updated → AT=%.5f ATR=%.5f Dir=%d Sig=%d",
          g_atCurrent, g_atrCurrent, g_atDirection, g_atSignal));
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool isNewBar    = (barTime != g_lastBarTime);

   // ------------------------------------------------------------------
   // INTRA-BAR: only monitor active basket
   // ------------------------------------------------------------------
   if(!isNewBar)
   {
      if(!g_inTrade) return;
      bool isBuy = (g_tradeDir == 1);

      // All positions closed (SL hit) → re-enter same direction
      if(CountPos(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL) == 0)
      {
         Log(StringFormat("Basket empty (SL hit) – re-entering %s from current price",
                          isBuy ? "BUY" : "SELL"));
         DeleteAllOrders();
         g_inTrade  = false;
         g_tradeDir = 0;
         EnterBasket(isBuy);
         g_pendingDir   = 0;
         g_pendingCount = 0;
         return;
      }

      // Basket TP check every tick
      if(CheckBasketTP(isBuy))
      {
         bool reDir = isBuy;
         ResetBasket("Basket TP reached – re-entering");
         EnterBasket(reDir);
         g_pendingDir   = 0;
         g_pendingCount = 0;
      }
      return;
   }

   // ------------------------------------------------------------------
   // NEW BAR processing
   // ------------------------------------------------------------------
   g_lastBarTime = barTime;

   // Recalculate AlphaTrend on every new bar for fresh signals
   CalcAlphaTrend();

   // Edge-case: basket state says in-trade but all positions closed at bar boundary
   if(g_inTrade && CountPos(g_tradeDir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL) == 0)
   {
      bool reDir = (g_tradeDir == 1);
      Log(StringFormat("Bar-open: basket empty – re-entering %s", reDir ? "BUY" : "SELL"));
      DeleteAllOrders();
      g_inTrade  = false;
      g_tradeDir = 0;
      EnterBasket(reDir);
      g_pendingDir   = 0;
      g_pendingCount = 0;
      return;
   }

   // Read signals from internal AlphaTrend engine
   // Check if a NEW signal appeared on the last completed bar
   bool buySignal  = false;
   bool sellSignal = false;
   
   if(g_atInitialized)
   {
      int bars = ArraySize(g_atValues);
      int lastBar = bars - 2;  // last completed bar index
      if(lastBar >= 3)
      {
         // Crossover detection on the last completed bar
         int fi = lastBar;
         buySignal  = (g_atValues[fi] >  g_atValues[fi - 2]) && (g_atValues[fi - 1] <= g_atValues[fi - 3]);
         sellSignal = (g_atValues[fi] <  g_atValues[fi - 2]) && (g_atValues[fi - 1] >= g_atValues[fi - 3]);
      }
   }
   
   if(buySignal && sellSignal) { Log("Conflicting signals – skip"); return; }

   // ------------------------------------------------------------------
   // RISK CONTROL: reversal signal while in trade
   // ------------------------------------------------------------------
   if(g_inTrade)
   {
      bool isBuy    = (g_tradeDir == 1);
      bool reversal = (isBuy && sellSignal) || (!isBuy && buySignal);

      if(reversal)
      {
         if(InpCloseOnRev)
         {
            bool newDir = !isBuy;
            Log(StringFormat("[RISK] Reversal → liquidate %s, immediately enter %s",
                             isBuy ? "BUY" : "SELL", newDir ? "BUY" : "SELL"));
            ResetBasket("Reversal liquidation");
            EnterBasket(newDir);
            g_pendingDir   = 0;
            g_pendingCount = 0;
         }
         else
         {
            double avg, lots, pnl;
            GetBasketStats(isBuy, avg, lots, pnl);
            Log(StringFormat("[RISK] Reversal (CloseOnRev=OFF) – basket PnL=%.2f", pnl));
         }
         return;
      }
   }

   // ------------------------------------------------------------------
   // Update confirmation counter
   // ------------------------------------------------------------------
   if(buySignal)
   {
      if(g_pendingDir == 1) g_pendingCount++;
      else { g_pendingDir = 1; g_pendingCount = 1; }
   }
   else if(sellSignal)
   {
      if(g_pendingDir == -1) g_pendingCount++;
      else { g_pendingDir = -1; g_pendingCount = 1; }
   }
   else
   {
      // No crossover signal – keep counting bars in same pending direction
      if(g_pendingDir != 0) g_pendingCount++;
   }

   // If pending direction matches current open trade direction – no action
   if(g_inTrade && g_tradeDir == g_pendingDir)
   {
      g_pendingDir   = 0;
      g_pendingCount = 0;
      return;
   }

   // ------------------------------------------------------------------
   // ENTRY after confirmation
   // ------------------------------------------------------------------
   if(!g_inTrade && g_pendingDir != 0 && g_pendingCount >= InpConfirmBars)
   {
      bool isBuy = (g_pendingDir == 1);
      Log(StringFormat("Trend confirmed (%d bars) → entering %s basket",
                       g_pendingCount, isBuy ? "BUY" : "SELL"));
      EnterBasket(isBuy);
      g_pendingDir   = 0;
      g_pendingCount = 0;
   }
}
//+------------------------------------------------------------------+
