//+------------------------------------------------------------------+
//|  [Viprasol] Multi-Timeframe Trend Signal Engine EA               |
//|  MQL5 translation of the Viprasol Pine Script indicator          |
//|  Strategy: SuperTrend crossover + EMA / ADX / Ribbon / Chaos     |
//|  Version : 1.00                                                  |
//+------------------------------------------------------------------+
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_MODE
{
   MODE_ALL      = 0,  // All Signals
   MODE_FILTERED = 1   // Filtered Signals
};

enum ENUM_CANDLE_VALIDATE
{
   VALIDATE_CLOSED = 0,  // Wait for candle close (recommended)
   VALIDATE_LIVE   = 1   // Use live tick (risk of repaint)
};

//+------------------------------------------------------------------+
//| Pine Script Constants (preserved from source)                    |
//+------------------------------------------------------------------+
#define ADX_PERIOD      14
#define ADX_BULL_MULT   1.2
#define ADX_BEAR_MULT   0.8
#define RSI_PERIOD      14
#define FILTER_MA_LEN   13
#define CHAOS_AMP       3
#define CHAOS_DEV_MULT  2
#define OB_LEVEL        75.0
#define OS_LEVEL        25.0

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
// ── Main Settings ──────────────────────────────────────────────────
input group "═══════════ Main Settings ═══════════"
input double   InpSensitivity    = 2.5;         // Sensitivity (SuperTrend ATR mult)
input ENUM_SIGNAL_MODE InpSignalMode = MODE_ALL;// Signal Mode
input int      InpAtrFactor      = 11;          // ATR Factor (ST band period)

// ── Trend Filters ──────────────────────────────────────────────────
input group "═══════════ Trend Filters ═══════════"
input bool     InpUseMainEma     = true;        // Use Main EMA Filter
input int      InpMainEmaPeriod  = 200;         // Main EMA Period
input bool     InpUseRibbon      = true;        // Use Ribbon EMA Filter (EMA20 vs EMA55)
input bool     InpUseChaos       = false;       // Use Chaos Trend Filter
input bool     InpUseMtfFilter   = false;       // Use MTF Confluence Filter
input int      InpMtfMinScore    = 4;           // Min MTF Bull score for BUY (1-6)

// ── Trade Execution ─────────────────────────────────────────────────
input group "═══════════ Trade Execution ═══════════"
input double   InpLotSize        = 0.1;         // Lot Size
input int      InpMagicNumber    = 202601;      // Magic Number
input ENUM_CANDLE_VALIDATE InpValidate = VALIDATE_CLOSED; // Entry Validation
input int      InpSlippage       = 10;          // Max Slippage (points)
input bool     InpReverseTrade   = false;       // Reverse signal (sell on buy signal)
input bool     InpCloseOnOpposite= true;        // Close existing trade on opposite signal

// ── Risk Management ─────────────────────────────────────────────────
input group "═══════════ Risk Management ═══════════"
input bool     InpUseFixedSL     = false;       // Use Fixed SL (points)
input int      InpFixedSL        = 500;         // Fixed SL distance (points)
input double   InpAtrSlMult      = 2.2;         // ATR(14)*mult = ATR SL distance
input bool     InpUseFixedTP     = false;       // Use Fixed TP (points)
input int      InpFixedTP        = 1000;        // Fixed TP distance (points)
input double   InpTpMult1        = 1.0;         // TP1 multiplier (risk * mult)
input bool     InpUseTP2         = true;        // Enable TP2 partial close / BE
input double   InpTpMult2        = 2.0;         // TP2 multiplier
input bool     InpUseTP3         = false;       // Enable TP3 full close
input double   InpTpMult3        = 3.0;         // TP3 multiplier
input bool     InpMoveBeAtTp1    = true;        // Move SL to Break-Even at TP1

// ── RSI TP Signals ──────────────────────────────────────────────────
input group "═══════════ RSI TP Signals ═══════════"
input bool     InpUseRsiTp       = false;       // Use RSI overbought/oversold TP
input double   InpRsiTp1Bull     = 70.0;        // RSI Bull TP1 level (crossover)
input double   InpRsiTp2Bull     = 85.0;        // RSI Bull TP2 level (crossover)

