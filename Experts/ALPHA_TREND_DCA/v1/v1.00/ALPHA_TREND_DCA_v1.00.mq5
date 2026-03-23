//+------------------------------------------------------------------+
//|                                              AlphaTrendBot.mq5   |
//|   Fibonacci DCA basket bot based on AlphaTrend indicator  v2.0   |
//+------------------------------------------------------------------+
#property copyright "AlphaTrend DCA Bot"
#property version   "1.00"
#property description "AlphaTrend DCA Expert Advisor - v1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//=== Input parameters =============================================
input group "=== Position Sizing ==="
input double InpBaseLot      = 0.01; // Base lot at InpBaseBalance
input int    InpMaxDCA       = 5;    // Max DCA levels (incl. initial entry)

input group "=== Lot Scaling ==="
input bool   InpScaleLot     = true;    // Scale lot proportional to account balance
input double InpBaseBalance  = 100000;  // Reference balance for InpBaseLot (e.g. 100 000 USD)

input group "=== DCA Grid ==="
input int    InpGrid         = 10;   // Minimum grid floor (Points) – used only if auto-grid is too small

input group "=== Take Profit ==="
input double InpTpMax        = 1.5;  // TP multiplier at level 1 (fewest positions)
input double InpTpMin        = 1.0;  // TP multiplier at max DCA (most positions)
// TP distance = ratio × InpGrid × _Point from basket avg entry

input group "=== Stop Loss ==="
input int    InpSLCandle     = 12;   // SL candle lookback
input int    InpSLPoint      = 10;   // Extra SL buffer beyond candle extreme (Points)
input int    InpSLFlex       = 50;   // SL flex tolerance: allow price to exceed SL by this many Points before triggering

input group "=== Signal Confirmation ==="
input int    InpConfirmBars  = 2;    // Bars trend must persist before entry

input group "=== Risk Control ==="
input bool   InpCloseOnRev   = true;  // Liquidate basket immediately on reversal signal
input bool   InpUseSL        = true;  // Use hard Stop Loss on all positions

input group "=== AlphaTrend Settings ==="
input double         InpATCoeff      = 1.0;          // AT Multiplier
input int            InpATPeriod     = 14;           // AT Period
input bool           InpATNoVol      = false;        // Use RSI instead of MFI
input ENUM_TIMEFRAMES InpSignalTF    = PERIOD_H1;   // Signal timeframe (indicator + bar detection)

input group "=== EA Settings ==="
input int    InpMagic        = 1;
input bool   InpPrintLog     = true;

//=== Global objects ===============================================
CTrade        g_trade;
CPositionInfo g_pos;
COrderInfo    g_ord;

int      g_atHandle      = INVALID_HANDLE;
datetime g_lastBarTime   = 0;

// Signal confirmation state
int      g_pendingDir    = 0;   // +1 = BUY pending, -1 = SELL pending, 0 = none
int      g_pendingCount  = 0;   // how many bars this pending direction has held

// Basket state
bool     g_inTrade       = false;
int      g_tradeDir      = 0;   // +1 = BUY basket active, -1 = SELL basket active
double   g_dynamicGrid   = 0;   // Auto-computed grid size for current basket (in price units)

//+------------------------------------------------------------------+
//| Log helper                                                        |
//+------------------------------------------------------------------+
void Log(string msg)
{
   if(InpPrintLog)
      PrintFormat("[AT-DCA] %s | %s",
                  TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), msg);
}

//+------------------------------------------------------------------+
//| Normalize lot                                                     |
//+------------------------------------------------------------------+
double NormLot(double lot)
{
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   // Always round UP to nearest 0.01
   double rounded = MathCeil(lot / 0.01) * 0.01;
   return MathMax(mn, MathMin(mx, NormalizeDouble(rounded, 2)));
}

