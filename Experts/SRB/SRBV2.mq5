//+------------------------------------------------------------------+
//|                                                        SRBV2.mq5 |
//|              Support/Resistance Breakout Bot V2                  |
//|                    Copyright 2024, Gemini AI Agent               |
//+------------------------------------------------------------------+

#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//=== INPUT PARAMETERS ===
input group "=== KHUNG THỜI GIAN ==="
input ENUM_TIMEFRAMES  InpHTF              = PERIOD_H4;   // Khung thời gian lớn (HTF)

input group "=== CÀI ĐẶT VÙNG S/R ==="
input int              InpFractalLookback  = 100;         // Số nến lookback tìm Fractal
input double           InpZoneTolerance    = 10.0;        // Độ rộng vùng S/R (pip)
input int              InpMinTouches       = 2;           // Số lần test tối thiểu (zone strength)

input group "=== CÀI ĐẶT BREAKOUT ==="
input double           InpBreakoutBuffer   = 5.0;         // Buffer xác nhận breakout (pip)
input int              InpCooldownBars     = 5;           // Số nến cooldown sau breakout

input group "=== CÀI ĐẶT STOP LOSS ==="
input int              InpSwingLookback    = 20;          // Số nến tìm Swing High/Low
input double           InpSLBuffer         = 3.0;         // Buffer thêm vào SL (pip)
input double           InpMinSL            = 10.0;        // SL tối thiểu để mở lệnh (pip)

input group "=== TAKE PROFIT ==="
input double           InpRR               = 2.0;         // Tỷ lệ Risk/Reward

input group "=== QUẢN LÝ VỐN ==="
input bool             InpUseRiskPercent   = true;        // Dùng quản lý vốn theo %
input double           InpRiskPercent      = 1.0;         // % rủi ro mỗi lệnh
input double           InpLotSize          = 0.1;         // Lot cố định (khi tắt risk %)

input group "=== CÀI ĐẶT EA ==="
input int              InpMagicNumber      = 20240002;    // Magic Number

//=== GLOBAL VARIABLES ===
CTrade   trade;
int      handleFractalsEntry = INVALID_HANDLE;
int      handleFractalsHTF   = INVALID_HANDLE;
double   pipSize;
datetime lastBuyBreakoutBar  = 0;
datetime lastSellBreakoutBar = 0;

//=== STRUCTURE: S/R Zone ===
struct SRZone
{
   double level;       // Đường S/R chính (trung tâm)
   double upper;       // Mép trên zone
   double lower;       // Mép dưới zone
   int    touches;     // Số lần price test zone
   bool   htfConfirm;  // Có confluence với HTF không
};

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   handleFractalsEntry = iFractals(_Symbol, _Period);
   handleFractalsHTF   = iFractals(_Symbol, InpHTF);

   if(handleFractalsEntry == INVALID_HANDLE || handleFractalsHTF == INVALID_HANDLE)
   {
      Print("Lỗi: Không thể khởi tạo chỉ báo Fractals");
      return INIT_FAILED;
   }

   // Tính pip size (hỗ trợ cả 4 và 5 chữ số thập phân)
   pipSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) pipSize *= 10.0;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);

   PrintFormat("SRBV2 khởi tạo | Symbol: %s | Entry TF: %s | HTF: %s | PipSize: %.5f",
               _Symbol, EnumToString(_Period), EnumToString(InpHTF), pipSize);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleFractalsEntry != INVALID_HANDLE) IndicatorRelease(handleFractalsEntry);
   if(handleFractalsHTF   != INVALID_HANDLE) IndicatorRelease(handleFractalsHTF);
}

//+------------------------------------------------------------------+
//| Kiểm tra EA có vị thế đang mở không                             |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Tìm Swing Low trong n nến gần nhất (bắt đầu từ nến index 2)    |
//+------------------------------------------------------------------+
double FindSwingLow(int lookback)
{
   double swingLow = DBL_MAX;
   for(int i = 2; i <= lookback + 1; i++)
   {
      double lo = iLow(_Symbol, _Period, i);
      if(lo < swingLow) swingLow = lo;
   }
   return (swingLow == DBL_MAX) ? 0.0 : swingLow;
}

