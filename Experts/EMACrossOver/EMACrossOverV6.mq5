//+------------------------------------------------------------------+
//|                                                      BotDemo.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input double LotSize = 0.01;         // Lot size for each trade
input int ShortPeriod = 10;      // Short EMA period
input int LongPeriod = 20;       // Long EMA period
input int LongtermPeriod = 200; // Long term EMA period
input int ATR_Period = 14;      // ATR period for Stop Loss
input double ATR_Multiplier = 1.5; // ATR multiplier for Stop Loss
input double RR_Ratio = 2.0;       // Risk:Reward ratio for Take Profit
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
int ema_longterm_handle;
int atr_handle;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create EMA handles
   ema_short_handle = iMA(_Symbol, _Period, ShortPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ema_long_handle = iMA(_Symbol, _Period, LongPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ema_longterm_handle = iMA(_Symbol, _Period, LongtermPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atr_handle = iATR(_Symbol, _Period, ATR_Period);
   
   if(ema_short_handle == INVALID_HANDLE || ema_long_handle == INVALID_HANDLE || 
      ema_longterm_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
     {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
     }

//--- set magic number
   trade.SetExpertMagicNumber(1236);
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- release EMA handles
   IndicatorRelease(ema_short_handle);
   IndicatorRelease(ema_long_handle);
   IndicatorRelease(ema_longterm_handle);
   IndicatorRelease(atr_handle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
  //--- get EMA and ATR values
   double ema_short[2], ema_long[2], ema_longterm[1], atr[1];
   
   // Copy 2 values for crossover detection
   if(CopyBuffer(ema_short_handle, 0, 0, 2, ema_short) != 2 ||
      CopyBuffer(ema_long_handle, 0, 0, 2, ema_long) != 2 ||
      CopyBuffer(ema_longterm_handle, 0, 0, 1, ema_longterm) != 1 ||
      CopyBuffer(atr_handle, 0, 0, 1, atr) != 1)
     {
      return;
     }

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Crossover detection: 
   // ema_short[1] is current bar (changing), ema_short[0] is previous bar (fixed)
   bool isCrossUp = (ema_short[0] <= ema_long[0] && ema_short[1] > ema_long[1]);
   bool isCrossDown = (ema_short[0] >= ema_long[0] && ema_short[1] < ema_long[1]);

  //--- check for buy signal (New Crossover + Filter)
   if(isCrossUp && currentPrice > ema_longterm[0] && PositionsTotal() == 0)
     {
      double risk = ATR_Multiplier * atr[0];
      double sl = currentPrice - risk;
      double tp = currentPrice + (risk * RR_Ratio);
      
      // Normalize SL/TP to symbol digits
      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);
      
      trade.Buy(LotSize, _Symbol, 0, sl, tp, "Open EMA Crossover Buy (New Cross + ATR SL)");
     }
   
  //--- check for exit signal (Opposite Crossover)
   else if(isCrossDown && PositionsTotal() > 0)
     {
      // close position if crossover reverses
      trade.PositionClose(_Symbol);
     }
}