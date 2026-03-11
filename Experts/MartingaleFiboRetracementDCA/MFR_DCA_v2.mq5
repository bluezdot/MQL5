#property version   "2.00"
//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input double   InpBaseLot          = 0.01;      // Base Lot Size
input double   InpBaseTrendRange   = 10000;     // Base Trend Price Range (Points) - hợp lý với M15
// 30000 - M30
input int      InpBaseTrendCandles = 3;         // Base Trend Number Candles
input int      InpMaxFindSwingCandles = 20;     // Max Number Candles to find swing
input long     InpMagicNumber      = 123456;    // Magic Number
//+------------------------------------------------------------------+
//| Include files                                                    |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CTrade         trade;
double         fiboLevels[] = {0.236, 0.382, 0.5, 0.618, 0.786, 1.0, 1.618, 2.618, 3.618, 4.236};
int            fiboMult[]   = {1, 1, 2, 3, 5, 8, 13, 21, 34, 55};

struct TrendState {
    bool active;
    double swingHigh;
    double swingLow;
    int direction; // 1: Buy, -1: Sell
    bool hadPositions;  // Flag đánh dấu đã từng có vị thế
};

TrendState buyChain  = {false, 0, 0,  1, false};
TrendState sellChain = {false, 0, 0, -1, false};
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
    trade.SetExpertMagicNumber(InpMagicNumber);
    return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Ưu tiên kiểm tra Stop Loss trước mọi logic khác
    CheckStopLoss();

    // Kiểm tra và quản lý chuỗi lệnh
    CheckAndManageChain(buyChain);
    CheckAndManageChain(sellChain);

    // Kiểm tra và thiết lập chuỗi lệnh nếu chưa có
    if(!buyChain.active) ScanForTrend(true);
    if(!sellChain.active) ScanForTrend(false);
    
    // Liên tục update TP dựa theo tick mới
    UpdateTP(1);
    UpdateTP(-1);
}

