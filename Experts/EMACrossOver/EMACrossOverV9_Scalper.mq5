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
input double StopLossPips = 400;      // Stop Loss in pips
input double TakeProfitPips = 800;    // Take Profit in pips
input double LotSize = 0.01;         // Lot size for each trade
input int ShortPeriod = 10;      // Short EMA period
input int LongPeriod = 20;       // Long EMA period
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
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create EMA handles
   ema_short_handle = iMA(_Symbol, _Period, ShortPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ema_long_handle = iMA(_Symbol, _Period, LongPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   if(ema_short_handle == INVALID_HANDLE || ema_long_handle == INVALID_HANDLE)
     {
      Print("Error creating EMA handles");
      return(INIT_FAILED);
     }

//--- set magic number
   trade.SetExpertMagicNumber(1231);
   
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
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
  //--- get EMA values
   double ema_short[1], ema_long[1];
   if(CopyBuffer(ema_short_handle, 0, 0, 1, ema_short) != 1 ||
      CopyBuffer(ema_long_handle, 0, 0, 1, ema_long) != 1)
     {
      return;
     }

  //--- get current prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
  //--- check for buy signal
   if(ema_short[0] > ema_long[0] && PositionsTotal() == 0)
     {
      if (StopLossPips == 0 && TakeProfitPips == 0)
        {
          // open buy position without SL and TP
          trade.Buy(LotSize, _Symbol, 0, 0, 0, "Open EMA Crossover Buy without SL/TP");
        }
      else 
        {
          // calculate SL and TP in prices
          double sl = ask - (StopLossPips * point * 10);   // SL below ask price
          double tp = ask + (TakeProfitPips * point * 10); // TP above ask price

          // open buy position
          trade.Buy(LotSize, _Symbol, 0, sl, tp, "Open EMA Crossover Buy with SL/TP");
        }
     }
   
  //--- check for sell signal (close position)
   else if(ema_short[0] < ema_long[0] && PositionsTotal() > 0)
     {
      // close all positions
      trade.PositionClose(_Symbol);
     }
}