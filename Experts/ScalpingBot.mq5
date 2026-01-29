//+------------------------------------------------------------------+
//|                                              ScalpingBot_Pro.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.10"

#include <Trade\Trade.mqh>

//--- Input parameters
input int      InpRSI_Period = 14;          // RSI Period
input double   InpLotSize    = 0.1;         // Lot size
input int      InpTP_Pips    = 100;         // Take Profit (Pips)
input int      InpSL_Pips    = 50;          // Stop Loss (Pips)
input int      InpMagic      = 789012;      // Magic Number

//--- Global variables
CTrade trade;
int    rsi_handle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   rsi_handle = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_CLOSE);
   if(rsi_handle == INVALID_HANDLE) {
      Print("Lỗi tạo handle RSI");
      return(INIT_FAILED);
   }
   
   trade.SetExpertMagicNumber(InpMagic);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Lấy dữ liệu RSI (Lấy 3 nến: 0, 1, 2)
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(rsi_handle, 0, 0, 3, rsi) < 3) return;

   // rsi[1] là nến vừa đóng, rsi[2] là nến trước đó nữa
   double current_rsi = rsi[1];
   double prev_rsi    = rsi[2];

   // 2. Kiểm tra trạng thái lệnh của Bot này
   bool has_position = false;
   ulong ticket = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol) {
            has_position = true;
            ticket = PositionGetInteger(POSITION_TICKET);
            break;
         }
      }
   }

   // 3. Logic VÀO LỆNH (BUY)
   if(!has_position) {
      // Điều kiện: RSI cắt lên từ vùng quá bán (30)
      bool buy_signal = (prev_rsi < 30 && current_rsi >= 30);
      
      if(buy_signal) {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl  = NormalizeDouble(ask - InpSL_Pips * _Point, _Digits);
         double tp  = NormalizeDouble(ask + InpTP_Pips * _Point, _Digits);
         
         if(trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "Scalping Buy")) {
            Print("Vào lệnh BUY tại RSI: ", current_rsi);
         }
      }
   }
   
   // 4. Logic THOÁT LỆNH (EXIT)
   if(has_position) {
      // Thoát khi RSI quá mua (60) hoặc sau 5 phút
      bool sell_signal = (current_rsi > 60);
      
      // Kiểm tra thời gian
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      bool time_exit = (TimeCurrent() - open_time >= 300); // 300 giây = 5 phút
      
      if(sell_signal || time_exit) {
         if(trade.PositionClose(ticket)) {
            Print("Đóng lệnh. Lý do: ", (sell_signal ? "RSI > 60" : "Hết 5 phút"));
         }
      }
   }
}

void OnDeinit(const int reason) {
   IndicatorRelease(rsi_handle);
}