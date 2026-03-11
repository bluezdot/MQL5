#property version   "2.20"
//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input double   InpBaseLot             = 0.01;   // Base Lot Size
input double   InpBaseTrendRange      = 10000;  // Base Trend Price Range (Points) - hợp lý với M15
// 10000 - M15
// 30000 - M30
input int      InpBaseTrendCandles    = 3;      // Base Trend Number Candles
input int      InpMaxFindSwingCandles = 20;     // Max Number Candles to find swing
input long     InpMagicNumber         = 123456; // Magic Number
//+------------------------------------------------------------------+
//| Include files                                                    |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
double fiboLevels[] = {0.236, 0.382, 0.5, 0.618, 0.786, 1.0, 1.618, 2.618, 3.618, 4.236};
int    fiboMult[]   = {1, 1, 2, 3, 5, 8, 13, 21, 34, 55};

struct TrendState {
    bool   active;
    double anchor;       // Điểm neo GỐC: Buy = SwingHigh (đỉnh trend); Sell = SwingLow (đáy trend)
    double limit;        // Điểm giới hạn: Buy = SwingLow (đáy pullback); Sell = SwingHigh (đỉnh pullback)
    int    direction;    // 1: Buy, -1: Sell
    bool   hadPositions; // Flag đánh dấu đã từng có vị thế
};

// Công thức thống nhất cho cả 2 chiều:
//   diff         = MathAbs(anchor - limit)
//   Fibo price   = anchor ± fiboLevels[i] × diff   (Buy: -, Sell: +)
//   SL level     = anchor ± fiboLevels[9] × diff   (Buy: -, Sell: +)
//   TP           = anchor ± fiboLevels[idx-1] × diff
//   Reset khi giá phá anchor                        (Buy: price >= anchor, Sell: price <= anchor)

TrendState buyChain  = {false, 0, 0,  1, false};
TrendState sellChain = {false, 0, 0, -1, false};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(InpMagicNumber);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    CheckStopLoss();

    // Kiểm tra và quản lý chuỗi lệnh nếu có
    CheckAndManageChain(buyChain);
    CheckAndManageChain(sellChain);

    // Scan và thiết lập chuỗi lệnh nếu chưa có
    if(!buyChain.active)  ScanForTrend(1);
    if(!sellChain.active) ScanForTrend(-1);

    // Update TP dựa theo tick mới
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
            if((dir ==  1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
               (dir == -1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL))
                trade.PositionClose(ticket);
        }
    }
}

//+------------------------------------------------------------------+
//| Stop Loss: đóng lệnh khi nến đóng vượt ra ngoài grid Fibo        |
//| Công thức: deepestLevel = anchor ± 4.236 × diff                  |
//|   Buy:  SL khi closedClose < anchor - 4.236 × diff               |
//|   Sell: SL khi closedClose > anchor + 4.236 × diff               |
//+------------------------------------------------------------------+
void CheckStopLoss() {
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, _Period, 0);
    if(lastBar == currentBar) return;
    lastBar = currentBar;

    double closedClose = iClose(_Symbol, _Period, 1);

    // --- BUY chain ---
    if(buyChain.active && HasPositions(1)) {
        double diff         = MathAbs(buyChain.anchor - buyChain.limit);
        double deepestLevel = buyChain.anchor - (fiboLevels[9] * diff);
        if(closedClose < deepestLevel) {
            PrintFormat("[SL BUY] Nến đóng %.5f < Fibo 4.236 (%.5f) → Cắt lỗ!", closedClose, deepestLevel);
            CloseAllPositions(1);
            ResetChain(buyChain);
        }
    }

    // --- SELL chain ---
    if(sellChain.active && HasPositions(-1)) {
        double diff         = MathAbs(sellChain.anchor - sellChain.limit);
        double deepestLevel = sellChain.anchor + (fiboLevels[9] * diff);
        if(closedClose > deepestLevel) {
            PrintFormat("[SL SELL] Nến đóng %.5f > Fibo 4.236 (%.5f) → Cắt lỗ!", closedClose, deepestLevel);
            CloseAllPositions(-1);
            ResetChain(sellChain);
        }
    }
}