//+------------------------------------------------------------------+
//| Return base lot scaled by current balance vs InpBaseBalance       |
//| e.g. balance=200k, base=100k → multiplier=2.0 → lots doubled     |
//+------------------------------------------------------------------+
double ScaledBaseLot()
{
   if(!InpScaleLot || InpBaseBalance <= 0)
      return InpBaseLot;
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double multiplier = balance / InpBaseBalance;
   return InpBaseLot * multiplier;
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
   // Use signal-TF candles for SL lookback (larger candles → natural SL placement)
   for(int i = 1; i <= InpSLCandle; i++)
      sl = isBuy ? MathMin(sl, iLow(_Symbol, InpSignalTF, i))
                 : MathMax(sl, iHigh(_Symbol, InpSignalTF, i));
   // SLPoint: fixed buffer beyond candle extreme
   // SLFlex : extra tolerance so price can breach the level by this much before actually hitting SL
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
//| tpRatio decreases linearly: TpMax (n=1) → TpMin (n=MaxDCA)      |
//| tpDist  = tpRatio × InpGrid × _Point  from avg entry            |
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
//|  Level 0 : market order, lot = baseLot × Fib(0)                  |
//|  Level i  : BuyLimit/SellLimit, lot = baseLot × Fib(i)           |
//|  Price spacing proportional to cumulative Fib weights over range  |
//|  range = |entry − extreme of last InpBackCandle bars|             |
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

   // Auto-compute dynamic grid:
   //   range = |entry − extreme of last InpSLCandle bars on signal TF|
   //   dynamicGrid = range / InpMaxDCA  (floor = InpGrid points)
   double extreme = entry;
   for(int i = 1; i <= InpSLCandle; i++)
      extreme = isBuy ? MathMin(extreme, iLow(_Symbol,  InpSignalTF, i))
                      : MathMax(extreme, iHigh(_Symbol, InpSignalTF, i));
   double range = MathAbs(entry - extreme);
   g_dynamicGrid = MathMax(range / InpMaxDCA, InpGrid * _Point);

   // Fibonacci lot weights (price spacing now uses g_dynamicGrid, not fib weights)
   double fib[];
   ArrayResize(fib, InpMaxDCA);
   for(int i = 0; i < InpMaxDCA; i++) fib[i] = FibNum(i);

   // Fibonacci lot weights – base lot is scaled by current balance
   double baseLot = ScaledBaseLot();
   Log(StringFormat("EnterBasket %s entry=%.5f sl=%.5f SLrange=%.0fpts dynGrid=%.0fpts baseLot=%.4f (x%.2f)",
                    isBuy ? "BUY" : "SELL", entry, sl,
                    range / _Point, g_dynamicGrid / _Point,
                    baseLot,
                    InpScaleLot ? AccountInfoDouble(ACCOUNT_BALANCE) / InpBaseBalance : 1.0));

   // Level 0 – market
   double lot0 = NormLot(baseLot * fib[0]);
   bool ok = isBuy ? g_trade.Buy(lot0,  _Symbol, 0, sl, 0, "AT_DCA_B_0")
                   : g_trade.Sell(lot0, _Symbol, 0, sl, 0, "AT_DCA_S_0");
   if(!ok) Log(StringFormat("  L0 MARKET FAILED err=%d", GetLastError()));
   else    Log(StringFormat("  L0 market lot=%.4f sl=%.5f", lot0, sl));

   // Levels 1..MaxDCA-1 – evenly spaced by g_dynamicGrid
   double stopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   for(int i = 1; i < InpMaxDCA; i++)
   {
      double offset   = g_dynamicGrid * i;
      double dcaPrice = isBuy ? NormalizeDouble(entry - offset, _Digits)
                               : NormalizeDouble(entry + offset, _Digits);

      if(isBuy  && entry - dcaPrice <= stopLevel) continue;
      if(!isBuy && dcaPrice - entry <= stopLevel) continue;

      double lotI = NormLot(baseLot * fib[i]);
      string cmt  = StringFormat("AT_DCA_%s_%d", isBuy ? "B" : "S", i);

      ok = isBuy ? g_trade.BuyLimit(lotI,  dcaPrice, _Symbol, sl, 0, ORDER_TIME_GTC, 0, cmt)
                 : g_trade.SellLimit(lotI, dcaPrice, _Symbol, sl, 0, ORDER_TIME_GTC, 0, cmt);
      if(!ok) Log(StringFormat("  L%d LIMIT FAILED err=%d price=%.5f lot=%.4f", i, GetLastError(), dcaPrice, lotI));
      else    Log(StringFormat("  L%d limit=%.5f offset=%.0fpts lot=%.4f", i, dcaPrice, offset / _Point, lotI));
   }

   g_inTrade  = true;
   g_tradeDir = isBuy ? 1 : -1;
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   g_atHandle = iCustom(_Symbol, InpSignalTF, "Custom\\AlphaTrend",
                        InpATCoeff, InpATPeriod, InpATNoVol);
   if(g_atHandle == INVALID_HANDLE)
   {
      Alert("AlphaTrendBot: Cannot load AlphaTrend indicator! Error=", GetLastError());
      return INIT_FAILED;
   }

   g_pendingDir   = 0;
   g_pendingCount = 0;
   g_inTrade      = false;
   g_tradeDir     = 0;
   g_dynamicGrid  = 0;

   Log(StringFormat("Init OK | SignalTF=%s CloseOnReversal=%s UseSL=%s ConfirmBars=%d",
       EnumToString(InpSignalTF), InpCloseOnRev ? "YES" : "NO",
       InpUseSL ? "YES" : "NO", InpConfirmBars));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atHandle != INVALID_HANDLE) { IndicatorRelease(g_atHandle); g_atHandle = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   // New-bar detection on the SIGNAL timeframe – execution still runs every tick
   datetime barTime = iTime(_Symbol, InpSignalTF, 0);
   bool isNewBar    = (barTime != g_lastBarTime);

   // ------------------------------------------------------------------
   // INTRA-BAR: only monitor active basket
   // ------------------------------------------------------------------
   if(!isNewBar)
   {
      if(!g_inTrade) return;
      bool isBuy = (g_tradeDir == 1);

      // All positions closed (SL hit) → re-enter same direction from current price
      if(CountPos(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL) == 0)
      {
         Log(StringFormat("Basket empty (SL hit) – re-entering %s from current price",
                          isBuy ? "BUY" : "SELL"));
         DeleteAllOrders();
         g_inTrade  = false;  // allow EnterBasket to proceed
         g_tradeDir = 0;
         EnterBasket(isBuy);
         g_pendingDir   = 0;
         g_pendingCount = 0;
         return;
      }

      // Basket TP check every tick
      if(CheckBasketTP(isBuy))
      {
         bool reDir = isBuy;  // save direction before reset
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

   // Edge-case: basket state says in-trade but all positions closed at bar boundary
   // (e.g. SL triggered on bar open tick before intra-bar path ran)
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

   double buyBuf[1], sellBuf[1];
   if(CopyBuffer(g_atHandle, 2, 1, 1, buyBuf)  < 1) return;
   if(CopyBuffer(g_atHandle, 3, 1, 1, sellBuf) < 1) return;

   bool buySignal  = (buyBuf[0]  != EMPTY_VALUE && buyBuf[0]  > 0);
   bool sellSignal = (sellBuf[0] != EMPTY_VALUE && sellBuf[0] > 0);
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
            EnterBasket(newDir);   // basket empty → enter new direction right away
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
