#property version   "1.00"
#property description "Martingale Fibonacci Retracement DCA Expert Advisor - v1.00"
//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input double   InpBaseLot          = 0.01;      // Base Lot Size
input double   InpBaseTrendRange   = 100;       // Base Trend Price Range (Points)
input int      InpBaseTrendCandles = 3;         // Base Trend Number Candles
input long     InpMagicNumber      = 13;        // Magic Number
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
};

TrendState buyChain = {false, 0, 0, 1};
TrendState sellChain = {false, 0, 0, -1};
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
    CheckAndManageChain(buyChain);
    CheckAndManageChain(sellChain);

    if(!buyChain.active) ScanForTrend(1);
    if(!sellChain.active) ScanForTrend(-1);
    
    UpdateTP(1);
    UpdateTP(-1);
}

//+------------------------------------------------------------------+
//| Xác định xu hướng và Pullback                                    |
//+------------------------------------------------------------------+
void ScanForTrend(int dir) {
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, _Period, 0, InpBaseTrendCandles + 5, rates) < InpBaseTrendCandles + 2) return;

    bool isTrend = true;
    double range = 0;

    for(int i=1; i <= InpBaseTrendCandles; i++) {
        if(dir == 1) { // Buy Trend
            if(rates[i].close <= rates[i+1].close) isTrend = false;
        } else { // Sell Trend
            if(rates[i].close >= rates[i+1].close) isTrend = false;
        }
        range += MathAbs(rates[i].high - rates[i].low);
    }

    if(isTrend && range >= InpBaseTrendRange * _Point) {
        // Kiểm tra Pullback
        bool pullback = false;
        if(dir == 1) {
            double currentSwingHigh = rates[1].high;
            if(rates[0].close < rates[1].low) pullback = true;
            if(pullback) SetupDCAChain(1, currentSwingHigh, FindSwingLow(rates));
        } else {
            double currentSwingLow = rates[1].low;
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
    while(i < 20 && rates[i].low < rates[i+1].low) i++;
    return rates[i].low;
}

double FindSwingHigh(MqlRates &rates[]) {
    int i = 1;
    while(i < 20 && rates[i].high > rates[i+1].high) i++;
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
    double lowestFiboPrice = (dir == 1) ? 999999 : 0;
    double currentTP = 0;
    int count = 0;
    
    // Tìm lệnh đã khớp sâu nhất
    for(int i=PositionsTotal()-1; i>=0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            if((dir == 1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
               (dir == -1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) {
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                if(dir == 1) lowestFiboPrice = MathMin(lowestFiboPrice, openPrice);
                else lowestFiboPrice = MathMax(lowestFiboPrice, openPrice);
                count++;
            }
        }
    }

    if(count == 0) return;

    // Xác định mức TP theo logic Fibo
    TrendState active = (dir == 1) ? buyChain : sellChain;
    double diff = MathAbs(active.swingHigh - active.swingLow);
    double hitLevel = MathAbs(active.swingHigh - lowestFiboPrice) / diff;

    double targetFibo = 0;
    if(hitLevel <= 0.382) targetFibo = 0;
    else if(hitLevel <= 0.618) targetFibo = 0.236;
    else if(hitLevel <= 0.786) targetFibo = 0.5;
    else if(hitLevel <= 1.0)   targetFibo = 0.618;
    else if(hitLevel <= 1.618) targetFibo = 0.786;
    else if(hitLevel <= 2.618) targetFibo = 1.0;
    else if(hitLevel <= 3.618) targetFibo = 1.618;
    else targetFibo = 2.618;

    currentTP = (dir == 1) ? active.swingHigh - (targetFibo * diff) : active.swingHigh + (targetFibo * diff);

    // Áp dụng TP cho toàn bộ vị thế
    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            if(MathAbs(PositionGetDouble(POSITION_TP) - currentTP) > _Point) {
                trade.PositionModify(PositionGetTicket(i), 0, currentTP);
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
    
    // Kiểm tra nếu chưa khớp lệnh nào mà giá đã phá Swing High/Low (Fibo 0)
    int totalPos = 0;
    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            if((state.direction == 1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
               (state.direction == -1 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) totalPos++;
        }
    }

    if(totalPos == 0) {
        if((state.direction == 1 && currentPrice >= state.swingHigh) || 
           (state.direction == -1 && currentPrice <= state.swingHigh)) {
            CancelAllLimits(state.direction);
            state.active = false;
        }
    } else {
        // Nếu đã có vị thế nhưng không còn lệnh nào trong danh sách (đã hit TP)
        if(totalPos > 0 && !HasPositions(state.direction)) {
            CancelAllLimits(state.direction);
            state.active = false;
        }
    }
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