//+------------------------------------------------------------------+
//| Xác định xu hướng và Pullback                                    |
//+------------------------------------------------------------------+
void ScanForTrend(int dir) {
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    // rates[0]       = nến đang hình thành (live)
    // rates[1]       = nến pullback vừa đóng
    // rates[2..N+1]  = N nến trend cần kiểm tra
    // rates[N+2..]   = các nến cũ để tìm swing
    int barsNeeded = InpMaxFindSwingCandles + 3;
    if(CopyRates(_Symbol, _Period, 0, barsNeeded, rates) < barsNeeded) return;

    bool   isTrend = true;
    double range   = 0;

    // Điều kiện trend: Higher Close + Higher Low (Buy) / Lower Close + Lower High (Sell)
    // - Higher Close: xác nhận momentum (người mua/bán đang kiểm soát)
    // - Higher Low (Buy) / Lower High (Sell): xác nhận cấu trúc giá (Dow Theory nhẹ)
    for(int i = 2; i <= InpBaseTrendCandles + 1; i++) {
        if(dir == 1) {
            if(rates[i].close <= rates[i+1].close) isTrend = false; // Higher Close
            if(rates[i].low   <= rates[i+1].low)   isTrend = false; // Higher Low
        } else {
            if(rates[i].close >= rates[i+1].close) isTrend = false; // Lower Close
            if(rates[i].high  >= rates[i+1].high)  isTrend = false; // Lower High
        }
        range += MathAbs(rates[i].high - rates[i].low);
    }

    if(!isTrend || range < InpBaseTrendRange * _Point) return;

    if(dir == 1) {
        // anchor = SwingHigh: HIGH cao nhất trong cả N nến trend + nến pullback
        double swingHigh = rates[1].high;
        for(int k = 2; k <= InpBaseTrendCandles + 1; k++)
            swingHigh = MathMax(swingHigh, rates[k].high);

        if(rates[1].close < rates[2].low)
            SetupDCAChain(1, swingHigh, FindSwingLow(rates));

    } else {
        // anchor = SwingLow: LOW thấp nhất trong cả N nến trend + nến pullback
        double swingLow = rates[1].low;
        for(int k = 2; k <= InpBaseTrendCandles + 1; k++)
            swingLow = MathMin(swingLow, rates[k].low);

        if(rates[1].close > rates[2].high)
            SetupDCAChain(-1, swingLow, FindSwingHigh(rates));
    }
}

//+------------------------------------------------------------------+
//| Tìm Swing Low/High làm điểm limit                                |
//+------------------------------------------------------------------+
double FindSwingLow(MqlRates &rates[]) {
    int i = 2;
    while(i < InpMaxFindSwingCandles && rates[i].low >= rates[i+1].low) i++;
    return rates[i].low;
}

double FindSwingHigh(MqlRates &rates[]) {
    int i = 2;
    while(i < InpMaxFindSwingCandles && rates[i].high <= rates[i+1].high) i++;
    return rates[i].high;
}

//+------------------------------------------------------------------+
//| Thiết lập lưới lệnh DCA                                          |
//| anchor: điểm neo gốc (Buy = đỉnh trend, Sell = đáy trend)        |
//| limitPt: điểm giới hạn (Buy = đáy swing, Sell = đỉnh swing)      |
//| Công thức lưới:                                                   |
//|   Buy:  BuyLimit  tại anchor - fiboLevels[i] × diff              |
//|   Sell: SellLimit tại anchor + fiboLevels[i] × diff              |
//+------------------------------------------------------------------+
void SetupDCAChain(int dir, double anchor, double limitPt) {
    double diff = MathAbs(anchor - limitPt);
    double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if(dir == 1) {
        buyChain.active    = true;
        buyChain.anchor    = anchor;    // SwingHigh — đỉnh trend, neo trên
        buyChain.limit     = limitPt;  // SwingLow  — đáy swing, neo dưới
        for(int i = 0; i < 10; i++) {
            double price = anchor - (fiboLevels[i] * diff); // kéo XUỐNG từ anchor
            if(price >= ask) {
                PrintFormat("[DCA BUY] Skip Fibo %.3f (price=%.5f >= ask=%.5f)", fiboLevels[i], price, ask);
                continue;
            }
            if(!trade.BuyLimit(InpBaseLot * fiboMult[i], price, _Symbol, 0, 0))
                PrintFormat("[DCA BUY] Failed Fibo %.3f price=%.5f: %s", fiboLevels[i], price, trade.ResultRetcodeDescription());
        }
    } else {
        sellChain.active   = true;
        sellChain.anchor   = anchor;    // SwingLow  — đáy trend, neo dưới
        sellChain.limit    = limitPt;  // SwingHigh — đỉnh swing, neo trên
        for(int i = 0; i < 10; i++) {
            double price = anchor + (fiboLevels[i] * diff); // kéo LÊN từ anchor
            if(price <= bid) {
                PrintFormat("[DCA SELL] Skip Fibo %.3f (price=%.5f <= bid=%.5f)", fiboLevels[i], price, bid);
                continue;
            }
            if(!trade.SellLimit(InpBaseLot * fiboMult[i], price, _Symbol, 0, 0))
                PrintFormat("[DCA SELL] Failed Fibo %.3f price=%.5f: %s", fiboLevels[i], price, trade.ResultRetcodeDescription());
        }
    }
}