//+------------------------------------------------------------------+
//| Indicator Handles (persistent — created once in OnInit)          |
//+------------------------------------------------------------------+
// Main timeframe
int h_MainEma     = INVALID_HANDLE;
int h_FilterMa    = INVALID_HANDLE;  // SMA(13)
int h_Atr14       = INVALID_HANDLE;  // ATR(14) for SL
int h_AtrST       = INVALID_HANDLE;  // ATR(InpAtrFactor) for SuperTrend
int h_Atr100      = INVALID_HANDLE;  // ATR(100) for Chaos
int h_Rsi         = INVALID_HANDLE;
int h_Ribbon20    = INVALID_HANDLE;  // EMA(20)
int h_Ribbon55    = INVALID_HANDLE;  // EMA(55)

// MTF ADX handles (6 timeframes: M5, M15, H1, H4, H12, D1)
int h_AdxMtf[6];
ENUM_TIMEFRAMES MTF_LIST[6] = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_H12, PERIOD_D1};

//+------------------------------------------------------------------+
//| Trade objects                                                    |
//+------------------------------------------------------------------+
CTrade        g_trade;
CPositionInfo g_pos;

//+------------------------------------------------------------------+
//| EA State Variables                                               |
//+------------------------------------------------------------------+
// SuperTrend persistent state
double g_st_UpperBand = 0.0;
double g_st_LowerBand = 0.0;
double g_st_Line      = 0.0;   // Previous bar's trend line
int    g_st_Dir       = 0;     // Previous bar's direction: -1=bull, 1=bear

// Ribbon
bool   g_ribbonBull   = false;

// Chaos state
int    g_chaosTrend     = 0;   // 0=up (bull), 1=down (bear)
int    g_chaosNextTrend = 0;
double g_chaosMaxLow    = 0.0;
double g_chaosMinHigh   = 0.0;
double g_chaosUpLine    = 0.0;
double g_chaosDownLine  = 0.0;

// Trade state
double g_entryPrice   = 0.0;
double g_stopPrice    = 0.0;
int    g_tradeSide    = 0;     // 1=long, -1=short, 0=flat
bool   g_tp1Hit       = false;
bool   g_tp2Hit       = false;

// Bar state
datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   g_trade.SetAsyncMode(false);

   // Create persistent indicator handles
   h_MainEma   = iMA(_Symbol, _Period, InpMainEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   h_FilterMa  = iMA(_Symbol, _Period, FILTER_MA_LEN,    0, MODE_SMA, PRICE_CLOSE);
   h_Atr14     = iATR(_Symbol, _Period, 14);
   h_AtrST     = iATR(_Symbol, _Period, InpAtrFactor);
   h_Atr100    = iATR(_Symbol, _Period, 100);
   h_Rsi       = iRSI(_Symbol, _Period, RSI_PERIOD, PRICE_CLOSE);
   h_Ribbon20  = iMA(_Symbol, _Period, 20, 0, MODE_EMA, PRICE_CLOSE);
   h_Ribbon55  = iMA(_Symbol, _Period, 55, 0, MODE_EMA, PRICE_CLOSE);

   for(int i = 0; i < 6; i++)
      h_AdxMtf[i] = iADXWilder(_Symbol, MTF_LIST[i], ADX_PERIOD);

   // Validate handles
   if(h_MainEma == INVALID_HANDLE || h_FilterMa == INVALID_HANDLE ||
      h_Atr14  == INVALID_HANDLE || h_AtrST == INVALID_HANDLE ||
      h_Rsi    == INVALID_HANDLE)
   {
      Print("[Viprasol EA] ERROR: Failed to create indicator handles!");
      return INIT_FAILED;
   }

   // Seed chaos state
   int bars = Bars(_Symbol, _Period);
   if(bars > 1)
   {
      g_chaosMaxLow  = iLow (_Symbol, _Period, 1);
      g_chaosMinHigh = iHigh(_Symbol, _Period, 1);
   }

   Print("[Viprasol EA] Initialized on ", _Symbol, " ", EnumToString(_Period),
         " | SensitivityMult=", InpSensitivity,
         " | ATRFactor=", InpAtrFactor,
         " | Mode=", (InpSignalMode == MODE_ALL ? "All Signals" : "Filtered Signals"));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release handles
   if(h_MainEma  != INVALID_HANDLE) IndicatorRelease(h_MainEma);
   if(h_FilterMa != INVALID_HANDLE) IndicatorRelease(h_FilterMa);
   if(h_Atr14    != INVALID_HANDLE) IndicatorRelease(h_Atr14);
   if(h_AtrST    != INVALID_HANDLE) IndicatorRelease(h_AtrST);
   if(h_Atr100   != INVALID_HANDLE) IndicatorRelease(h_Atr100);
   if(h_Rsi      != INVALID_HANDLE) IndicatorRelease(h_Rsi);
   if(h_Ribbon20 != INVALID_HANDLE) IndicatorRelease(h_Ribbon20);
   if(h_Ribbon55 != INVALID_HANDLE) IndicatorRelease(h_Ribbon55);
   for(int i = 0; i < 6; i++)
      if(h_AdxMtf[i] != INVALID_HANDLE) IndicatorRelease(h_AdxMtf[i]);
}

