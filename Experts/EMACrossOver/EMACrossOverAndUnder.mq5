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
   ema_short_handle = iMA(_Symbol, _Period, 10, 0, MODE_EMA, PRICE_CLOSE);
   ema_long_handle = iMA(_Symbol, _Period, 20, 0, MODE_EMA, PRICE_CLOSE);
   
   if(ema_short_handle == INVALID_HANDLE || ema_long_handle == INVALID_HANDLE)
     {
      Print("Error creating EMA handles");
      return(INIT_FAILED);
     }

//--- set magic number
   trade.SetExpertMagicNumber(123458);
   
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
void OnTick()
  {
   //--- get EMA values from two closed bars (shifts 1 and 0)
   double ema_short_vals[2], ema_long_vals[2];
   if(CopyBuffer(ema_short_handle,0,1,2,ema_short_vals) != 2 ||
      CopyBuffer(ema_long_handle,0,1,2,ema_long_vals) != 2)
     return;

   // detect closed-bar crossover/crossunder
   bool bullish_cross = (ema_short_vals[1] <= ema_long_vals[1]) && (ema_short_vals[0] > ema_long_vals[0]);
   bool bearish_cross = (ema_short_vals[1] >= ema_long_vals[1]) && (ema_short_vals[0] < ema_long_vals[0]);

   //--- EA magic (set in OnInit)
   const int my_magic = 123458;

   //--- helpers: check if EA has a position of specific type
   auto HasMyPositionType = [&](int type)->bool
     {
      for(int i=0;i<PositionsTotal();++i)
        {
         if(PositionSelectByIndex(i))
           {
            if((int)PositionGetInteger(POSITION_MAGIC) == my_magic && PositionGetString(POSITION_SYMBOL) == _Symbol && (int)PositionGetInteger(POSITION_TYPE) == type)
               return true;
           }
        }
      return false;
     };

   //--- helper: close my positions of a given type
   auto CloseMyPositionsOfType = [&](int type)
     {
      for(int i=PositionsTotal()-1;i>=0;--i)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket==0) continue;
         if(PositionSelectByTicket(ticket))
           {
            if((int)PositionGetInteger(POSITION_MAGIC) == my_magic && PositionGetString(POSITION_SYMBOL) == _Symbol && (int)PositionGetInteger(POSITION_TYPE) == type)
               trade.PositionClose(ticket);
           }
        }
     };

   //--- pip/stop calculations
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pip = (digits==3 || digits==5) ? _Point*10.0 : _Point;
   double min_stop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   //--- BUY on bullish crossover
   if(bullish_cross && !HasMyPositionType(POSITION_TYPE_BUY))
     {
      // close opposite sells opened by this EA
      if(HasMyPositionType(POSITION_TYPE_SELL)) CloseMyPositionsOfType(POSITION_TYPE_SELL);

      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = price - StopLossPips * pip;
      double tp = price + TakeProfitPips * pip;

      if((price - sl) >= min_stop)
        {
         if(!trade.Buy(LotSize, _Symbol, 0, sl, tp, "Trend Following Buy"))
            PrintFormat("Buy failed: %s (%d)", trade.ResultRetcodeDescription(), trade.ResultRetcode());
        }
      else
         Print("Buy skipped: stop level too small");
     }

   //--- SELL on bearish crossunder
   else if(bearish_cross && !HasMyPositionType(POSITION_TYPE_SELL))
     {
      // close opposite buys opened by this EA
      if(HasMyPositionType(POSITION_TYPE_BUY)) CloseMyPositionsOfType(POSITION_TYPE_BUY);

      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = price + StopLossPips * pip;
      double tp = price - TakeProfitPips * pip;

      if((sl - price) >= min_stop)
        {
         if(!trade.Sell(LotSize, _Symbol, 0, sl, tp, "Trend Following Sell"))
            PrintFormat("Sell failed: %s (%d)", trade.ResultRetcodeDescription(), trade.ResultRetcode());
        }
      else
         Print("Sell skipped: stop level too small");
     }
  }