//+------------------------------------------------------------------+
//|                                             EMACrossOverV1.2.mq5 |
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
input double LotSize = 0.01;         // Lot size for each trade
input int ShortPeriod = 10;      // Short EMA period
input int LongPeriod = 20;       // Long EMA period
input double RR_Ratio = 2.0;       // Risk:Reward ratio for Take Profit
input int MagicNumber = 123456;    // Magic Number
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
bool can_enter = false;
double ema_short[];
double ema_long[];
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
   
   ArraySetAsSeries(ema_short, true);
   ArraySetAsSeries(ema_long, true);
   
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
void OnTick()
  {
   // start_pos = 0 => get from current bar
   // Ưu điểm: Bắt tín hiệu sớm hơn so với start_pos = 1
   // Nhược điểm: Có thể bị nhiễu bởi tín hiệu giả
   if(CopyBuffer(ema_short_handle, 0, 0, 2, ema_short) != 2 ||
      CopyBuffer(ema_long_handle, 0, 0, 2, ema_long) != 2)
     {
      return;
     }

   double prev_short = ema_short[1], prev_long = ema_long[1]; // previous closed bar
   double curr_short = ema_short[0], curr_long = ema_long[0]; // current/newest closed bar

   //--- detect crossover events
   if(prev_short <= prev_long && curr_short > curr_long) // bullish crossover
     {
      can_enter = true;
      Print("Bullish crossover detected - entry armed.");
     }
   else if(prev_short >= prev_long && curr_short < curr_long) // bearish crossover
     {
      can_enter = false;
      Print("Bearish crossover detected - closing positions and blocking entries.");
      if(PositionSelect(_Symbol))
         trade.PositionClose(_Symbol);
     }

   //--- entry: only on a bullish crossover and no existing position on this symbol
   if(can_enter && !PositionSelect(_Symbol))
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0;
      double risk = StopLossPips * pip;
      double sl = (StopLossPips > 0) ? ask - risk : 0;
      double tp = (RR_Ratio > 0) ? ask + RR_Ratio * risk : 0;

      if(trade.Buy(LotSize, _Symbol, 0, sl, tp, "EMA crossover buy"))
        {
         Print("Opened BUY on bullish crossover.");
         can_enter = false; // require next bullish cross to re-arm
        }
      else
         Print("Buy failed: ", GetLastError());
     }
  }