//+------------------------------------------------------------------+
//| Helper: copy one buffer value                                    |
//+------------------------------------------------------------------+
double BufVal(int handle, int bufIdx, int shift)
{
   double buf[1];
   if(CopyBuffer(handle, bufIdx, shift, 1, buf) < 1) return 0.0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Detect new bar                                                   |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t != g_lastBarTime) { g_lastBarTime = t; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| SuperTrend                                                       |
//| Mirrors Pine: computeSuperTrend(open, sensitivity, atrLen)       |
//| All inputs use shift=1 (previous confirmed bar)                  |
//+------------------------------------------------------------------+
void CalcSuperTrend(double &stLine, int &stDir)
{
   // Pine uses `open` as the `src` for the band midpoint
   double src      = iOpen(_Symbol, _Period, 1);
   double atrVal   = BufVal(h_AtrST, 0, 1);      // ATR of bar[1]
   double close1   = iClose(_Symbol, _Period, 1);  // bar[1] close
   double close2   = iClose(_Symbol, _Period, 2);  // bar[2] close (prev of bar[1])

   double upperBand = src + InpSensitivity * atrVal;
   double lowerBand = src - InpSensitivity * atrVal;

   // Trailing band adjustment (Pine logic)
   lowerBand = (lowerBand > g_st_LowerBand || close2 < g_st_LowerBand) ? lowerBand : g_st_LowerBand;
   upperBand = (upperBand < g_st_UpperBand || close2 > g_st_UpperBand) ? upperBand : g_st_UpperBand;

   g_st_LowerBand = lowerBand;
   g_st_UpperBand = upperBand;

   // Direction logic
   if(g_st_Line == 0.0) // first call
   {
      stDir  = 2;          // neutral
      stLine = upperBand;
   }
   else if(g_st_Line == g_st_UpperBand) // was on upper (bear) band
   {
      stDir  = (close1 > upperBand) ? -1 : 1;
      stLine = (stDir == -1) ? lowerBand : upperBand;
   }
   else // was on lower (bull) band
   {
      stDir  = (close1 < lowerBand) ? 1 : -1;
      stLine = (stDir == -1) ? lowerBand : upperBand;
   }
}

//+------------------------------------------------------------------+
//| Ribbon EMA state update                                          |
//| EMA(20) vs EMA(55) — updates g_ribbonBull                       |
//+------------------------------------------------------------------+
void UpdateRibbon()
{
   double fast0 = BufVal(h_Ribbon20, 0, 1);
   double slow0 = BufVal(h_Ribbon55, 0, 1);
   double fast1 = BufVal(h_Ribbon20, 0, 2);
   double slow1 = BufVal(h_Ribbon55, 0, 2);

   if(fast1 <= slow1 && fast0 > slow0) g_ribbonBull = true;
   if(fast1 >= slow1 && fast0 < slow0) g_ribbonBull = false;
}

//+------------------------------------------------------------------+
//| Chaos Trend state machine update                                 |
//| Mirrors Pine's chaos block exactly                               |
//+------------------------------------------------------------------+
void UpdateChaos()
{
   int lookback = 110; // enough for AMP + ATR100
   double hi[], lo[], cl[];
   if(CopyHigh (_Symbol, _Period, 1, lookback, hi) < lookback) return;
   if(CopyLow  (_Symbol, _Period, 1, lookback, lo) < lookback) return;
   if(CopyClose(_Symbol, _Period, 1, lookback, cl) < lookback) return;

   int sz     = ArraySize(hi);
   int amp    = CHAOS_AMP;

   // Latest bar in array: [sz-1]
   double curClose = cl[sz-1];
   double prevLow  = lo[sz-2];
   double prevHigh = hi[sz-2];

   // chaosHighP = highest in last AMP bars, chaosLowP = lowest
   double chaosHighP = 0.0, chaosLowP = DBL_MAX;
   double chaosHighMa = 0.0, chaosLowMa = 0.0;
   for(int k = sz - amp; k < sz; k++)
   {
      if(hi[k] > chaosHighP) chaosHighP = hi[k];
      if(lo[k] < chaosLowP)  chaosLowP  = lo[k];
      chaosHighMa += hi[k];
      chaosLowMa  += lo[k];
   }
   chaosHighMa /= amp;
   chaosLowMa  /= amp;

   // ATR(100)/2 from persistent handle
   double atr100h = BufVal(h_Atr100, 0, 1) / 2.0;

   // State machine (matches Pine if/else exactly)
   if(g_chaosNextTrend == 1)
   {
      g_chaosMaxLow = MathMax(chaosLowP, g_chaosMaxLow);
      if(chaosHighMa < g_chaosMaxLow && curClose < prevLow)
      {
         g_chaosTrend     = 1;
         g_chaosNextTrend = 0;
         g_chaosMinHigh   = chaosHighP;
      }
   }
   else
   {
      g_chaosMinHigh = MathMin(chaosHighP, g_chaosMinHigh);
      if(chaosLowMa > g_chaosMinHigh && curClose > prevHigh)
      {
         g_chaosTrend     = 0;
         g_chaosNextTrend = 1;
         g_chaosMaxLow    = chaosLowP;
      }
   }

   // Update trend lines
   if(g_chaosTrend == 0)
      g_chaosUpLine = (g_chaosUpLine == 0.0) ? g_chaosMaxLow : MathMax(g_chaosMaxLow, g_chaosUpLine);
   else
      g_chaosDownLine = (g_chaosDownLine == 0.0) ? g_chaosMinHigh : MathMin(g_chaosMinHigh, g_chaosDownLine);
}

//+------------------------------------------------------------------+
//| ADX trend quality for a given MTF handle                         |
//| Returns +1 (bull), -1 (bear), 0 (neutral)                       |
//| Mirrors Pine: detectTrendQuality()                               |
//+------------------------------------------------------------------+
int AdxTrendQuality(int handle)
{
   if(handle == INVALID_HANDLE) return 0;

   // Collect ADX_PERIOD values to compute median (Pine uses sma as proxy)
   double adxBuf[];
   if(CopyBuffer(handle, 0, 1, ADX_PERIOD, adxBuf) < ADX_PERIOD) return 0;

   double adxVal = adxBuf[ADX_PERIOD - 1]; // most recent
   double sum    = 0.0;
   for(int i = 0; i < ADX_PERIOD; i++) sum += adxBuf[i];
   double medianAdx = sum / ADX_PERIOD;

   double bullThresh = medianAdx * ADX_BULL_MULT;
   double bearThresh = medianAdx * ADX_BEAR_MULT;

   if(adxVal > bullThresh) return  1;
   if(adxVal < bearThresh) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Compute SL distance                                              |
//+------------------------------------------------------------------+
double CalcSlDistance()
{
   if(InpUseFixedSL) return InpFixedSL * _Point;
   return BufVal(h_Atr14, 0, 1) * InpAtrSlMult;
}

//+------------------------------------------------------------------+
//| Compute TP price                                                 |
//+------------------------------------------------------------------+
double CalcTpPrice(bool isBuy, double entry, double slDist, double mult)
{
   if(InpUseFixedTP) return isBuy ? entry + InpFixedTP * _Point * mult
                                  : entry - InpFixedTP * _Point * mult;
   double risk = slDist * mult;
   return isBuy ? entry + risk : entry - risk;
}

//+------------------------------------------------------------------+
//| Position helpers                                                 |
//+------------------------------------------------------------------+
bool HasPosition(ENUM_POSITION_TYPE t)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(g_pos.SelectByIndex(i) && g_pos.Symbol() == _Symbol &&
         g_pos.Magic() == InpMagicNumber && g_pos.PositionType() == t)
         return true;
   return false;
}

bool HasAnyPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(g_pos.SelectByIndex(i) && g_pos.Symbol() == _Symbol &&
         g_pos.Magic() == InpMagicNumber)
         return true;
   return false;
}

