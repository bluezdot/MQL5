//+------------------------------------------------------------------+
//|                                     Robust_Gold_Scalper_V1.mq5   |
//|                                  Copyright 2026, Gemini Trading  |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

input group "=== Chiến thuật EMA ==="
input int      FastEMA      = 13;      // EMA Nhanh
input int      SlowEMA      = 48;      // EMA Chậm
input int      TrendEMA     = 200;     // EMA Xu hướng (Lọc nhiễu)

input group "=== Bộ lọc Động lượng ==="
input int      RSIPeriod    = 14;
input int      RSI_High     = 70;      // Vùng quá mua
input int      RSI_Low      = 30;      // Vùng quá bán

input group "=== Quản lý rủi ro (Vốn 100k$) ==="
input double   RiskPercent  = 0.5;     // Rủi ro 0.5% mỗi lệnh (~500$)
input double   ATR_Multiplier = 2.0;   // Khoảng cách SL theo ATR
input int      TrailingStart  = 150;   // Bắt đầu dời SL khi lãi x points
input int      TrailingStep   = 50;    // Bước dời SL

// Khai báo biến
CTrade trade;
int handleFast, handleSlow, handleTrend, handleRSI, handleATR;

int OnInit() {
   handleFast  = iMA(_Symbol, _Period, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   handleSlow  = iMA(_Symbol, _Period, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   handleTrend = iMA(_Symbol, _Period, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI   = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);
   handleATR   = iATR(_Symbol, _Period, 14);
   
   trade.SetExpertMagicNumber(123456);
   return(INIT_SUCCEEDED);
}

void OnTick() {
   double f[], s[], t[], r[], a[], closePrice[];
   CopyBuffer(handleFast, 0, 0, 3, f);
   CopyBuffer(handleSlow, 0, 0, 3, s);
   CopyBuffer(handleTrend, 0, 0, 3, t);
   CopyBuffer(handleRSI, 0, 0, 3, r);
   CopyBuffer(handleATR, 0, 0, 1, a);

   if(CopyClose(_Symbol, _Period, 0, 3, closePrice) < 3) return;

   ArraySetAsSeries(f, true); ArraySetAsSeries(s, true);
   ArraySetAsSeries(t, true); ArraySetAsSeries(r, true);
   ArraySetAsSeries(closePrice, true);

   // Kiểm tra vị thế hiện tại
   if(PositionsTotal() < 1) {
      // ĐIỀU KIỆN MUA: Fast cắt lên Slow + Giá trên TrendEMA + RSI chưa quá mua
      if(f[1] > s[1] && f[2] <= s[2] && closePrice[1] > t[1] && r[1] < RSI_High) {
         ExecuteTrade(ORDER_TYPE_BUY, a[0]);
      }
      // ĐIỀU KIỆN BÁN: Fast cắt xuống Slow + Giá dưới TrendEMA + RSI chưa quá bán
      if(f[1] < s[1] && f[2] >= s[2] && closePrice[1] < t[1] && r[1] > RSI_Low) {
         ExecuteTrade(ORDER_TYPE_SELL, a[0]);
      }
   } else {
      ApplyTrailingStop();
   }
}

void ExecuteTrade(ENUM_ORDER_TYPE type, double atrValue) {
   double slDistance = atrValue * ATR_Multiplier;
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   // Tính Lot dựa trên rủi ro (Money Management)
   double lot = NormalizeDouble(riskAmount / (slDistance / _Point * tickValue), 2);
   
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (type == ORDER_TYPE_BUY) ? price - slDistance : price + slDistance;
   
   trade.PositionOpen(_Symbol, type, lot, price, sl, 0, "Robust Scalper");
}

void ApplyTrailingStop() {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionGetSymbol(i) == _Symbol) {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            if(bid - openPrice > TrailingStart * _Point) {
               double newSL = bid - TrailingStep * _Point;
               if(newSL > currentSL) trade.PositionModify(ticket, newSL, 0);
            }
         } else {
            if(openPrice - ask > TrailingStart * _Point) {
               double newSL = ask + TrailingStep * _Point;
               if(currentSL == 0 || newSL < currentSL) trade.PositionModify(ticket, newSL, 0);
            }
         }
      }
   }
}