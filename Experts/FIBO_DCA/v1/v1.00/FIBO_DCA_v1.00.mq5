#property version   "1.00"
#property description "Fibonacci DCA Expert Advisor - v1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- WinAPI for file operations
#import "kernel32.dll"
int CreateDirectoryW(string path, int lpSecurityAttributes);
int MoveFileW(string lpExistingFileName, string lpNewFileName);
#import


//--- Enums
enum ENUM_TRADE_DIRECTION
  {
   DIRECTION_BUY,  // Only Buy
   DIRECTION_SELL, // Only Sell
   DIRECTION_BOTH  // Both Buy and Sell (Bidirectional DCA)
  };

//--- Inputs
input string             InpLabel1      = "=== Trading Settings ==="; 
input long               InpMagic       = 11;         // Magic Number
input ENUM_TRADE_DIRECTION InpDirection = DIRECTION_BUY;  // Trade Direction (Chieu giao dich)
input double             InpLots        = 0.01;           // Initial Lot Size (Khoi luong khoi tao)
input int                InpStepPoints  = 200;            // Grid Step (Points)
input double             InpStepMultiplier = 1.1;         // Step Multiplier (Ty le tang step)
input double             InpTakeProfitPercent = 0.12;     // Target Profit (% of Balance)
input int                InpMaxOrders   = 27;             // Max Orders per Direction (So lenh toi da moi chieu)
input int                InpSlippage    = 3;              // Slippage
input int                InpRangeMargin = 600;            // Margin for Dynamic Range (Points)

input string             InpLabel2      = "=== Drawdown Protection ===";
input bool               InpEnableDrawdownProtection = true; // Enable Drawdown Protection (Bat bao ve rut von)
input double             InpInitBalance = 200000;            // Reference Balance for Scaling (So du tham chieu)
input double             InpMaxDrawdownPercent = 30;         // Max Drawdown % (% rut von toi da)

input string             InpLabel3      = "=== Basket Protection & Recovery ===";
input int                InpProtectionThreshold = 6;        // Min Positions for Protection (So lenh kich hoat bao ve)
input int                InpProtectionStepPoints = 200;      // Protection Step (Khoang cach DCA tang cuong)
input double             InpProtectionStepMultiplier = 1.1;  // Protection Step Multiplier (Ty le tang step)
input double             InpProtectionLotMultiplier = 1.5;   // Protection Lot Multiplier (Ty le tang lot)
input double             InpProtectionTakeProfitPercent = 10.0; // Protection Target Profit/Loss (% of Balance)

input string             InpLabel4      = "=== Statistics & Export ===";
input string             InpExportPath   = "";               // Absolute Export Path (Empty to disable), VD: C:\MT5\manager\bots\DCA\FinbonaciDCA\test_result

//--- Global Objects
CTrade         m_trade;
CSymbolInfo    m_symbol;
CPositionInfo  m_position;

//--- Global Variables for Dynamic Range
double         g_MinPrice = 0.0;
double         g_MaxPrice = 0.0;

//--- Global Variables for Drawdown Protection
double         g_InitialBalance = 0.0;
double         g_PeakBalance = 0.0;
int            g_ScaleRatio = 1;              // Auto-calculated scaling ratio

//--- Global Variables for Equity Export
int            g_EquityFileHandle = INVALID_HANDLE;
string         g_EquityFileName = "";
string         g_SessionFolder = "";
datetime       g_LastLogTime = 0;