void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_pos.SelectByIndex(i) && g_pos.Symbol() == _Symbol &&
         g_pos.Magic() == InpMagicNumber)
         g_trade.PositionClose(g_pos.Ticket());
   }
   g_tp1Hit = false;
   g_tp2Hit = false;
   g_tradeSide = 0;
}

//+------------------------------------------------------------------+
//| Open Buy                                                         |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slDist  = CalcSlDistance();
   double sl      = NormalizeDouble(ask - slDist, _Digits);
   double tp      = NormalizeDouble(CalcTpPrice(true, ask, slDist, InpTpMult1), _Digits);

   if(g_trade.Buy(InpLotSize, _Symbol, 0, sl, tp, "[Viprasol] BUY"))
   {
      g_entryPrice = ask;
      g_stopPrice  = sl;
      g_tradeSide  = 1;
      g_tp1Hit     = false;
      g_tp2Hit     = false;
      Print("[Viprasol EA] BUY opened | SL=", sl, " TP1=", tp,
            " | ticket=", g_trade.ResultOrder());
   }
   else Print("[Viprasol EA] BUY failed: ", g_trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Open Sell                                                        |
//+------------------------------------------------------------------+
void OpenSell()
{
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDist = CalcSlDistance();
   double sl     = NormalizeDouble(bid + slDist, _Digits);
   double tp     = NormalizeDouble(CalcTpPrice(false, bid, slDist, InpTpMult1), _Digits);

   if(g_trade.Sell(InpLotSize, _Symbol, 0, sl, tp, "[Viprasol] SELL"))
   {
      g_entryPrice = bid;
      g_stopPrice  = sl;
      g_tradeSide  = -1;
      g_tp1Hit     = false;
      g_tp2Hit     = false;
      Print("[Viprasol EA] SELL opened | SL=", sl, " TP1=", tp,
            " | ticket=", g_trade.ResultOrder());
   }
   else Print("[Viprasol EA] SELL failed: ", g_trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Manage open positions: Break-even, TP2/TP3, RSI TP               |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != _Symbol || g_pos.Magic() != InpMagicNumber) continue;

      ulong  ticket   = g_pos.Ticket();
      bool   isBuy    = (g_pos.PositionType() == POSITION_TYPE_BUY);
      double entry    = g_pos.PriceOpen();
      double curSl    = g_pos.StopLoss();
      double curTp    = g_pos.TakeProfit();
      double slDist   = CalcSlDistance();

      double tp1 = CalcTpPrice(isBuy, entry, slDist, InpTpMult1);
      double tp2 = CalcTpPrice(isBuy, entry, slDist, InpTpMult2);
      double tp3 = CalcTpPrice(isBuy, entry, slDist, InpTpMult3);

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double cur = isBuy ? bid : ask;

      // ── RSI TP (Pine's RSI crossover TP signals) ──────────────────
      if(InpUseRsiTp && !g_tp1Hit)
      {
         double rsi0 = BufVal(h_Rsi, 0, 1); // last confirmed bar
         double rsi1 = BufVal(h_Rsi, 0, 2);
         if(isBuy)
         {
            bool tp1cross = (rsi1 <= InpRsiTp1Bull && rsi0 > InpRsiTp1Bull);
            if(tp1cross)
            {
               g_tp1Hit = true;
               Print("[Viprasol EA] RSI TP1 hit (bull) — closing, ticket=", ticket);
               g_trade.PositionClose(ticket);
               continue;
            }
         }
         else
         {
            double lv = 100.0 - InpRsiTp1Bull;
            bool tp1cross = (rsi1 >= lv && rsi0 < lv);
            if(tp1cross)
            {
               g_tp1Hit = true;
               Print("[Viprasol EA] RSI TP1 hit (bear) — closing, ticket=", ticket);
               g_trade.PositionClose(ticket);
               continue;
            }
         }
      }

      // ── Price-based TP1 → Break-even ─────────────────────────────
      if(!g_tp1Hit)
      {
         bool hitTp1 = isBuy ? (cur >= tp1) : (cur <= tp1);
         if(hitTp1)
         {
            g_tp1Hit = true;
            if(InpMoveBeAtTp1)
            {
               double beSl = NormalizeDouble(isBuy ? entry + _Point : entry - _Point, _Digits);
               bool   needMove = isBuy ? beSl > curSl : beSl < curSl;
               if(needMove) g_trade.PositionModify(ticket, beSl, curTp);
               Print("[Viprasol EA] TP1 hit → SL moved to BE, ticket=", ticket);
            }
            if(!InpUseTP2 && !InpUseTP3)
            {
               g_trade.PositionClose(ticket);
               continue;
            }
         }
      }

      // ── TP2 ───────────────────────────────────────────────────────
      if(g_tp1Hit && !g_tp2Hit && InpUseTP2)
      {
         bool hitTp2 = isBuy ? (cur >= tp2) : (cur <= tp2);
         if(hitTp2)
         {
            g_tp2Hit = true;
            if(!InpUseTP3)
            {
               Print("[Viprasol EA] TP2 hit — closing, ticket=", ticket);
               g_trade.PositionClose(ticket);
               continue;
            }
            else
            {
               // Trail SL to TP1 and keep running for TP3
               double newSl = NormalizeDouble(tp1, _Digits);
               bool needMove = isBuy ? newSl > curSl : newSl < curSl;
               if(needMove) g_trade.PositionModify(ticket, newSl, curTp);
               Print("[Viprasol EA] TP2 hit → SL trail to TP1, running TP3, ticket=", ticket);
            }
         }
      }

      // ── TP3 ───────────────────────────────────────────────────────
      if(g_tp1Hit && g_tp2Hit && InpUseTP3)
      {
         bool hitTp3 = isBuy ? (cur >= tp3) : (cur <= tp3);
         if(hitTp3)
         {
            Print("[Viprasol EA] TP3 hit — closing, ticket=", ticket);
            g_trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTick — main execution loop                                     |
//+------------------------------------------------------------------+
void OnTick()
{
   bool newBar = IsNewBar();

   // Bar-close mode: process logic only on new bar
   if(InpValidate == VALIDATE_CLOSED && !newBar)
   {
      // Still manage positions on every tick (for real-time TP/SL tracking)
      ManagePositions();
      return;
   }

   // Minimum bars guard
   if(Bars(_Symbol, _Period) < InpMainEmaPeriod + 20) return;

   // ── 1. Update indicators ───────────────────────────────────────
   UpdateRibbon();
   if(InpUseChaos) UpdateChaos();

   // ── 2. Read key values (bar[1] = last confirmed bar) ──────────
   double close0 = iClose(_Symbol, _Period, 1); // confirmed close
   double close1 = iClose(_Symbol, _Period, 2); // bar before that

   double mainEma0 = BufVal(h_MainEma,  0, 1); // EMA(200) at bar[1]
   double mainEma1 = BufVal(h_MainEma,  0, 2); // EMA(200) at bar[2]
   double filterMa = BufVal(h_FilterMa, 0, 1); // SMA(13) at bar[1]

   // ── 3. SuperTrend ──────────────────────────────────────────────
   double newStLine = 0.0;
   int    newStDir  = 0;
   CalcSuperTrend(newStLine, newStDir);

   // Crossover detection: compare bar[1] close vs NEW ST line,
   // and bar[2] close vs PREVIOUS ST line (g_st_Line)
   bool prevAbove = (close1 >= g_st_Line && g_st_Line > 0.0);
   bool curAbove  = (close0 >= newStLine);

   bool rawBuy  = (!prevAbove && curAbove)  && (close0 >= filterMa);
   bool rawSell = ( prevAbove && !curAbove) && (close0 <= filterMa);

   // Update stored SuperTrend state
   g_st_Line = newStLine;
   g_st_Dir  = newStDir;

   // ── 4. EMA Direction flag ──────────────────────────────────────
   bool aboveEma = (close1 > mainEma1) && (close0 > mainEma0);

   // ── 5. Signal Mode filter ──────────────────────────────────────
   // Pine "All Signals"    : unfilteredBuy  = rawBuy  AND NOT aboveEma
   //                         unfilteredSell = rawSell AND     aboveEma
   // Pine "Filtered Signals": filteredBuy  = rawBuy  AND     aboveEma
   //                          filteredSell = rawSell AND NOT aboveEma
   bool tradeBuy  = false;
   bool tradeSell = false;

   if(InpSignalMode == MODE_ALL)
   {
      tradeBuy  = rawBuy  && (!aboveEma || !InpUseMainEma);
      tradeSell = rawSell && ( aboveEma || !InpUseMainEma);
   }
   else
   {
      tradeBuy  = rawBuy  && ( aboveEma || !InpUseMainEma);
      tradeSell = rawSell && (!aboveEma || !InpUseMainEma);
   }

   // ── 6. Optional: Ribbon filter (EMA20 vs EMA55) ───────────────
   if(InpUseRibbon)
   {
      if(!g_ribbonBull && tradeBuy)  tradeBuy  = false;
      if( g_ribbonBull && tradeSell) tradeSell = false;
   }

   // ── 7. Optional: Chaos filter ─────────────────────────────────
   if(InpUseChaos)
   {
      // chaosTrend==0 means bullish direction
      if(g_chaosTrend != 0 && tradeBuy)  tradeBuy  = false;
      if(g_chaosTrend != 1 && tradeSell) tradeSell = false;
   }

   // ── 8. Optional: MTF Confluence filter ────────────────────────
   if(InpUseMtfFilter)
   {
      int bullScore = 0, bearScore = 0;
      for(int i = 0; i < 6; i++)
      {
         int q = AdxTrendQuality(h_AdxMtf[i]);
         if(q >  0) bullScore++;
         if(q <  0) bearScore++;
      }
      if(bullScore < InpMtfMinScore && tradeBuy)  tradeBuy  = false;
      if(bearScore < InpMtfMinScore && tradeSell) tradeSell = false;
   }

   // ── 9. Reverse signal option ───────────────────────────────────
   if(InpReverseTrade)
   {
      bool tmp  = tradeBuy;
      tradeBuy  = tradeSell;
      tradeSell = tmp;
   }

   // ── 10. Manage existing positions ─────────────────────────────
   ManagePositions();

   // ── 11. Execute trades ────────────────────────────────────────
   if(tradeBuy)
   {
      if(!HasPosition(POSITION_TYPE_BUY))
      {
         if(InpCloseOnOpposite) CloseAll();
         OpenBuy();
      }
   }
   else if(tradeSell)
   {
      if(!HasPosition(POSITION_TYPE_SELL))
      {
         if(InpCloseOnOpposite) CloseAll();
         OpenSell();
      }
   }
}

//+------------------------------------------------------------------+
//| End of [Viprasol] Multi-Timeframe Trend Signal Engine EA v1.00   |
//+------------------------------------------------------------------+