//+------------------------------------------------------------------+
//| Cập nhật Take Profit theo Level xấu nhất đã khớp                 |
//| TP = anchor ± fiboLevels[deepestIdx-1] × diff                    |
//|   Buy:  anchor - ... (TP kéo lên về phía anchor)                 |
//|   Sell: anchor + ... (TP kéo xuống về phía anchor)               |
//+------------------------------------------------------------------+
void UpdateTP(int dir) {
    double worstPrice = (dir == 1) ? DBL_MAX : 0;
    int    count      = 0;

    for(int i = PositionsTotal()-1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            if((dir ==  1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
               (dir == -1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) {
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                if(dir == 1) worstPrice = MathMin(worstPrice, openPrice); // BUY:  thấp nhất = xấu nhất
                else         worstPrice = MathMax(worstPrice, openPrice); // SELL: cao nhất  = xấu nhất
                count++;
            }
        }
    }
    if(count == 0) return;

    TrendState chain = (dir == 1) ? buyChain : sellChain;
    double diff = MathAbs(chain.anchor - chain.limit);

    // Tìm Fibo index gần nhất với giá entry xấu nhất
    int    deepestIdx = 0;
    double minDist    = DBL_MAX;
    for(int k = 0; k < 10; k++) {
        // Buy: giá lưới kéo xuống từ anchor; Sell: kéo lên từ anchor
        double fiboPrice = (dir == 1)
            ? chain.anchor - fiboLevels[k] * diff
            : chain.anchor + fiboLevels[k] * diff;
        double dist = MathAbs(worstPrice - fiboPrice);
        if(dist < minDist) { minDist = dist; deepestIdx = k; }
    }

    // TP = 1 bậc Fibo về phía anchor (gần điểm neo hơn)
    double currentTP;
    if(deepestIdx == 0) {
        currentTP = chain.anchor; // Đã ở mức nông nhất → TP chính là anchor
    } else {
        currentTP = (dir == 1)
            ? chain.anchor - fiboLevels[deepestIdx - 1] * diff  // Buy: TP kéo lên
            : chain.anchor + fiboLevels[deepestIdx - 1] * diff; // Sell: TP kéo xuống
    }

    for(int i = PositionsTotal()-1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            if((dir ==  1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
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
//| Reset khi giá phá anchor:                                        |
//|   Buy:  currentPrice >= anchor (vượt đỉnh → pullback không xảy ra)|
//|   Sell: currentPrice <= anchor (rơi dưới đáy → pullback sai)     |
//+------------------------------------------------------------------+
void CheckAndManageChain(TrendState &state) {
    if(!state.active) return;
    double currentPrice   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool   hasPos         = HasPositions(state.direction);
    bool   hasPendingOrds = HasPendingLimits(state.direction);

    if(hasPos) state.hadPositions = true;

    if(!hasPos) {
        // Trường hợp 1: Chưa khớp lệnh nào, giá phá anchor → xu hướng sai
        if((state.direction ==  1 && currentPrice >= state.anchor) ||
           (state.direction == -1 && currentPrice <= state.anchor)) {
            ResetChain(state);
            return;
        }

        // Trường hợp 2: Đã từng có vị thế, tất cả đã đóng (hit TP/SL)
        if(state.hadPositions) {
            ResetChain(state);
            return;
        }

        // Trường hợp 3: Không có vị thế VÀ không còn lệnh limit nào
        if(!hasPendingOrds) {
            ResetChain(state);
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Reset toàn bộ trạng thái chain                                   |
//+------------------------------------------------------------------+
void ResetChain(TrendState &state) {
    CancelAllLimits(state.direction);
    state.active       = false;
    state.hadPositions = false;
    state.anchor       = 0;
    state.limit        = 0;
}

//+------------------------------------------------------------------+
//| Hàm tiện ích                                                     |
//+------------------------------------------------------------------+
bool HasPositions(int dir) {
    for(int i = PositionsTotal()-1; i >= 0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            if((dir ==  1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
               (dir == -1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) return true;
        }
    }
    return false;
}

bool HasPendingLimits(int dir) {
    for(int i = OrdersTotal()-1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber) {
            if((dir ==  1 && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT) ||
               (dir == -1 && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT)) return true;
        }
    }
    return false;
}

void CancelAllLimits(int dir) {
    for(int i = OrdersTotal()-1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber) {
            if((dir ==  1 && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT) ||
               (dir == -1 && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT))
                trade.OrderDelete(ticket);
        }
    }
}
