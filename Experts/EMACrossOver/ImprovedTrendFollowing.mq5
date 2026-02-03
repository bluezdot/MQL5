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
   trade.SetExpertMagicNumber(123457);
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
      // calculate SL and TP in prices
      double sl = ask - (StopLossPips * point * 10);   // SL below ask price
      double tp = ask + (TakeProfitPips * point * 10); // TP above ask price

      // open buy position
      trade.Buy(LotSize, _Symbol, 0, sl, tp, "Trend Following Buy");
     }
   
  //--- check for sell signal (close position)
   else if(ema_short[0] < ema_long[0] && PositionsTotal() > 0)
     {
      // close all positions
      trade.PositionClose(_Symbol);
     }
}
// void OnTick()
//   {
// //--- get EMA values
//    double ema_short[1], ema_long[1];
//    if(CopyBuffer(ema_short_handle, 0, 0, 1, ema_short) != 1 ||
//       CopyBuffer(ema_long_handle, 0, 0, 1, ema_long) != 1)
//      {
//       return;
//      }
   
// //--- get current prices
//    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
//    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
//    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
//    int stop_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

//    Print("Ask: ", ask, " Bid: ", bid, " EMA10: ", ema_short[0], " EMA20: ", ema_long[0], point);
   
// //--- check for buy signal
//    if(ema_short[0] > ema_long[0] && PositionsTotal() == 0)
//      {
//       // calculate SL and TP in prices
//       double sl = ask - (StopLossPips * point);
//       double tp = ask + (TakeProfitPips * point);
      
//       // ensure SL respects broker's minimum stop level
//       double min_sl = ask - (stop_level * point);
//       if(sl > min_sl)
//         {
//          sl = min_sl;
//          Print("SL adjusted to minimum level: ", sl);
//         }
      
//       // validate SL and TP
//       if(sl >= ask || tp <= ask)
//         {
//          Print("Invalid SL/TP: Ask=", ask, " SL=", sl, " TP=", tp, " Stop Level=", stop_level, " pips");
//          return;
//         }
      
//       // open buy position with SL and TP
//       if(trade.Buy(LotSize, _Symbol, sl, tp, 0, "Trend Following Buy"))
//         {
//          Print("Buy opened at Ask=", ask, " SL=", sl, " TP=", tp);
//         }
//       else
//         {
//          Print("Buy failed: Retcode=", trade.ResultRetcode(), " Description=", trade.ResultRetcodeDescription());
//          Print("Details: Ask=", ask, " SL=", sl, " TP=", tp, " StopLevel=", stop_level, " pips");
//         }
//      }
   
// //--- check for sell signal (open sell position)
//    else if(ema_short[0] < ema_long[0] && PositionsTotal() == 0)
//      {
//       // calculate SL and TP in prices for short
//       double sl = bid + (StopLossPips * point);   // SL above bid price (for short)
//       double tp = bid - (TakeProfitPips * point); // TP below bid price (for short)
      
//       // ensure SL respects broker's minimum stop level
//       double max_sl = bid + (stop_level * point);
//       if(sl < max_sl)
//         {
//          sl = max_sl;
//          Print("SL adjusted to minimum level: ", sl);
//         }
      
//       // validate SL and TP
//       if(sl <= bid || tp >= bid)
//         {
//          Print("Invalid SL/TP for Sell: Bid=", bid, " SL=", sl, " TP=", tp, " Stop Level=", stop_level, " pips");
//          return;
//         }
      
//       // open sell position with SL and TP
//       if(trade.Sell(LotSize, _Symbol, sl, tp, 0, "Trend Following Sell"))
//         {
//          Print("Sell opened at Bid=", bid, " SL=", sl, " TP=", tp);
//         }
//       else
//         {
//          Print("Sell failed: Retcode=", trade.ResultRetcode(), " Description=", trade.ResultRetcodeDescription());
//          Print("Details: Bid=", bid, " SL=", sl, " TP=", tp, " StopLevel=", stop_level, " pips");
//         }
//      }
   
// //--- check for close signal (close any open position)
//    else if(PositionsTotal() > 0)
//      {
//       // Get position type
//       ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
//       // Close BUY position if EMA 10 < EMA 20
//       if(pos_type == POSITION_TYPE_BUY && ema_short[0] < ema_long[0])
//         {
//          if(trade.PositionClose(_Symbol))
//            {
//             Print("Buy position closed at ", bid);
//            }
//         }
//       // Close SELL position if EMA 10 > EMA 20
//       else if(pos_type == POSITION_TYPE_SELL && ema_short[0] > ema_long[0])
//         {
//          if(trade.PositionClose(_Symbol))
//            {
//             Print("Sell position closed at ", ask);
//            }
//         }
//      }
//   }
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
