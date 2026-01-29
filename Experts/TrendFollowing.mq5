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
input double StopLossPips = 20;      // Stop Loss in pips
input double TakeProfitPips = 40;    // Take Profit in pips
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
//--- create timer
   EventSetTimer(60);
   
//--- create EMA handles
   ema_short_handle = iMA(_Symbol, _Period, 10, 0, MODE_EMA, PRICE_CLOSE);
   ema_long_handle = iMA(_Symbol, _Period, 20, 0, MODE_EMA, PRICE_CLOSE);
   
   if(ema_short_handle == INVALID_HANDLE || ema_long_handle == INVALID_HANDLE)
     {
      Print("Error creating EMA handles");
      return(INIT_FAILED);
     }
   
//--- set magic number
   trade.SetExpertMagicNumber(123456);
   
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
   
//--- release EMA handles
   IndicatorRelease(ema_short_handle);
   IndicatorRelease(ema_long_handle);
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
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
      // calculate SL and TP in prices
      double sl = ask - (StopLossPips * point);   // SL below ask price
      double tp = ask + (TakeProfitPips * point); // TP above ask price
      
      // open buy position with SL and TP
      if(trade.Buy(LotSize, _Symbol, sl, tp, 0, "Trend Following Buy"))
        {
         Print("Buy opened at ", ask, " SL=", sl, " TP=", tp);
        }
      else
        {
         Print("Buy failed: ", trade.ResultRetcode());
        }
     }
   
//--- check for sell signal (open sell position)
   else if(ema_short[0] < ema_long[0] && PositionsTotal() == 0)
     {
      // calculate SL and TP in prices for short
      double sl = bid + (StopLossPips * point);   // SL above bid price (for short)
      double tp = bid - (TakeProfitPips * point); // TP below bid price (for short)
      
      // open sell position with SL and TP
      if(trade.Sell(LotSize, _Symbol, sl, tp, 0, "Trend Following Sell"))
        {
         Print("Sell opened at ", bid, " SL=", sl, " TP=", tp);
        }
      else
        {
         Print("Sell failed: ", trade.ResultRetcode());
        }
     }
   
//--- check for close signal (close any open position)
   else if(PositionsTotal() > 0)
     {
      // Get position type
      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      // Close BUY position if EMA 10 < EMA 20
      if(pos_type == POSITION_TYPE_BUY && ema_short[0] < ema_long[0])
        {
         if(trade.PositionClose(_Symbol))
           {
            Print("Buy position closed at ", bid);
           }
        }
      // Close SELL position if EMA 10 > EMA 20
      else if(pos_type == POSITION_TYPE_SELL && ema_short[0] > ema_long[0])
        {
         if(trade.PositionClose(_Symbol))
           {
            Print("Sell position closed at ", ask);
           }
        }
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