//+------------------------------------------------------------------+
//| Đóng tất cả vị thế theo hướng                                    |
//+------------------------------------------------------------------+
void CloseAllPositions(int dir) {
    for(int i = PositionsTotal()-1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            if((dir == 1  && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
               (dir == -1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) {
                trade.PositionClose(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Stop Loss: đóng lệnh khi nến đóng vượt ra ngoài grid Fibo        |
//+------------------------------------------------------------------+
void CheckStopLoss() {
    // Chỉ xử lý khi có nến mới đóng hoàn thành
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, _Period, 0);
    if(lastBar == currentBar) return;
    lastBar = currentBar;

    // Lấy giá đóng cửa của nến vừa hoàn thành (index 1)
    double closedClose = iClose(_Symbol, _Period, 1);

    // --- Kiểm tra BUY chain ---
    if(buyChain.active && HasPositions(1)) {
        double diff = MathAbs(buyChain.swingHigh - buyChain.swingLow);
        // Mức Fibo sâu nhất (4.236) = giá BuyLimit thấp nhất trong grid
        double deepestBuyLevel = buyChain.swingHigh - (fiboLevels[9] * diff);

        if(closedClose < deepestBuyLevel) {
            PrintFormat("[SL BUY] Nến đóng %.5f < Fibo 4.236 (%.5f) → Cắt lỗ!", closedClose, deepestBuyLevel);
            CloseAllPositions(1);
            ResetChain(buyChain);
        }
    }

    // --- Kiểm tra SELL chain ---
    if(sellChain.active && HasPositions(-1)) {
        double diff = MathAbs(sellChain.swingHigh - sellChain.swingLow);
        // Mức Fibo sâu nhất (4.236) = giá SellLimit cao nhất trong grid
        double deepestSellLevel = sellChain.swingLow + (fiboLevels[9] * diff);

        if(closedClose > deepestSellLevel) {
            PrintFormat("[SL SELL] Nến đóng %.5f > Fibo 4.236 (%.5f) → Cắt lỗ!", closedClose, deepestSellLevel);
            CloseAllPositions(-1);
            ResetChain(sellChain);
        }
    }
}

//+------------------------------------------------------------------+
//| Xác định xu hướng và Pullback                                    |
//+------------------------------------------------------------------+
void ScanForTrend(bool isBuy) {
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int barsNeeded = MathMax(InpBaseTrendCandles + 2, InpMaxFindSwingCandles + 2);
    if(CopyRates(_Symbol, _Period, 0, barsNeeded, rates) < barsNeeded) return;

    // Assume trend is true
    bool isTrend = true;
    // To sum up range
    double range = 0;

    for(int i=1; i <= InpBaseTrendCandles; i++) {
        if(isBuy) {
            if(rates[i].close <= rates[i+1].close) isTrend = false;
        } else {
            if(rates[i].close >= rates[i+1].close) isTrend = false;
        }
        range += MathAbs(rates[i].high - rates[i].low);
    }

    if(isTrend && range >= InpBaseTrendRange * _Point) {
        bool pullback = false;
        if(isBuy) {
            // Lấy HIGH cao nhất bao gồm cả nến hiện tại (rates[0]) đến hết trend candles
            double currentSwingHigh = rates[0].high;
            for(int k = 1; k <= InpBaseTrendCandles; k++)
                currentSwingHigh = MathMax(currentSwingHigh, rates[k].high);

            if(rates[0].close < rates[1].low) pullback = true;
            if(pullback) SetupDCAChain(1, currentSwingHigh, FindSwingLow(rates));
        } else {
            // Lấy LOW thấp nhất bao gồm cả nến hiện tại (rates[0]) đến hết trend candles
            double currentSwingLow = rates[0].low;
            for(int k = 1; k <= InpBaseTrendCandles; k++)
                currentSwingLow = MathMin(currentSwingLow, rates[k].low);

            if(rates[0].close > rates[1].high) pullback = true;
            if(pullback) SetupDCAChain(-1, currentSwingLow, FindSwingHigh(rates));
        }
    }
}

//+------------------------------------------------------------------+
//| Tìm Swing Low/High cho Fibonacci                                 |
//+------------------------------------------------------------------+
double FindSwingLow(MqlRates &rates[]) {
    int i = 1;
    while(i < InpMaxFindSwingCandles && rates[i].low >= rates[i+1].low) i++;
    return rates[i].low;
}

double FindSwingHigh(MqlRates &rates[]) {
    int i = 1;
    while(i < InpMaxFindSwingCandles && rates[i].high <= rates[i+1].high) i++;
    return rates[i].high;
}

//+------------------------------------------------------------------+
//| Thiết lập lưới lệnh DCA                                          |
//+------------------------------------------------------------------+
void SetupDCAChain(int dir, double f0, double f1) {
    double diff = MathAbs(f0 - f1);
    if(dir == 1) {
        buyChain.active = true;
        buyChain.swingHigh = f0;
        buyChain.swingLow = f1;
        for(int i=0; i<10; i++) {
            double price = f0 - (fiboLevels[i] * diff);
            trade.BuyLimit(InpBaseLot * fiboMult[i], price, _Symbol, 0, 0);
        }
    } else {
        sellChain.active = true;
        sellChain.swingHigh = f1;
        sellChain.swingLow = f0;
        for(int i=0; i<10; i++) {
            double price = f0 + (fiboLevels[i] * diff);
            trade.SellLimit(InpBaseLot * fiboMult[i], price, _Symbol, 0, 0);
        }
    }
}

//+------------------------------------------------------------------+
//| Cập nhật Take Profit theo Level thấp nhất/cao nhất đã khớp       |
//+------------------------------------------------------------------+
void UpdateTP(int dir) {
    double worstPrice = (dir == 1) ? 999999 : 0;
    int count = 0;
    
    // Tìm giá entry xấu nhất trong các vị thế đang mở
    for(int i = PositionsTotal()-1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            if((dir == 1  && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
               (dir == -1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) {
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                if(dir == 1) worstPrice = MathMin(worstPrice, openPrice); // BUY:  thấp nhất = xấu nhất
                else         worstPrice = MathMax(worstPrice, openPrice); // SELL: cao nhất  = xấu nhất
                count++;
            }
        }
    }
    if(count == 0) return;

    TrendState active = (dir == 1) ? buyChain : sellChain;
    double diff = MathAbs(active.swingHigh - active.swingLow);

    // Tìm Fibo level (index) gần nhất với giá entry xấu nhất
    int deepestIdx = 0;
    double minDist = DBL_MAX;
    for(int k = 0; k < 10; k++) {
        double fiboEntryPrice = (dir == 1)
            ? active.swingHigh - fiboLevels[k] * diff  
            : active.swingLow  + fiboLevels[k] * diff; 
        double dist = MathAbs(worstPrice - fiboEntryPrice);
        if(dist < minDist) {
            minDist = dist;
            deepestIdx = k;
        }
    }

    // TP = mức Fibo ngay phía trên deepestIdx (1 bước gần hơn điểm neo)
    double currentTP;
    if(deepestIdx == 0) {
        currentTP = (dir == 1) ? active.swingHigh : active.swingLow;
    } else {
        currentTP = (dir == 1)
            ? active.swingHigh - fiboLevels[deepestIdx - 1] * diff  
            : active.swingLow  + fiboLevels[deepestIdx - 1] * diff; 
    }

    // Áp dụng TP cho vị thế đúng hướng (chỉ BUY hoặc chỉ SELL)
    for(int i = PositionsTotal()-1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            if((dir == 1  && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
               (dir == -1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) {
                if(MathAbs(PositionGetDouble(POSITION_TP) - currentTP) > _Point) {
                    double currentSL = PositionGetDouble(POSITION_SL); // Giữ nguyên SL
                    trade.PositionModify(ticket, currentSL, currentTP);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Quản lý và Reset Chain                                           |
//+------------------------------------------------------------------+
void CheckAndManageChain(TrendState &state) {
    if(!state.active) return;
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool hasPos = HasPositions(state.direction);
    bool hasPendingOrders = HasPendingLimits(state.direction);

    // Ghi nhận từng có vị thế khi có lệnh đang mở
    if(hasPos) state.hadPositions = true;

    if(!hasPos) {
        // Trường hợp 1: Chưa khớp lệnh nào, giá phá swing → xu hướng sai
        // Buy: giá vượt lên trên SwingHigh → pullback không xảy ra, xu hướng sai
        // Sell: giá rơi xuống dưới SwingLow → pullback không xảy ra, xu hướng sai
        if((state.direction == 1  && currentPrice >= state.swingHigh) ||
           (state.direction == -1 && currentPrice <= state.swingLow)) {
            ResetChain(state);
            return;
        }

        // Trường hợp 2: Đã từng có vị thế, tất cả đã đóng (hit TP/SL)
        //               Còn lệnh limit treo → hủy hết và reset chain
        if(state.hadPositions) {
            ResetChain(state);
            return;
        }

        // Trường hợp 3: Không có vị thế VÀ không còn lệnh limit nào
        //               (chain còn active nhưng không còn gì để quản lý)
        if(!hasPendingOrders) {
            ResetChain(state);
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Reset toàn bộ trạng thái chain về giá trị mặc định              |
//+------------------------------------------------------------------+
void ResetChain(TrendState &state) {
    CancelAllLimits(state.direction);
    state.active       = false;
    state.hadPositions = false;
    state.swingHigh    = 0;   // Reset để tránh dùng giá trị cũ
    state.swingLow     = 0;   // Reset để tránh dùng giá trị cũ
}

bool HasPositions(int dir) {
    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            if((dir == 1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
               (dir == -1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) return true;
        }
    }
    return false;
}

bool HasPendingLimits(int dir) {
    for(int i = OrdersTotal()-1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber) {
            if((dir == 1  && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT) ||
               (dir == -1 && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT))
                return true;
        }
    }
    return false;
}

void CancelAllLimits(int dir) {
    for(int i=OrdersTotal()-1; i>=0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber) {
            if((dir == 1 && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT) ||
               (dir == -1 && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT)) {
                trade.OrderDelete(ticket);
            }
        }
    }
}

// Improved so với V1
// - Fix Rule đặt TP
// - Fix Rule Reset Chain: Khi có lệnh cắn TP thì phải reset chain
// - Bổ sung Stoploss
// - Fix logic vào lệnh (Kẻ fibonacci)