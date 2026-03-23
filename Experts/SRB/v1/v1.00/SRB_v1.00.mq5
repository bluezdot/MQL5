#property version   "1.00"
#property description "Support & Resistance Breakout (SRB) Expert Advisor - Fractal-based S/R detection"

#property strict
//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input int      InpMagicNumber   = 19; // Magic Number
input int      InpFractalPeriod = 5;       // Chu kỳ Fractal
input double   InpLotSize       = 0.1;     // Khối lượng vào lệnh
input double   InpRR            = 1.5;     // Tỷ lệ Reward/Risk
//+------------------------------------------------------------------+
//| Include files                                                    |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CTrade         trade;
int            handleFractals;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   handleFractals = iFractals(_Symbol, _Period);
   
   if(handleFractals == INVALID_HANDLE)
   {
      Print("Không thể khởi tạo chỉ báo Fractals");
      return(INIT_FAILED);
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Kiểm tra nến mới (Tránh vào lệnh liên tục trên 1 nến)
   static datetime last_bar;
   datetime current_bar = iTime(_Symbol, _Period, 0);
   if(last_bar == current_bar) return;
   last_bar = current_bar;

   // Lấy dữ liệu Fractal và giá
   double upper[], lower[];
   ArraySetAsSeries(upper, true);
   ArraySetAsSeries(lower, true);

   if(CopyBuffer(handleFractals, 0, 0, 50, upper) < 0) return;
   if(CopyBuffer(handleFractals, 1, 0, 50, lower) < 0) return;

   // Xác định Kháng cự (Resistance) và Hỗ trợ (Support) gần nhất
   double resistance = 0, support = 0;
   
   for(int i=2; i<50; i++) // Bỏ qua nến 0 và 1 vì Fractal cần nến xác nhận
   {
      if(resistance == 0 && upper[i] < EMPTY_VALUE) resistance = upper[i];
      if(support == 0 && lower[i] < EMPTY_VALUE) support = lower[i];
      if(resistance > 0 && support > 0) break;
   }

   double closePrice = iClose(_Symbol, _Period, 1);

   // KIỂM TRA ĐIỀU KIỆN VÀO LỆNH
   // Đếm lệnh thuộc EA này theo magic number
   int myPositions = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         myPositions++;
   }
   if(myPositions < 1) // Chỉ mở 1 lệnh tại một thời điểm
   {
      // 1. Lệnh BUY (Breakout Kháng cự)
      if(closePrice > resistance && resistance > 0)
      {
         double sl = support; // Stoploss tại Swing Low
         double tp = closePrice + (closePrice - sl) * InpRR;
         
         if(sl < closePrice) // Đảm bảo SL hợp lệ
         {
            trade.Buy(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), sl, tp, "Breakout Buy");
         }
      }
      
      // 2. Lệnh SELL (Breakout Hỗ trợ)
      else if(closePrice < support && support > 0)
      {
         double sl = resistance; // Stoploss tại Swing High
         double tp = closePrice - (sl - closePrice) * InpRR;
         
         if(sl > closePrice) // Đảm bảo SL hợp lệ
         {
            trade.Sell(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), sl, tp, "Breakout Sell");
         }
      }
   }
}