//+------------------------------------------------------------------+
//| Tìm Swing High trong n nến gần nhất (bắt đầu từ nến index 2)   |
//+------------------------------------------------------------------+
double FindSwingHigh(int lookback)
{
   double swingHigh = 0.0;
   for(int i = 2; i <= lookback + 1; i++)
   {
      double hi = iHigh(_Symbol, _Period, i);
      if(hi > swingHigh) swingHigh = hi;
   }
   return swingHigh;
}

//+------------------------------------------------------------------+
//| Đếm số lần giá test một zone (nến overlap với zone)             |
//+------------------------------------------------------------------+
int CountZoneTouches(double zUpper, double zLower, int lookback)
{
   int touches = 0;
   for(int i = 2; i < lookback; i++)
   {
      double hi = iHigh(_Symbol, _Period, i);
      double lo = iLow(_Symbol, _Period, i);
      if(lo <= zUpper && hi >= zLower)
         touches++;
   }
   return touches;
}

//+------------------------------------------------------------------+
//| Xây dựng danh sách vùng S/R từ Fractals (Entry TF + HTF)       |
//+------------------------------------------------------------------+
void BuildSRZones(SRZone &resistances[], SRZone &supports[])
{
   ArrayResize(resistances, 0);
   ArrayResize(supports,    0);

   double tol = InpZoneTolerance * pipSize;

   // --- Thu thập Fractals từ HTF ---
   double htfUp[], htfLo[];
   ArraySetAsSeries(htfUp, true);
   ArraySetAsSeries(htfLo, true);
   if(CopyBuffer(handleFractalsHTF, 0, 0, InpFractalLookback, htfUp) <= 0) return;
   if(CopyBuffer(handleFractalsHTF, 1, 0, InpFractalLookback, htfLo) <= 0) return;

   double htfResArr[], htfSupArr[];
   ArrayResize(htfResArr, 0);
   ArrayResize(htfSupArr, 0);
   for(int i = 2; i < InpFractalLookback; i++)
   {
      if(htfUp[i] < EMPTY_VALUE) { int s = ArraySize(htfResArr); ArrayResize(htfResArr, s+1); htfResArr[s] = htfUp[i]; }
      if(htfLo[i] < EMPTY_VALUE) { int s = ArraySize(htfSupArr); ArrayResize(htfSupArr, s+1); htfSupArr[s] = htfLo[i]; }
   }

   // --- Thu thập Fractals từ Entry TF ---
   double entUp[], entLo[];
   ArraySetAsSeries(entUp, true);
   ArraySetAsSeries(entLo, true);
   if(CopyBuffer(handleFractalsEntry, 0, 0, InpFractalLookback, entUp) <= 0) return;
   if(CopyBuffer(handleFractalsEntry, 1, 0, InpFractalLookback, entLo) <= 0) return;

   // --- Xây dựng Resistance zones ---
   for(int i = 2; i < InpFractalLookback; i++)
   {
      if(entUp[i] >= EMPTY_VALUE) continue;
      double level = entUp[i];

      // Merge vào zone gần nhất nếu trong phạm vi 2*tol
      bool merged = false;
      for(int z = 0; z < ArraySize(resistances); z++)
      {
         if(MathAbs(resistances[z].level - level) <= tol * 2.0)
         {
            resistances[z].level = (resistances[z].level + level) / 2.0;
            resistances[z].upper = resistances[z].level + tol;
            resistances[z].lower = resistances[z].level - tol;
            merged = true;
            break;
         }
      }
      if(!merged)
      {
         int n = ArraySize(resistances);
         ArrayResize(resistances, n + 1);
         resistances[n].level     = level;
         resistances[n].upper     = level + tol;
         resistances[n].lower     = level - tol;
         resistances[n].touches   = 0;
         resistances[n].htfConfirm = false;
      }
   }

   // --- Xây dựng Support zones ---
   for(int i = 2; i < InpFractalLookback; i++)
   {
      if(entLo[i] >= EMPTY_VALUE) continue;
      double level = entLo[i];

      bool merged = false;
      for(int z = 0; z < ArraySize(supports); z++)
      {
         if(MathAbs(supports[z].level - level) <= tol * 2.0)
         {
            supports[z].level = (supports[z].level + level) / 2.0;
            supports[z].upper = supports[z].level + tol;
            supports[z].lower = supports[z].level - tol;
            merged = true;
            break;
         }
      }
      if(!merged)
      {
         int n = ArraySize(supports);
         ArrayResize(supports, n + 1);
         supports[n].level     = level;
         supports[n].upper     = level + tol;
         supports[n].lower     = level - tol;
         supports[n].touches   = 0;
         supports[n].htfConfirm = false;
      }
   }

   // --- Tính touches và HTF confluence cho từng zone ---
   for(int z = 0; z < ArraySize(resistances); z++)
   {
      resistances[z].touches = CountZoneTouches(resistances[z].upper, resistances[z].lower, InpFractalLookback);
      for(int h = 0; h < ArraySize(htfResArr); h++)
         if(MathAbs(htfResArr[h] - resistances[z].level) <= tol * 2.0)
            { resistances[z].htfConfirm = true; break; }
   }
   for(int z = 0; z < ArraySize(supports); z++)
   {
      supports[z].touches = CountZoneTouches(supports[z].upper, supports[z].lower, InpFractalLookback);
      for(int h = 0; h < ArraySize(htfSupArr); h++)
         if(MathAbs(htfSupArr[h] - supports[z].level) <= tol * 2.0)
            { supports[z].htfConfirm = true; break; }
   }

   // --- Lọc: chỉ giữ zone đủ tiêu chí (HTF confluence HOẶC đủ touches) ---
   int rCount = 0;
   for(int z = 0; z < ArraySize(resistances); z++)
      if(resistances[z].htfConfirm || resistances[z].touches >= InpMinTouches)
         resistances[rCount++] = resistances[z];
   ArrayResize(resistances, rCount);

   int sCount = 0;
   for(int z = 0; z < ArraySize(supports); z++)
      if(supports[z].htfConfirm || supports[z].touches >= InpMinTouches)
         supports[sCount++] = supports[z];
   ArrayResize(supports, sCount);
}

