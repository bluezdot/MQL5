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
   trade.SetExpertMagicNumber(1233);
   
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
   
  //--- check for existing position
   bool hasPosition = PositionSelect(_Symbol);
   long posType = -1;
   if(hasPosition) posType = PositionGetInteger(POSITION_TYPE);

  //--- Buy logic
   if(ema_short[0] > ema_long[0])
     {
      // Close Sell position if it exists
      if(hasPosition && posType == POSITION_TYPE_SELL)
         trade.PositionClose(_Symbol);
      
      // Open Buy if no position
      if(!PositionSelect(_Symbol))
         trade.Buy(LotSize, _Symbol, 0, 0, 0, "Open EMA Crossover Buy");
     }
   
  //--- Sell logic
   else if(ema_short[0] < ema_long[0])
     {
      // Close Buy position if it exists
      if(hasPosition && posType == POSITION_TYPE_BUY)
         trade.PositionClose(_Symbol);
         
      // Open Sell if no position
      if(!PositionSelect(_Symbol))
         trade.Sell(LotSize, _Symbol, 0, 0, 0, "Open EMA Crossover Sell");
     }
}