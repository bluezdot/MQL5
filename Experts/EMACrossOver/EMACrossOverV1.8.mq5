//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input int ATR_Period = 14;           // ATR period
input double ATR_Multiplier = 1.5;   // ATR multiplier for volatility
input double TP_Multiplier = 1.0;    // Take Profit multiplier
input double LotSize = 0.01;         // Lot size for each trade
input int ShortPeriod = 9;           // Short EMA period
input int LongPeriod = 21;           // Long EMA period
input int MagicNumber = 123456;      // Magic Number
//+------------------------------------------------------------------+
//| Include files                                                    |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
int ema_short_handle;
int ema_long_handle;
int atr_handle;
double ema_short[];
double ema_long[];
double atr[];
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   ema_short_handle = iMA(_Symbol, _Period, ShortPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ema_long_handle = iMA(_Symbol, _Period, LongPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atr_handle = iATR(_Symbol, _Period, ATR_Period);
   
   if(ema_short_handle == INVALID_HANDLE || ema_long_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
     {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(MagicNumber);

   ArraySetAsSeries(ema_short, true);
   ArraySetAsSeries(ema_long, true);
   ArraySetAsSeries(atr, true);

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(ema_short_handle);
   IndicatorRelease(ema_long_handle);
   IndicatorRelease(atr_handle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   if(CopyBuffer(ema_short_handle, 0, 0, 2, ema_short) != 2 ||
      CopyBuffer(ema_long_handle, 0, 0, 2, ema_long) != 2 || 
      CopyBuffer(atr_handle, 0, 0, 1, atr) != 1)
     {
      return;
     }

   Comment("EMA Short [0]: ", ema_short[0], "\n",
           "EMA Short [1]: ", ema_short[1], "\n",
           "EMA Long [0]: ", ema_long[0], "\n",
           "EMA Long [1]: ", ema_long[1], "\n",
           "ATR [0]: ", atr[0]);
   
   // Check exit conditions first
   if(ema_short[0] <= ema_long[0] && ema_short[1] > ema_long[1] && PositionsTotal() > 0)
     {
      // Close position if EMA crossover (short crosses below long)
      trade.PositionClose(_Symbol);
     }
   
   // Check entry condition
   if(ema_short[0] > ema_long[0] && ema_short[1] <= ema_long[1] && PositionsTotal() == 0)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double risk = atr[0] * ATR_Multiplier;
      double tp = ask + (TP_Multiplier * risk);

      trade.Buy(LotSize, _Symbol, 0, 0, tp, "Open EMA Crossover Buy with TP");
     }
}