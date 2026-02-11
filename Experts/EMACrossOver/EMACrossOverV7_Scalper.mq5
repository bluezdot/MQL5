//+------------------------------------------------------------------+
//|                                     EMA_Cross_Scalper_100k.mq5   |
//|                                  Copyright 2026, Gemini Trading  |
//+------------------------------------------------------------------+
#property strict

// Input parameters
input int      FastEMA = 9;          // Chu kỳ EMA Nhanh
input int      SlowEMA = 21;         // Chu kỳ EMA Chậm
input double   LotSize = 1.0;        // Khối lượng lệnh (Khuyên dùng 1.0 cho 100k$)
input int      ATR_Period = 14;      // Chu kỳ ATR để tính StopLoss
input double   ATR_Multiplier = 2.0; // Hệ số nhân ATR cho SL
input int      TakeProfit_Pts = 500; // Chốt lời cố định (Point)
input int      MagicNumber = 123456;

// Global variables
int handleFastEMA, handleSlowEMA, handleATR;
double bufferFastEMA[], bufferSlowEMA[], bufferATR[];

int OnInit() {
   handleFastEMA = iMA(_Symbol, _Period, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   handleSlowEMA = iMA(_Symbol, _Period, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   handleATR     = iATR(_Symbol, _Period, ATR_Period);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   IndicatorRelease(handleFastEMA);
   IndicatorRelease(handleSlowEMA);
   IndicatorRelease(handleATR);
}

void OnTick() {
   // Copy dữ liệu indicator
   CopyBuffer(handleFastEMA, 0, 0, 3, bufferFastEMA);
   CopyBuffer(handleSlowEMA, 0, 0, 3, bufferSlowEMA);
   CopyBuffer(handleATR, 0, 0, 1, bufferATR);
   
   ArraySetAsSeries(bufferFastEMA, true);
   ArraySetAsSeries(bufferSlowEMA, true);

   // Kiểm tra điều kiện vào lệnh (Crossover)
   bool buyCondition = bufferFastEMA[1] > bufferSlowEMA[1] && bufferFastEMA[2] <= bufferSlowEMA[2];
   bool sellCondition = bufferFastEMA[1] < bufferSlowEMA[1] && bufferFastEMA[2] >= bufferSlowEMA[2];

   if(PositionsTotal() < 1) { // Chỉ mở 1 lệnh tại một thời điểm
      double sl_dist = bufferATR[0] * ATR_Multiplier;
      
      if(buyCondition) {
         double sl = SymbolInfoDouble(_Symbol, SYMBOL_BID) - sl_dist;
         double tp = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + TakeProfit_Pts * _Point;
         TradeOpen(ORDER_TYPE_BUY, sl, tp);
      }
      else if(sellCondition) {
         double sl = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + sl_dist;
         double tp = SymbolInfoDouble(_Symbol, SYMBOL_BID) - TakeProfit_Pts * _Point;
         TradeOpen(ORDER_TYPE_SELL, sl, tp);
      }
   }
}

void TradeOpen(ENUM_ORDER_TYPE type, double sl, double tp) {
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = type;
   request.price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = MagicNumber;
   
   OrderSend(request, result);
}