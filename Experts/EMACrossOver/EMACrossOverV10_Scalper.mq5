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
input int ShortPeriod = 9;      // Short EMA period
input int LongPeriod = 21;       // Long EMA period
input int LongtermPeriod = 200; // Long term EMA period
input int ATR_Period = 14;      // ATR period for Stop Loss
input double ATR_Multiplier = 2.0; // ATR multiplier for Stop Loss
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
   trade.SetExpertMagicNumber(12310);
   
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
   double ema_short[2], ema_long[2], ema_longterm[1], atr[1];

   if(CopyBuffer(ema_short_handle, 0, 1, 2, ema_short) != 2 ||
      CopyBuffer(ema_long_handle, 0, 1, 2, ema_long) != 2 ||
      CopyBuffer(ema_longterm_handle, 0, 1, 1, ema_longterm) != 1 ||
      CopyBuffer(atr_handle, 0, 1, 1, atr) != 1) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Crossover detection:
   bool isCrossUp = (ema_short[0] <= ema_long[0] && ema_short[1] > ema_long[1]);
   bool isCrossDown = (ema_short[0] >= ema_long[0] && ema_short[1] < ema_long[1]);

   bool hasPosition = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == 12310) {
         hasPosition = true;
         
         // Management Logic: Partial Close and Move SL to Entry
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         double volume = PositionGetDouble(POSITION_VOLUME);
         ulong ticket = PositionGetInteger(POSITION_TICKET);

         double risk = MathAbs(openPrice - sl);
         
         // Check if SL is not already at entry (avoid repeating)
         if(sl < openPrice && currentPrice >= openPrice + risk) {
            double lotToClose = NormalizeDouble(volume * 0.5, 2);
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(lotToClose >= minLot) {
               trade.PositionClosePartial(ticket, lotToClose);
            }
            trade.PositionModify(ticket, openPrice, tp);
            Print("REACHED TARGET: Partial Close 50% and SL moved to Entry for Buy Position #", ticket);
         }
         break;
      }
   }

  //--- check for buy signal (New Crossover + Filter)
   if(isCrossUp && ask > ema_longterm[0] && !hasPosition) {
      double risk = ATR_Multiplier * atr[0];
      double sl = NormalizeDouble(ask - risk, _Digits);
      double tp = NormalizeDouble(ask + (risk * RR_Ratio), _Digits);
      
      trade.Buy(LotSize, _Symbol, ask, sl, tp, "Open EMA Crossover Buy (New Cross + ATR SL)");
   }
   
  //--- check for exit signal (Opposite Crossover)
   else if(isCrossDown && hasPosition) {
      trade.PositionClose(_Symbol);
   }
}