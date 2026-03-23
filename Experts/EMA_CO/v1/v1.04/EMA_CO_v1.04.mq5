//+------------------------------------------------------------------+
//|                                            EMACrossOverV1.04.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property version   "1.04"
#property description "EMA Crossover Expert Advisor - v1.04"
//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input double LotSize = 0.01;         // Lot size for each trade
input int ShortPeriod = 10;          // Short EMA period
input int LongPeriod = 20;           // Long EMA period
input int MagicNumber = 6;           // Magic Number
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
   ema_short_handle = iMA(_Symbol, _Period, ShortPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ema_long_handle = iMA(_Symbol, _Period, LongPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   if(ema_short_handle == INVALID_HANDLE || ema_long_handle == INVALID_HANDLE)
     {
      Print("Error creating EMA handles");
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(MagicNumber);
   
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(ema_short_handle);
   IndicatorRelease(ema_long_handle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
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

  //--- Bull
   if(ema_short[0] > ema_long[0])
     {
      // Close Sell position if it exists
      if(hasPosition && posType == POSITION_TYPE_SELL)
         trade.PositionClose(_Symbol);
      
      // Open Buy if no position
      if(!PositionSelect(_Symbol))
         trade.Buy(LotSize, _Symbol, 0, 0, 0, "Open EMA Crossover Buy");
     }
   
  //--- Bear
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