//+------------------------------------------------------------------+
//| Helper: Calculate Trading Range from Previous Day (D1)           |
//+------------------------------------------------------------------+
void CalculateTradingRange()
  {
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   // Copy index 1 (yesterday) for 1 bar on D1 timeframe
   if(CopyHigh(Symbol(), PERIOD_D1, 1, 1, high) > 0 && 
      CopyLow(Symbol(), PERIOD_D1, 1, 1, low) > 0)
     {
      double d1_high = high[0];
      double d1_low  = low[0];
      double margin_value = InpRangeMargin * m_symbol.Point();
      
      // Calculate dynamic limits
      g_MaxPrice = d1_high + margin_value;
      g_MinPrice = d1_low - margin_value;
      
      PrintFormat("Updated Trading Range: Min=%.5f, Max=%.5f (D1 High=%.5f, Low=%.5f, Margin=%d)", 
                  g_MinPrice, g_MaxPrice, d1_high, d1_low, InpRangeMargin);
     }
   else
     {
      Print("Error copying D1 price data: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Initialize Trade Object
   m_trade.SetExpertMagicNumber(InpMagic);
   m_trade.SetDeviationInPoints(InpSlippage);
   
   // Initialize Symbol
   if(!m_symbol.Name(Symbol()))
     {
      Print("Failed to initialize symbol");
      return(INIT_FAILED);
     }

   // Initialize timer for 1 hour (3600 seconds)
   EventSetTimer(3600);
   
   // Calculate initial range
   CalculateTradingRange();
   
   // Initialize drawdown protection
   g_InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_PeakBalance = g_InitialBalance;
   
   // Initialize session folder name
   g_SessionFolder = StringFormat("%s_%d_%d", Symbol(), (int)InpMagic, (int)TimeCurrent());
   
   PrintFormat("FibonacciDCA EA Initialized - Initial Balance: %.2f", g_InitialBalance);
   
   // Initialize Equity Export if in tester and path is provided
   if(MQLInfoInteger(MQL_TESTER) && InpExportPath != "")
     {
      InitEquityExport();
     }
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   
   // Export trades if in tester and path is provided
   if(MQLInfoInteger(MQL_TESTER) && InpExportPath != "")
     {
      // 1. Export Trades History
      ExportTradesToCSV();
      
      // 2. Export H1 Price Data
      ExportPriceDataToCSV();
      
      // 3. Close and Move Equity Curve
      if(g_EquityFileHandle != INVALID_HANDLE)
        {
         FileClose(g_EquityFileHandle);
         g_EquityFileHandle = INVALID_HANDLE;
         
         // Move the equity file to absolute path\session_folder\balance.csv
         MoveToAbsolutePath(g_EquityFileName, "balance.csv");
        }
        
      // 4. Export Inputs
      ExportInputsToSet();
     }
   else if(g_EquityFileHandle != INVALID_HANDLE)
     {
      FileClose(g_EquityFileHandle);
      g_EquityFileHandle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
  {
   CalculateTradingRange();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Refresh rates
   if(!m_symbol.RefreshRates())
      return;

   // Calculate scale ratio based on current balance vs reference balance
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(InpInitBalance > 0)
     {
      double ratio = current_balance / InpInitBalance;
      g_ScaleRatio = (int)MathMax(1.0, MathFloor(ratio));
     }
   else
     {
      g_ScaleRatio = 1;
     }

   // Check drawdown protection
   if(InpEnableDrawdownProtection)
     {
      if(!CheckDrawdownProtection())
         return; // Drawdown exceeded, trading stopped
     }

   // Determine which directions to trade
   bool trade_buy = (InpDirection == DIRECTION_BUY || InpDirection == DIRECTION_BOTH);
   bool trade_sell = (InpDirection == DIRECTION_SELL || InpDirection == DIRECTION_BOTH);

   // Separate variables for BUY and SELL positions
   int buy_positions = 0, sell_positions = 0;
   double buy_last_price = 0, sell_last_price = 0;
   double buy_total_volume = 0, sell_total_volume = 0;
   double buy_total_value = 0, sell_total_value = 0;
   double buy_average = 0, sell_average = 0;
   double buy_profit_money = 0, sell_profit_money = 0;

   // 1. Analyze existing positions - separate by direction
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(m_position.SelectByIndex(i))
        {
         if(m_position.Symbol() == Symbol() && m_position.Magic() == InpMagic)
           {
            double price = m_position.PriceOpen();
            double vol = m_position.Volume();
            double pos_profit = m_position.Profit() + m_position.Swap() + m_position.Commission();
            
            // Track BUY positions
            if(m_position.PositionType() == POSITION_TYPE_BUY)
              {
               buy_positions++;
               
               // Track the lowest entry price for BUY (worst entry)
               if(buy_last_price == 0 || price < buy_last_price)
                  buy_last_price = price;
                  
               buy_total_volume += vol;
               buy_total_value += price * vol;
               buy_profit_money += pos_profit;
              }
            // Track SELL positions
            else if(m_position.PositionType() == POSITION_TYPE_SELL)
              {
               sell_positions++;
               
               // Track the highest entry price for SELL (worst entry)
               if(sell_last_price == 0 || price > sell_last_price)
                  sell_last_price = price;
                  
               sell_total_volume += vol;
               sell_total_value += price * vol;
               sell_profit_money += pos_profit;
              }
           }
        }
     }

   // Calculate weighted average prices
   if(buy_total_volume > 0)
      buy_average = buy_total_value / buy_total_volume;
   if(sell_total_volume > 0)
      sell_average = sell_total_value / sell_total_volume;

   // 2. Removed Basket Protection early close
   // CheckBasketProtection logic was removed.

   // 3. BUY Position Logic
   if(trade_buy)
     {
      ProcessBuyLogic(buy_positions, buy_last_price, buy_average);
     }

   // 4. SELL Position Logic
   if(trade_sell)
     {
      ProcessSellLogic(sell_positions, sell_last_price, sell_average);
     }

   // 5. Check Target Profit via Cash Value
   CheckBasketTakeProfit(buy_positions, buy_profit_money, sell_positions, sell_profit_money);

   // 6. Log Balance and Equity if in tester and path is provided
   if(MQLInfoInteger(MQL_TESTER) && InpExportPath != "" && g_EquityFileHandle != INVALID_HANDLE)
     {
      LogEquityStatus();
     }
  }

//+------------------------------------------------------------------+
//| Helper: Get Fibonacci Sequence Number                            |
//+------------------------------------------------------------------+
int GetFibonacciRatio(int n)
  {
   // n is the index of the trade (0-based)
   // Trade 1 (n=0): 1
   // Trade 2 (n=1): 1
   // Trade 3 (n=2): 2
   // Trade 4 (n=3): 3
   // Trade 5 (n=4): 5
   
   if(n <= 1) return 1;
   
   int prev2 = 1;
   int prev1 = 1;
   int current = 1;
   
   for(int i = 2; i <= n; i++)
     {
      current = prev1 + prev2;
      prev2 = prev1;
      prev1 = current;
     }
   return current;
  }

//+------------------------------------------------------------------+
//| Helper: Process BUY Position Logic (DCA mua)                     |
//+------------------------------------------------------------------+
void ProcessBuyLogic(int buy_positions, double buy_last_price, double buy_average)
  {
   // Check price range limits
   if(g_MaxPrice > 0 && g_MinPrice > 0)
     {
      if(m_symbol.Ask() < g_MinPrice || m_symbol.Ask() > g_MaxPrice)
         return;
     }

   // NO BUY POSITIONS: Open Initial Buy
   if(buy_positions == 0)
     {
      CancelPendingOrders(ORDER_TYPE_BUY_LIMIT);
      
      double lot = NormalizeLot(InpLots * g_ScaleRatio);
      bool res = m_trade.Buy(lot, Symbol(), m_symbol.Ask(), 0, 0, "Initial Buy");
      if(res)
         PrintFormat("Opened Initial BUY: Lot=%.2f (Scale=%d), Price=%.5f", lot, g_ScaleRatio, m_symbol.Ask());
      else
         PrintFormat("Failed Initial BUY: Error=%d, %s", m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
     }
   // DCA LOGIC: Add to position if price dropped
   else if(buy_positions < InpMaxOrders)
     {
      // Calculate progressive step
      double dynamic_step = 0;
      if(buy_positions < InpProtectionThreshold)
        {
         // Normal DCA
         double base_step = InpStepPoints * m_symbol.Point();
         double multiplier = MathPow(InpStepMultiplier, buy_positions - 1);
         dynamic_step = base_step * multiplier;
        }
      else
        {
         // Protection DCA (with new grid size and multiplier)
         double base_step = InpProtectionStepPoints * m_symbol.Point();
         double multiplier = MathPow(InpProtectionStepMultiplier, buy_positions - InpProtectionThreshold);
         dynamic_step = base_step * multiplier;
        }
      
      double step_price = buy_last_price - dynamic_step;
      
      // Check if a Pending Buy Limit already exists
      bool limit_exists = false;
      for(int o = OrdersTotal() - 1; o >= 0; o--)
        {
         ulong ticket = OrderGetTicket(o);
         if(OrderGetInteger(ORDER_MAGIC) == InpMagic && 
            OrderGetString(ORDER_SYMBOL) == Symbol() &&
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT)
           {
            limit_exists = true;
            break;
           }
        }
      
      if(!limit_exists)
        {
         // Calculate lot scaling based on phase
         double new_lot = 0;
         if(buy_positions < InpProtectionThreshold)
           {
            // Normal Fibonacci phase
            int fib_ratio = GetFibonacciRatio(buy_positions);
            new_lot = InpLots * fib_ratio * g_ScaleRatio;
           }
         else
           {
            // Protection phase (new lot multiplier)
            int threshold_fib = GetFibonacciRatio(InpProtectionThreshold);
            double base_lot = InpLots * threshold_fib * g_ScaleRatio;
            new_lot = base_lot * MathPow(InpProtectionLotMultiplier, buy_positions - InpProtectionThreshold + 1);
           }
         
         new_lot = NormalizeLot(new_lot);
         step_price = NormalizeDouble(step_price, m_symbol.Digits());
         
         bool res = m_trade.BuyLimit(new_lot, step_price, Symbol(), 0, 0, ORDER_TIME_GTC, 0, "DCA Buy Limit #" + IntegerToString(buy_positions + 1));
         
         if(res)
            PrintFormat("Placed DCA BUY Limit #%d: Lot=%.2f, Price=%.5f", buy_positions + 1, new_lot, step_price);
         else
            PrintFormat("DCA BUY Limit Failed: Error=%d", m_trade.ResultRetcode());
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Process SELL Position Logic (DCA ban)                    |
//+------------------------------------------------------------------+
void ProcessSellLogic(int sell_positions, double sell_last_price, double sell_average)
  {
   // Check price range limits
   if(g_MaxPrice > 0 && g_MinPrice > 0)
     {
      if(m_symbol.Bid() < g_MinPrice || m_symbol.Bid() > g_MaxPrice)
         return;
     }

   // NO SELL POSITIONS: Open Initial Sell
   if(sell_positions == 0)
     {
      CancelPendingOrders(ORDER_TYPE_SELL_LIMIT);
      
      double lot = NormalizeLot(InpLots * g_ScaleRatio);
      bool res = m_trade.Sell(lot, Symbol(), m_symbol.Bid(), 0, 0, "Initial Sell");
      if(res)
         PrintFormat("Opened Initial SELL: Lot=%.2f (Scale=%d), Price=%.5f", lot, g_ScaleRatio, m_symbol.Bid());
      else
         PrintFormat("Failed Initial SELL: Error=%d, %s", m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
     }
   // DCA LOGIC: Add to position if price rose
   else if(sell_positions < InpMaxOrders)
     {
      // Calculate progressive step
      double dynamic_step = 0;
      if(sell_positions < InpProtectionThreshold)
        {
         // Normal DCA
         double base_step = InpStepPoints * m_symbol.Point();
         double multiplier = MathPow(InpStepMultiplier, sell_positions - 1);
         dynamic_step = base_step * multiplier;
        }
      else
        {
         // Protection DCA (with new grid size and multiplier)
         double base_step = InpProtectionStepPoints * m_symbol.Point();
         double multiplier = MathPow(InpProtectionStepMultiplier, sell_positions - InpProtectionThreshold);
         dynamic_step = base_step * multiplier;
        }
      
      double step_price = sell_last_price + dynamic_step;
      
      // Check if a Pending Sell Limit already exists
      bool limit_exists = false;
      for(int o = OrdersTotal() - 1; o >= 0; o--)
        {
         ulong ticket = OrderGetTicket(o);
         if(OrderGetInteger(ORDER_MAGIC) == InpMagic && 
            OrderGetString(ORDER_SYMBOL) == Symbol() &&
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT)
           {
            limit_exists = true;
            break;
           }
        }
      
      if(!limit_exists)
        {
         // Calculate lot scaling based on phase
         double new_lot = 0;
         if(sell_positions < InpProtectionThreshold)
           {
            // Normal Fibonacci phase
            int fib_ratio = GetFibonacciRatio(sell_positions);
            new_lot = InpLots * fib_ratio * g_ScaleRatio;
           }
         else
           {
            // Protection phase (new lot multiplier)
            int threshold_fib = GetFibonacciRatio(InpProtectionThreshold);
            double base_lot = InpLots * threshold_fib * g_ScaleRatio;
            new_lot = base_lot * MathPow(InpProtectionLotMultiplier, sell_positions - InpProtectionThreshold + 1);
           }
         
         new_lot = NormalizeLot(new_lot);
         step_price = NormalizeDouble(step_price, m_symbol.Digits());
         
         bool res = m_trade.SellLimit(new_lot, step_price, Symbol(), 0, 0, ORDER_TIME_GTC, 0, "DCA Sell Limit #" + IntegerToString(sell_positions + 1));
         
         if(res)
            PrintFormat("Placed DCA SELL Limit #%d: Lot=%.2f, Price=%.5f", sell_positions + 1, new_lot, step_price);
         else
            PrintFormat("DCA SELL Limit Failed: Error=%d", m_trade.ResultRetcode());
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Check Basket Take Profit and Close                       |
//+------------------------------------------------------------------+
void CheckBasketTakeProfit(int buy_positions, double buy_profit_money, 
                           int sell_positions, double sell_profit_money)
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Check BUY basket
   if(buy_positions > 0)
     {
      double target_percent = (buy_positions >= InpProtectionThreshold) ? InpProtectionTakeProfitPercent : InpTakeProfitPercent;
      double target_cash = balance * (target_percent / 100.0);
      
      if(buy_profit_money >= target_cash)
        {
         PrintFormat(">>> BUY Basket Profit Target Reached! Target: $%.2f, Profit: $%.2f. Closing %d positions.", target_cash, buy_profit_money, buy_positions);
         ClosePositionsByDirection(POSITION_TYPE_BUY);
        }
     }
   
   // Check SELL basket
   if(sell_positions > 0)
     {
      double target_percent = (sell_positions >= InpProtectionThreshold) ? InpProtectionTakeProfitPercent : InpTakeProfitPercent;
      double target_cash = balance * (target_percent / 100.0);
      
      if(sell_profit_money >= target_cash)
        {
         PrintFormat(">>> SELL Basket Profit Target Reached! Target: $%.2f, Profit: $%.2f. Closing %d positions.", target_cash, sell_profit_money, sell_positions);
         ClosePositionsByDirection(POSITION_TYPE_SELL);
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Close Positions By Direction                             |
//+------------------------------------------------------------------+
void ClosePositionsByDirection(ENUM_POSITION_TYPE type)
  {
   // Cancel all pending orders matching the direction to prevent new orders from executing
   if(type == POSITION_TYPE_BUY)
      CancelPendingOrders(ORDER_TYPE_BUY_LIMIT);
   else if(type == POSITION_TYPE_SELL)
      CancelPendingOrders(ORDER_TYPE_SELL_LIMIT);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(m_position.SelectByIndex(i))
        {
         if(m_position.Symbol() == Symbol() && m_position.Magic() == InpMagic && m_position.PositionType() == type)
           {
            ulong ticket = m_position.Ticket();
            if(m_trade.PositionClose(ticket))
              {
               PrintFormat("Closed %s position #%llu", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"), ticket);
              }
            else
              {
               PrintFormat("Failed to close position #%llu. Error=%d", ticket, m_trade.ResultRetcode());
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Normalize Lot Size                                       |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   double min  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   
   // Snap to step
   if(step > 0)
      lot = step * MathFloor(lot / step);
      
   // Clamp to limits
   if(lot < min) lot = min;
   if(lot > max) lot = max;
   
   return lot;
  }

//+------------------------------------------------------------------+
//| Helper: Cancel Pending Orders by Type (-1 for all)               |
//+------------------------------------------------------------------+
void CancelPendingOrders(int type)
  {
   for(int o = OrdersTotal() - 1; o >= 0; o--)
     {
      ulong ticket = OrderGetTicket(o);
      if(OrderGetInteger(ORDER_MAGIC) == InpMagic && 
         OrderGetString(ORDER_SYMBOL) == Symbol())
        {
         if(type == -1 || OrderGetInteger(ORDER_TYPE) == type)
           {
            m_trade.OrderDelete(ticket);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Close All Positions                                      |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   CancelPendingOrders(-1);
   
   int total = PositionsTotal();
   int closed = 0;
   
   for(int i = total - 1; i >= 0; i--)
     {
      if(m_position.SelectByIndex(i))
        {
         if(m_position.Symbol() == Symbol() && m_position.Magic() == InpMagic)
           {
            ulong ticket = m_position.Ticket();
            if(m_trade.PositionClose(ticket))
              {
               closed++;
               PrintFormat("Closed position #%llu", ticket);
              }
            else
              {
               PrintFormat("Failed to close position #%llu: Error=%d", ticket, m_trade.ResultRetcode());
              }
           }
        }
     }
   
   PrintFormat("*** Closed %d/%d positions ***", closed, total);
  }

// CheckBasketProtection was removed

//+------------------------------------------------------------------+
//| Helper: Check Drawdown and Close All if Exceeded                 |
//| Returns false if drawdown exceeded threshold                     |
//+------------------------------------------------------------------+
bool CheckDrawdownProtection()
  {
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Update peak balance
   if(current_balance > g_PeakBalance)
      g_PeakBalance = current_balance;
   
   // Calculate drawdown from initial balance
   double drawdown_amount = g_InitialBalance - current_equity;
   double drawdown_percent = (drawdown_amount / g_InitialBalance) * 100.0;
   
   // Scale the drawdown threshold based on account growth
   double scaled_threshold = InpMaxDrawdownPercent * g_ScaleRatio;
   
   // Check if drawdown exceeds scaled threshold
   if(drawdown_percent >= scaled_threshold)
     {
      PrintFormat("*** DRAWDOWN ALERT *** Drawdown: %.2f%% exceeds scaled limit %.2f%% (base=%.2f%%, scale=%d)", 
                  drawdown_percent, scaled_threshold, InpMaxDrawdownPercent, g_ScaleRatio);
      PrintFormat("Initial Balance: %.2f, Current Equity: %.2f", g_InitialBalance, current_equity);
      
      // Close all positions immediately
      CloseAllPositions();
      
      // Send notification
      string msg = StringFormat("EA FibonacciDCA - DRAWDOWN PROTECTION!\nDrawdown: %.2f%%\nThreshold: %.2f%%\nBalance: %.2f -> %.2f\nAll positions closed.",
                                drawdown_percent, scaled_threshold, g_InitialBalance, current_equity);
      SendNotification(msg);
      
      PrintFormat("*** ALL POSITIONS CLOSED DUE TO DRAWDOWN ***");
      
      return false; // Stop trading
     }
   
   return true; // Continue trading
  }

//+------------------------------------------------------------------+
//| Helper: Export Trade History to CSV (Strategy Tester Only)       |
//+------------------------------------------------------------------+
void ExportTradesToCSV()
  {
   if(!HistorySelect(0, TimeCurrent()))
     {
      Print("Failed to select history for export");
      return;
     }

   int total_deals = HistoryDealsTotal();
   if(total_deals == 0)
     {
      Print("No deals found to export");
      return;
     }

   string filename = StringFormat("Trades_Export_%s_%d_%d.csv", Symbol(), (int)InpMagic, (int)TimeCurrent());
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("Failed to open file %s for writing. Error: %d", filename, GetLastError());
      return;
     }

   // Write Header
   FileWrite(handle, "Ticket", "Order", "Time", "Symbol", "Type", "Entry", "Volume", "Price", "Profit", "Commission", "Swap", "Comment");

   int exported_count = 0;
   for(int i = 0; i < total_deals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
        {
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(magic != InpMagic) continue; // Filter by magic number

         long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue; // Only export trade deals

         ulong order = HistoryDealGetInteger(ticket, DEAL_ORDER);
         datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         string sym = HistoryDealGetString(ticket, DEAL_SYMBOL);
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
         string comment = HistoryDealGetString(ticket, DEAL_COMMENT);

         string str_type = (type == DEAL_TYPE_BUY) ? "BUY" : "SELL";
         string str_entry = (entry == DEAL_ENTRY_IN) ? "IN" : (entry == DEAL_ENTRY_OUT) ? "OUT" : "IN/OUT";

         FileWrite(handle, (string)ticket, (string)order, TimeToString(time), sym, str_type, str_entry, (string)volume, (string)price, (string)profit, (string)commission, (string)swap, comment);
         exported_count++;
        }
     }

   FileClose(handle);
   PrintFormat("Successfully exported trades to MQL5/Files/%s", filename);
   
   // Move to absolute path\session_folder\trades.csv
   MoveToAbsolutePath(filename, "trades.csv");
  }

//+------------------------------------------------------------------+
//| Helper: Move file from MQL5/Files to Absolute Path Subfolder     |
//+------------------------------------------------------------------+
void MoveToAbsolutePath(string sandbox_filename, string target_name)
  {
   if(InpExportPath == "") return;

   // 1. Get source path (MQL5/Files)
   string src_path = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + sandbox_filename;

   // 2. Prepare destination folder and path
   string base_folder = InpExportPath;
   if(StringSubstr(base_folder, StringLen(base_folder)-1) == "\\")
      base_folder = StringSubstr(base_folder, 0, StringLen(base_folder)-1);
      
   string session_folder_path = base_folder + "\\" + g_SessionFolder;
   string dest_path = session_folder_path + "\\" + target_name;

   // 3. Create directories
   CreateDirectoryW(base_folder, 0);
   CreateDirectoryW(session_folder_path, 0);

   // 4. Move and rename file
   if(MoveFileW(src_path, dest_path) != 0)
      PrintFormat("File saved successfully to: %s", dest_path);
   else
      PrintFormat("Failed to move file to: %s. Error: %d", dest_path, GetLastError());
  }

//+------------------------------------------------------------------+
//| Helper: Initialize Equity/Balance Export File                    |
//+------------------------------------------------------------------+
void InitEquityExport()
  {
   g_EquityFileName = "temp_balance_" + IntegerToString(InpMagic) + ".csv";
   g_EquityFileHandle = FileOpen(g_EquityFileName, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   
   if(g_EquityFileHandle != INVALID_HANDLE)
     {
      FileWrite(g_EquityFileHandle, "Time", "Balance", "Equity");
      PrintFormat("Equity export initialized: %s", g_EquityFileName);
     }
   else
     {
      PrintFormat("Failed to initialize equity export. Error: %d", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Helper: Log Current Account Status (Balance & Equity)            |
//+------------------------------------------------------------------+
void LogEquityStatus()
  {
   if(g_EquityFileHandle == INVALID_HANDLE) return;

   datetime current_time = TimeCurrent();
   
   // Log once per hour (3600 seconds) to keep file size reasonable
   if(current_time >= g_LastLogTime + 3600)
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      
      FileWrite(g_EquityFileHandle, TimeToString(current_time), (string)balance, (string)equity);
      g_LastLogTime = current_time;
     }
  }

//+------------------------------------------------------------------+
//| Helper: Export Inputs to .set File                               |
//+------------------------------------------------------------------+
void ExportInputsToSet()
  {
   if(InpExportPath == "") return;

   string filename = StringFormat("Inputs_%s_%d_%d.set", Symbol(), (int)InpMagic, (int)TimeCurrent());
   int handle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_UNICODE);
   
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("Failed to open file %s for writing. Error: %d", filename, GetLastError());
      return;
     }

   FileWrite(handle, "; saved on " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   FileWrite(handle, "; this file contains input parameters for testing/optimizing FibonacciDCA expert advisor");
   FileWrite(handle, "; to use it in the strategy tester, click Load in the context menu of the Inputs tab");
   FileWrite(handle, ";");
   
   FileWrite(handle, StringFormat("InpLabel1=%s||0||0||0||N", InpLabel1));
   FileWrite(handle, StringFormat("InpMagic=%d||0||0||0||N", InpMagic));
   FileWrite(handle, StringFormat("InpDirection=%d||0||0||0||N", InpDirection));
   FileWrite(handle, StringFormat("InpLots=%g||0.0||0.0||0.0||N", InpLots));
   FileWrite(handle, StringFormat("InpStepPoints=%d||0||0||0||N", InpStepPoints));
   FileWrite(handle, StringFormat("InpStepMultiplier=%g||0.0||0.0||0.0||N", InpStepMultiplier));
   FileWrite(handle, StringFormat("InpTakeProfitPercent=%g||0.0||0.0||0.0||N", InpTakeProfitPercent));
   FileWrite(handle, StringFormat("InpMaxOrders=%d||0||0||0||N", InpMaxOrders));
   FileWrite(handle, StringFormat("InpSlippage=%d||0||0||0||N", InpSlippage));
   FileWrite(handle, StringFormat("InpRangeMargin=%d||0||0||0||N", InpRangeMargin));
   
   FileWrite(handle, StringFormat("InpLabel2=%s||0||0||0||N", InpLabel2));
   FileWrite(handle, StringFormat("InpEnableDrawdownProtection=%s||false||0||true||N", InpEnableDrawdownProtection ? "true" : "false"));
   FileWrite(handle, StringFormat("InpInitBalance=%g||0.0||0.0||0.0||N", InpInitBalance));
   FileWrite(handle, StringFormat("InpMaxDrawdownPercent=%g||0.0||0.0||0.0||N", InpMaxDrawdownPercent));
   
   FileWrite(handle, StringFormat("InpLabel3=%s||0||0||0||N", InpLabel3));
   FileWrite(handle, StringFormat("InpProtectionThreshold=%d||0||0||0||N", InpProtectionThreshold));
   FileWrite(handle, StringFormat("InpProtectionStepPoints=%d||0||0||0||N", InpProtectionStepPoints));
   FileWrite(handle, StringFormat("InpProtectionStepMultiplier=%g||0.0||0.0||0.0||N", InpProtectionStepMultiplier));
   FileWrite(handle, StringFormat("InpProtectionLotMultiplier=%g||0.0||0.0||0.0||N", InpProtectionLotMultiplier));
   
   FileWrite(handle, StringFormat("InpLabel4=%s||0||0||0||N", InpLabel4));
   FileWrite(handle, StringFormat("InpExportPath=%s||||||||N", InpExportPath));
   
   FileClose(handle);
   PrintFormat("Successfully exported inputs to MQL5/Files/%s", filename);
   
   MoveToAbsolutePath(filename, "input.set");
  }

//+------------------------------------------------------------------+
//| Helper: Export H1 Price Data to CSV (Strategy Tester Only)       |
//+------------------------------------------------------------------+
void ExportPriceDataToCSV()
  {
   if(!MQLInfoInteger(MQL_TESTER)) return;

   string filename = StringFormat("Price_H1_%s_%d_%d.csv", Symbol(), (int)InpMagic, (int)TimeCurrent());
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("Failed to open file %s for writing. Error: %d", filename, GetLastError());
      return;
     }

   // Write Header
   FileWrite(handle, "Time", "Open", "High", "Low", "Close", "TickVolume", "Spread", "RealVolume");

   MqlRates rates[];
   ArraySetAsSeries(rates, false); // sort: oldest to newest
   
   int bars = Bars(Symbol(), PERIOD_H1);
   if(bars > 0 && CopyRates(Symbol(), PERIOD_H1, 0, bars, rates) > 0)
     {
      int total = ArraySize(rates);
      for(int i = 0; i < total; i++)
        {
         FileWrite(handle, 
                   TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES),
                   DoubleToString(rates[i].open, m_symbol.Digits()),
                   DoubleToString(rates[i].high, m_symbol.Digits()),
                   DoubleToString(rates[i].low, m_symbol.Digits()),
                   DoubleToString(rates[i].close, m_symbol.Digits()),
                   IntegerToString(rates[i].tick_volume),
                   IntegerToString(rates[i].spread),
                   IntegerToString(rates[i].real_volume));
        }
     }
   else
     {
      Print("Failed to copy H1 rates for export. Error: ", GetLastError());
     }
     
   FileClose(handle);
   PrintFormat("Successfully exported H1 price data to MQL5/Files/%s", filename);
   
   MoveToAbsolutePath(filename, "price-h1.csv");
  }
