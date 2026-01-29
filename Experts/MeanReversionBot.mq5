//+------------------------------------------------------------------+
//|                                                MeanReversionBot.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
//+------------------------------------------------------------------+
//| Include files                                                    |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
int bb_handle;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create timer
   EventSetTimer(60);
   
//--- create Bollinger Bands handle (period 20, deviation 2)
   bb_handle = iBands(_Symbol, _Period, 20, 0, 2, PRICE_CLOSE);
   
   if(bb_handle == INVALID_HANDLE)
     {
      Print("Error creating Bollinger Bands handle");
      return(INIT_FAILED);
     }
   
//--- set magic number
   trade.SetExpertMagicNumber(654321);
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
   EventKillTimer();
   
//--- release Bollinger Bands handle
   IndicatorRelease(bb_handle);
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- get current close price
   double close = iClose(_Symbol, _Period, 0);
   
//--- get Bollinger Bands values
   double upper[1], lower[1];
   if(CopyBuffer(bb_handle, 1, 0, 1, upper) != 1 ||
      CopyBuffer(bb_handle, 2, 0, 1, lower) != 1)
     {
      return;
     }
   
//--- check for buy signal (price touches lower band)
   if(close <= lower[0] && PositionsTotal() == 0)
     {
      // open buy position
      trade.Buy(0.01, _Symbol, 0, 0, 0, "Mean Reversion Buy");
     }
   
//--- check for sell signal (price touches upper band, close position)
   else if(close >= upper[0] && PositionsTotal() > 0)
     {
      // close all positions
      trade.PositionClose(_Symbol);
     }
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int32_t id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| BookEvent function                                               |
//+------------------------------------------------------------------+
void OnBookEvent(const string &symbol)
  {
//---
   
  }
//+------------------------------------------------------------------+