//+------------------------------------------------------------------+
//| Tính lot theo % rủi ro vốn                                      |
//+------------------------------------------------------------------+
double CalculateLot(double entryPrice, double slPrice)
{
   if(!InpUseRiskPercent) return InpLotSize;

   double slPips = MathAbs(entryPrice - slPrice) / pipSize;
   if(slPips <= 0.0) return InpLotSize;

   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk     = balance * InpRiskPercent / 100.0;
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pipVal   = tickVal * pipSize / tickSize;

   double lot  = risk / (slPips * pipVal);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   lot = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                 MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), lot));
   return lot;
}

//+------------------------------------------------------------------+
//| Kiểm tra cooldown: đã vào lệnh cùng chiều trong n nến gần đây? |
//+------------------------------------------------------------------+
bool IsInCooldown(bool isBuy)
{
   datetime refBar = isBuy ? lastBuyBreakoutBar : lastSellBreakoutBar;
   if(refBar == 0) return false;
   int shift = iBarShift(_Symbol, _Period, refBar, false);
   return (shift >= 0 && shift <= InpCooldownBars);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Chỉ xử lý khi hình thành nến mới
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, _Period, 0);
   if(lastBar == currentBar) return;
   lastBar = currentBar;

   // Đã có lệnh mở → bỏ qua
   if(HasOpenPosition()) return;

   // Xây dựng vùng S/R
   SRZone resistances[], supports[];
   BuildSRZones(resistances, supports);

   int numR = ArraySize(resistances);
   int numS = ArraySize(supports);

   // Lấy data nến vừa đóng (index 1)
   double closePrice = iClose(_Symbol, _Period, 1);
   double openPrice  = iOpen (_Symbol, _Period, 1);
   double bufPips    = InpBreakoutBuffer * pipSize;
   double maxDist    = 50.0 * pipSize; // Khoảng cách tối đa zone → close

   // --- Tìm Resistance vừa bị phá (nằm dưới close, trong phạm vi maxDist) ---
   double nearestRes = 0.0;
   for(int z = 0; z < numR; z++)
   {
      double R = resistances[z].level;
      if(closePrice > R + bufPips && (closePrice - R) <= maxDist)
         if(R > nearestRes) nearestRes = R;
   }

   // --- Tìm Support vừa bị phá (nằm trên close, trong phạm vi maxDist) ---
   double nearestSup = 0.0;
   for(int z = 0; z < numS; z++)
   {
      double S = supports[z].level;
      if(closePrice < S - bufPips && (S - closePrice) <= maxDist)
         if(nearestSup == 0.0 || S < nearestSup) nearestSup = S;
   }

   //=== TÍN HIỆU BUY ===
   if(nearestRes > 0.0 && !IsInCooldown(true))
   {
      // Xác nhận body breakout: thân nến nằm trên resistance (không chỉ shadow)
      if(MathMin(openPrice, closePrice) > nearestRes)
      {
         double swingLow = FindSwingLow(InpSwingLookback);
         double entry    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl       = swingLow - InpSLBuffer * pipSize;
         double slPips   = (entry - sl) / pipSize;

         if(swingLow > 0.0 && slPips >= InpMinSL)
         {
            double tp  = entry + (entry - sl) * InpRR;
            double lot = CalculateLot(entry, sl);

            if(trade.Buy(lot, _Symbol, entry, sl, tp, "SRB_BUY"))
            {
               lastBuyBreakoutBar = iTime(_Symbol, _Period, 1);
               PrintFormat("[SRB BUY] Entry:%.5f | SL:%.5f (%.1f pip) | TP:%.5f | Lot:%.2f | R-Zone:%.5f",
                           entry, sl, slPips, tp, lot, nearestRes);
            }
         }
         else
            PrintFormat("[SRB BUY skip] SL=%.1f pip < Min=%.1f pip | SwingLow:%.5f", slPips, InpMinSL, swingLow);
      }
   }
   //=== TÍN HIỆU SELL ===
   else if(nearestSup > 0.0 && !IsInCooldown(false))
   {
      // Xác nhận body breakout: thân nến nằm dưới support
      if(MathMax(openPrice, closePrice) < nearestSup)
      {
         double swingHigh = FindSwingHigh(InpSwingLookback);
         double entry     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl        = swingHigh + InpSLBuffer * pipSize;
         double slPips    = (sl - entry) / pipSize;

         if(swingHigh > 0.0 && slPips >= InpMinSL)
         {
            double tp  = entry - (sl - entry) * InpRR;
            double lot = CalculateLot(entry, sl);

            if(trade.Sell(lot, _Symbol, entry, sl, tp, "SRB_SELL"))
            {
               lastSellBreakoutBar = iTime(_Symbol, _Period, 1);
               PrintFormat("[SRB SELL] Entry:%.5f | SL:%.5f (%.1f pip) | TP:%.5f | Lot:%.2f | S-Zone:%.5f",
                           entry, sl, slPips, tp, lot, nearestSup);
            }
         }
         else
            PrintFormat("[SRB SELL skip] SL=%.1f pip < Min=%.1f pip | SwingHigh:%.5f", slPips, InpMinSL, swingHigh);
      }
   }

   //=== HIỂN THỊ THÔNG TIN DEBUG ===
   Comment(StringFormat(
      "=== SRBV2 ===\n"
      "Symbol: %s | TF: %s | HTF: %s\n"
      "Close[1]: %.5f\n"
      "Resistance zones: %d | Vừa phá: %s\n"
      "Support zones:    %d | Vừa phá: %s\n"
      "Buy cooldown: %s | Sell cooldown: %s",
      _Symbol, EnumToString(_Period), EnumToString(InpHTF),
      closePrice,
      numR, nearestRes > 0.0 ? DoubleToString(nearestRes, _Digits) : "N/A",
      numS, nearestSup > 0.0 ? DoubleToString(nearestSup, _Digits) : "N/A",
      IsInCooldown(true)  ? "YES" : "NO",
      IsInCooldown(false) ? "YES" : "NO"
   ));
}
//+------------------------------------------------------------------+
