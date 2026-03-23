#property copyright "Copyright 2026, Tran Hoang Nam"
#property link ""
#property version "1.01"

#include <Trade/Trade.mqh>
CTrade trade;

//==============================================
// CONFIGURATION
//==============================================
input int MagicNumber = 21; // Magic Number
input string CommentPrefix = "GRID_DCA_v1.01"; // Prefix for order comments (e.g. "GRID_DCA_v1.01" -> "GRID_DCA_v1.01_B_00")
input int MaxOrdersPerSide = 20; // Maximum number of orders on each side (buy/sell)
input double BaseLot = 0.01; // Base lot size for the first order
input double ChainStopLoss = 55000; // Maximum loss in account (currency)
input int ChainStopLossRestartDelay = 3600; // Time to wait before resuming after ChainStopLoss (0 = stop permanently) (seconds)
input bool BuyOnly = false; // Buy only mode (bool)
input bool SellOnly = false; // Sell only mode (bool)
input int TimeToOpenNewChain = 15; // Time to wait before opening a     new DCA chain (seconds)

// Grid step sizes for each zone (in points)
input double Zone1_GridStep = 5000; // Distance for the 1st grid level (points)
input double Zone2_GridStep = 10000; // Distance for the 2nd grid level (points)
input double Zone3_GridStep = 10000; // Distance for the 3rd grid level (points)
input double Zone4_GridStep = 15000; // Distance for the 4th grid level (points)

// Distance thresholds for each zone (in points)
input double Zone1_To_Zone2_Distance = 25000;    // Distance Zone 1 -> Zone 2 (points)
input double Zone2_To_Zone3_Distance = 35000;    // Distance Zone 2 -> Zone 3 (points)
input double Zone3_To_Zone4_Distance = 30000;    // Distance Zone 3 -> Zone 4 (points)

// Take profit per lot for all DCA chain (in account currency)
input double TP_PerLot = 500; // Take profit per lot for all DCA chain (currency)

// EOD (End of Day) settings
input int EODWindowMinutes = 120;     // Minutes before market close to activate EOD mode (0 = disabled) (minutes)
input int EODZoneThreshold = 8;       // Chains with fewer orders than this will be force-closed in EOD window
input int DelayAfterMarketOpen = 600; // Time to wait after market opens before resuming trading (0 = immediate) (seconds)

//==============================================
// VOLUME PER ZONE AND LEVEL: Every zone has 5 orders (level 0-4)
//==============================================
double ZoneVolume[4][5] = {
   {1,  1,  2,   3,   5},    // Zone 1
   {1,  6,  7,  13,  20},    // Zone 2
   {1, 21, 22,  43,  65},    // Zone 3
   {1, 66, 67, 133, 200}     // Zone 4
};

//==============================================
// ENUM
//==============================================
enum TradeSide
{
   SIDE_BUY,
   SIDE_SELL
};

//==============================================
// GLOBAL VARIABLES
//==============================================
double BuyChainEntryPrice = 0;              // Entry price for buy chain
double SellChainEntryPrice = 0;             // Entry price for sell chain
datetime LastBuyCloseTime = 0;              // Last time buy chain was closed
datetime LastSellCloseTime = 0;             // Last time sell chain was closed
datetime ChainStopLossTriggeredTime = 0;    // Time when ChainStopLoss was triggered (0 = not triggered)
bool EODWindowActive = false;               // True when within EOD window (before market close)
bool WaitingForMarketOpen = false;          // True when waiting for next market session to open
datetime MarketOpenTime = 0;                // Timestamp when market was first detected open after EOD wait

//==============================================
// STRUCTURE FOR CHAIN INFO
//==============================================
struct ChainStats
{
   double totalVolume;
   double totalProfit;
   int orderCount;
};

//==============================================
// HELPER FUNCTIONS DECLARATION
//==============================================
string GetOrderComment(TradeSide side, int orderIndex);
bool ParseOrderComment(string comment, TradeSide &side, int &orderIndex);
void GetZoneAndLevel(int orderIndex, int &zone, int &level);
double CalculateGridPrice(TradeSide side, double entryPrice, int orderIndex);
int GetOrderCount(TradeSide side);
ChainStats GetChainStats(TradeSide side);
bool CloseChainBySide(TradeSide side);
bool CanOpenNewChain(TradeSide side);
bool PlaceOrder(TradeSide side, int orderIndex, double price);
int GetLastOrderIndex(TradeSide side);
double GetLastOrderPrice(TradeSide side, int orderIndex);
double GetGridStepForZone(int zone);
bool IsMarketOpen();
datetime GetSessionCloseTime();
void HandleEODChains();

int OnInit()
{
   // Set magic number for CTrade
   trade.SetExpertMagicNumber(MagicNumber);
   
   datetime serverTime = TimeTradeServer();
   
   Print("Grid DCA bot initialized!");
   Print("BaseLot: ", BaseLot);
   Print("MaxOrdersPerSide: ", MaxOrdersPerSide);
   Print("ServerTime: ", serverTime);
   
   return(INIT_SUCCEEDED);
}

void OnDeinit()
{

}

void OnTick()
{
   // Check if bot is in ChainStopLoss cooldown
   if(ChainStopLossTriggeredTime > 0)
   {
      if(ChainStopLossRestartDelay == 0)
         return; // Permanent stop
      
      if(TimeCurrent() - ChainStopLossTriggeredTime < ChainStopLossRestartDelay)
         return; // Still in cooldown
      
      // Cooldown expired, reset and resume
      ChainStopLossTriggeredTime = 0;
      Print("ChainStopLoss cooldown expired. Resuming trading.");
   }
   
   // ============================================
   // SECTION 0: EOD / MARKET SESSION CHECK
   // ============================================
   
   // Waiting for next market session to open
   if(WaitingForMarketOpen)
   {
      if(IsMarketOpen())
      {
         // Record the moment market first opens
         if(MarketOpenTime == 0)
         {
            MarketOpenTime = TimeCurrent();
            Print("EOD: Market session opened. Waiting ", DelayAfterMarketOpen, "s before resuming trading.");
         }
         
         // Check if delay has passed
         if(DelayAfterMarketOpen == 0 || TimeCurrent() - MarketOpenTime >= DelayAfterMarketOpen)
         {
            EODWindowActive = false;
            WaitingForMarketOpen = false;
            MarketOpenTime = 0;
            Print("EOD: Delay elapsed. Resuming trading.");
         }
      }
      else
      {
         MarketOpenTime = 0; // Reset if market closes again (edge case)
      }
      return;
   }
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // ============================================
   // SECTION 1: CHECK CHAIN STOPLOSS (TOTAL)
   // ============================================
   ChainStats buyStats = GetChainStats(SIDE_BUY);
   ChainStats sellStats = GetChainStats(SIDE_SELL);
   double totalPnL = buyStats.totalProfit + sellStats.totalProfit;
   
   if(totalPnL <= -ChainStopLoss)
   {
      Print("ChainStopLoss triggered! Total PnL: ", totalPnL, " Threshold: ", -ChainStopLoss);
      
      // Close all positions
      if(buyStats.orderCount > 0)
         CloseChainBySide(SIDE_BUY);
      if(sellStats.orderCount > 0)
         CloseChainBySide(SIDE_SELL);
      
      ChainStopLossTriggeredTime = TimeCurrent();
      if(ChainStopLossRestartDelay == 0)
         Print("Bot stopped permanently due to ChainStopLoss!");
      else
         Print("Bot paused due to ChainStopLoss! Will resume in ", ChainStopLossRestartDelay, " seconds.");
      return;
   }
   
   // ============================================
   // SECTION 2: CHECK TAKE PROFIT FOR EACH CHAIN
   // ============================================
   
   // Check Buy Chain TP
   if(buyStats.orderCount > 0)
   {
      double buyTarget = TP_PerLot * buyStats.totalVolume;
      if(buyStats.totalProfit >= buyTarget)
      {
         Print("Buy chain TP reached! Profit: ", buyStats.totalProfit, " Target: ", buyTarget);
         CloseChainBySide(SIDE_BUY);
      }
   }
   
   // Check Sell Chain TP
   if(sellStats.orderCount > 0)
   {
      double sellTarget = TP_PerLot * sellStats.totalVolume;
      if(sellStats.totalProfit >= sellTarget)
      {
         Print("Sell chain TP reached! Profit: ", sellStats.totalProfit, " Target: ", sellTarget);
         CloseChainBySide(SIDE_SELL);
      }
   }
   
   // ============================================
   // SECTION 2.5: EOD WINDOW HANDLING
   // ============================================
   
   // Detect entry into EOD window
   if(!EODWindowActive && EODWindowMinutes > 0)
   {
      datetime closeTime = GetSessionCloseTime();
      if(closeTime > 0)
      {
         long timeToClose = (long)(closeTime - TimeCurrent());
         if(timeToClose > 0 && timeToClose <= (long)(EODWindowMinutes * 60))
         {
            EODWindowActive = true;
            Print("EOD: Window activated. Session closes in ", timeToClose / 60, " minutes.");
         }
      }
   }
   
   // Handle open chains during EOD window
   if(EODWindowActive)
      HandleEODChains();
   
   // ============================================
   // SECTION 3: MANAGE BUY CHAIN
   // ============================================
   
   // Initialize buy chain if doesn't exist
   if(CanOpenNewChain(SIDE_BUY))
   {
      // Open first buy order at current price
      if(PlaceOrder(SIDE_BUY, 0, ask))
      {
         BuyChainEntryPrice = ask;
         Print("Buy chain initialized at price: ", BuyChainEntryPrice);
      }
   }
   
   // Manage existing buy chain orders
   if(BuyChainEntryPrice > 0)
   {
      // Find the highest order index that exists
      int lastOrderIndex = GetLastOrderIndex(SIDE_BUY);
      
      // Only try to place the next order after the last one
      if(lastOrderIndex >= 0 && lastOrderIndex < MaxOrdersPerSide - 1)
      {
         int nextOrderIndex = lastOrderIndex + 1;
         
         // Get entry price of last order
         double lastOrderPrice = GetLastOrderPrice(SIDE_BUY, lastOrderIndex);
         
         if(lastOrderPrice > 0)
         {
            // Calculate required distance based on zone
            int lastZone, lastLevel;
            GetZoneAndLevel(lastOrderIndex, lastZone, lastLevel);
            
            // If last order is at level 4 (end of zone), use zone transition distance
            double requiredDistance = 0;
            if(lastLevel == 4)
            {
               // Transition to next zone
               if(lastZone == 0) requiredDistance = Zone1_To_Zone2_Distance;
               else if(lastZone == 1) requiredDistance = Zone2_To_Zone3_Distance;
               else if(lastZone == 2) requiredDistance = Zone3_To_Zone4_Distance;
            }
            else
            {
               // Same zone, use grid step
               requiredDistance = GetGridStepForZone(lastZone);
            }
            
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double requiredPriceDistance = requiredDistance * point;
            
            // For buy: next order should be placed when price goes DOWN enough from last order
            // But we need to check if price has already gone down past the required distance
            double nextGridPrice = lastOrderPrice - requiredPriceDistance;
            
            // Check if current price has reached the next level
            if(ask <= nextGridPrice)
            {
               PlaceOrder(SIDE_BUY, nextOrderIndex, ask);
            }
         }
      }
   }
   
   // ============================================
   // SECTION 4: MANAGE SELL CHAIN
   // ============================================
   
   // Initialize sell chain if doesn't exist
   if(CanOpenNewChain(SIDE_SELL))
   {
      // Open first sell order at current price
      if(PlaceOrder(SIDE_SELL, 0, bid))
      {
         SellChainEntryPrice = bid;
         Print("Sell chain initialized at price: ", SellChainEntryPrice);
      }
   }
   
   // Manage existing sell chain orders
   if(SellChainEntryPrice > 0)
   {
      // Find the highest order index that exists
      int lastOrderIndex = GetLastOrderIndex(SIDE_SELL);
      
      // Only try to place the next order after the last one
      if(lastOrderIndex >= 0 && lastOrderIndex < MaxOrdersPerSide - 1)
      {
         int nextOrderIndex = lastOrderIndex + 1;
         
         // Get entry price of last order
         double lastOrderPrice = GetLastOrderPrice(SIDE_SELL, lastOrderIndex);
         
         if(lastOrderPrice > 0)
         {
            // Calculate required distance based on zone
            int lastZone, lastLevel;
            GetZoneAndLevel(lastOrderIndex, lastZone, lastLevel);
            
            // If last order is at level 4 (end of zone), use zone transition distance
            double requiredDistance = 0;
            if(lastLevel == 4)
            {
               // Transition to next zone
               if(lastZone == 0) requiredDistance = Zone1_To_Zone2_Distance;
               else if(lastZone == 1) requiredDistance = Zone2_To_Zone3_Distance;
               else if(lastZone == 2) requiredDistance = Zone3_To_Zone4_Distance;
            }
            else
            {
               // Same zone, use grid step
               requiredDistance = GetGridStepForZone(lastZone);
            }
            
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double requiredPriceDistance = requiredDistance * point;
            
            // For sell: next order should be placed when price goes UP enough from last order
            double nextGridPrice = lastOrderPrice + requiredPriceDistance;
            
            // Check if current price has reached the next level
            if(bid >= nextGridPrice)
            {
               PlaceOrder(SIDE_SELL, nextOrderIndex, bid);
            }
         }
      }
   }
}

//==============================================
// HELPER FUNCTIONS IMPLEMENTATION
//==============================================

//+------------------------------------------------------------------+
//| Build order comment encoding side and order index               |
//| Format: "{CommentPrefix}_B_00" / "{CommentPrefix}_S_19"        |
//+------------------------------------------------------------------+
string GetOrderComment(TradeSide side, int orderIndex)
{
   string sideStr = (side == SIDE_BUY) ? "B" : "S";
   return StringFormat("%s_%s_%02d", CommentPrefix, sideStr, orderIndex);
}

//+------------------------------------------------------------------+
//| Parse order comment to extract side and order index              |
//| Returns true if comment matches current CommentPrefix format     |
//+------------------------------------------------------------------+
bool ParseOrderComment(string comment, TradeSide &side, int &orderIndex)
{
   int prefixLen = StringLen(CommentPrefix);
   if(StringLen(comment) < prefixLen + 5) return false;  // "_B_00" = 5 chars
   if(StringSubstr(comment, 0, prefixLen) != CommentPrefix) return false;
   if(StringSubstr(comment, prefixLen, 1) != "_") return false;
   string sideChar = StringSubstr(comment, prefixLen + 1, 1);
   if(StringSubstr(comment, prefixLen + 2, 1) != "_") return false;
   orderIndex = (int)StringToInteger(StringSubstr(comment, prefixLen + 3, 2));
   if(sideChar == "B")      side = SIDE_BUY;
   else if(sideChar == "S") side = SIDE_SELL;
   else return false;
   return true;
}

//+------------------------------------------------------------------+
//| Get zone and level from order index (0-19)                       |
//| Zone 0: index 0-4, Zone 1: index 5-9, etc.                      |
//+------------------------------------------------------------------+
void GetZoneAndLevel(int orderIndex, int &zone, int &level)
{
   zone = orderIndex / 5;
   level = orderIndex % 5;
}

//+------------------------------------------------------------------+
//| Calculate grid price for specific order index                    |
//| Buy chain: prices decrease, Sell chain: prices increase         |
//+------------------------------------------------------------------+
double CalculateGridPrice(TradeSide side, double entryPrice, int orderIndex)
{
   if(entryPrice == 0) return 0;
   
   int zone, level;
   GetZoneAndLevel(orderIndex, zone, level);
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double distance = 0;
   
   // Calculate cumulative distance from entry price
   // First, add all grid steps within previous zones
   for(int z = 0; z < zone; z++)
   {
      // Each zone has 5 levels, but only 4 steps between them (level 0->1, 1->2, 2->3, 3->4)
      double gridStep = 0;
      if(z == 0) gridStep = Zone1_GridStep;
      else if(z == 1) gridStep = Zone2_GridStep;
      else if(z == 2) gridStep = Zone3_GridStep;
      else if(z == 3) gridStep = Zone4_GridStep;
      
      distance += 4 * gridStep; // 4 steps per zone
      
      // Add zone transition distance after each zone (except the last zone we haven't entered yet)
      if(z == 0) distance += Zone1_To_Zone2_Distance;
      else if(z == 1) distance += Zone2_To_Zone3_Distance;
      else if(z == 2) distance += Zone3_To_Zone4_Distance;
   }
   
   // Add steps within current zone
   double currentZoneGridStep = 0;
   if(zone == 0) currentZoneGridStep = Zone1_GridStep;
   else if(zone == 1) currentZoneGridStep = Zone2_GridStep;
   else if(zone == 2) currentZoneGridStep = Zone3_GridStep;
   else if(zone == 3) currentZoneGridStep = Zone4_GridStep;
   
   distance += level * currentZoneGridStep;
   
   // Convert distance to price
   double priceDistance = distance * point;
   
   if(side == SIDE_BUY)
      return entryPrice - priceDistance; // Buy orders go down
   else
      return entryPrice + priceDistance; // Sell orders go up
}

//+------------------------------------------------------------------+
//| Get count of orders for specific side                            |
//+------------------------------------------------------------------+
int GetOrderCount(TradeSide side)
{
   int count = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            TradeSide posSide;
            int posIndex;
            if(ParseOrderComment(PositionGetString(POSITION_COMMENT), posSide, posIndex) && posSide == side)
               count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Get chain statistics (volume, profit, order count)               |
//+------------------------------------------------------------------+
ChainStats GetChainStats(TradeSide side)
{
   ChainStats stats;
   stats.totalVolume = 0;
   stats.totalProfit = 0;
   stats.orderCount = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            TradeSide posSide;
            int posIndex;
            if(ParseOrderComment(PositionGetString(POSITION_COMMENT), posSide, posIndex) && posSide == side)
            {
               stats.orderCount++;
               stats.totalVolume += PositionGetDouble(POSITION_VOLUME);
               stats.totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            }
         }
      }
   }
   return stats;
}

//+------------------------------------------------------------------+
//| Close all positions for specific side                            |
//+------------------------------------------------------------------+
bool CloseChainBySide(TradeSide side)
{
   bool allClosed = true;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            TradeSide posSide;
            int posIndex;
            if(ParseOrderComment(PositionGetString(POSITION_COMMENT), posSide, posIndex) && posSide == side)
            {
               if(!trade.PositionClose(ticket))
               {
                  Print("Failed to close position ", ticket, " Error: ", GetLastError());
                  allClosed = false;
               }
            }
         }
      }
   }
   
   if(allClosed)
   {
      // Reset entry price and update last close time
      if(side == SIDE_BUY)
      {
         BuyChainEntryPrice = 0;
         LastBuyCloseTime = TimeCurrent();
      }
      else
      {
         SellChainEntryPrice = 0;
         LastSellCloseTime = TimeCurrent();
      }
   }
   
   return allClosed;
}

//+------------------------------------------------------------------+
//| Check if can open new chain based on time delay                  |
//+------------------------------------------------------------------+
bool CanOpenNewChain(TradeSide side)
{
   // Block new chains during EOD window or while waiting for next market session
   if(EODWindowActive || WaitingForMarketOpen) return false;
   
   // Check ChainStopLoss cooldown
   if(ChainStopLossTriggeredTime > 0) return false;
   
   // Check BuyOnly/SellOnly filters
   if(BuyOnly && side == SIDE_SELL) return false;
   if(SellOnly && side == SIDE_BUY) return false;
   
   // Check if chain already exists
   if(side == SIDE_BUY && BuyChainEntryPrice != 0) return false;
   if(side == SIDE_SELL && SellChainEntryPrice != 0) return false;
   
   // Check time delay since last close
   datetime lastClose = (side == SIDE_BUY) ? LastBuyCloseTime : LastSellCloseTime;
   if(lastClose > 0)
   {
      datetime currentTime = TimeCurrent();
      if(currentTime - lastClose < TimeToOpenNewChain)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Place order for specific side and index                          |
//+------------------------------------------------------------------+
bool PlaceOrder(TradeSide side, int orderIndex, double price)
{
   int zone, level;
   GetZoneAndLevel(orderIndex, zone, level);
   
   double volume = BaseLot * ZoneVolume[zone][level];
   string comment = GetOrderComment(side, orderIndex);
   
   // Normalize volume
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   volume = MathMax(minLot, MathMin(maxLot, volume));
   volume = MathFloor(volume / lotStep) * lotStep;
   
   trade.SetExpertMagicNumber(MagicNumber);
   
   bool result = false;
   if(side == SIDE_BUY)
      result = trade.Buy(volume, _Symbol, 0, 0, 0, comment);
   else
      result = trade.Sell(volume, _Symbol, 0, 0, 0, comment);
   
   if(result)
   {
      Print("Order placed: ", (side == SIDE_BUY ? "BUY" : "SELL"), 
            " Index:", orderIndex, " Zone:", zone, " Level:", level, 
            " Volume:", volume, " Comment:", comment);
   }
   else
   {
      Print("Failed to place order: ", (side == SIDE_BUY ? "BUY" : "SELL"),
            " Index:", orderIndex, " Error:", GetLastError());
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Get the highest order index that exists in chain                 |
//+------------------------------------------------------------------+
int GetLastOrderIndex(TradeSide side)
{
   int lastIndex = -1;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            TradeSide posSide;
            int orderIndex;
            if(ParseOrderComment(PositionGetString(POSITION_COMMENT), posSide, orderIndex) && posSide == side)
            {
               if(orderIndex > lastIndex)
                  lastIndex = orderIndex;
            }
         }
      }
   }
   return lastIndex;
}

//+------------------------------------------------------------------+
//| Get entry price of specific order by index                       |
//+------------------------------------------------------------------+
double GetLastOrderPrice(TradeSide side, int orderIndex)
{
   string targetComment = GetOrderComment(side, orderIndex);
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            if(PositionGetString(POSITION_COMMENT) == targetComment)
            {
               return PositionGetDouble(POSITION_PRICE_OPEN);
            }
         }
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Get grid step size for specific zone                             |
//+------------------------------------------------------------------+
double GetGridStepForZone(int zone)
{
   if(zone == 0) return Zone1_GridStep;
   else if(zone == 1) return Zone2_GridStep;
   else if(zone == 2) return Zone3_GridStep;
   else if(zone == 3) return Zone4_GridStep;
   return 0;
}

//+------------------------------------------------------------------+
//| Check if market is currently open for trading                    |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   ENUM_DAY_OF_WEEK today = (ENUM_DAY_OF_WEEK)dt.day_of_week;
   
   datetime startOfDay = now - (datetime)(dt.hour * 3600 + dt.min * 60 + dt.sec);
   datetime currentSecondsInDay = now - startOfDay;
   
   datetime from, to;
   for(int sessionIdx = 0; sessionIdx < 10; sessionIdx++)
   {
      if(!SymbolInfoSessionTrade(_Symbol, today, sessionIdx, from, to))
         break;
      if(currentSecondsInDay >= from && currentSecondsInDay < to)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get absolute datetime when the current trading session ends      |
//| Returns 0 if no active session found                             |
//+------------------------------------------------------------------+
datetime GetSessionCloseTime()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   ENUM_DAY_OF_WEEK today = (ENUM_DAY_OF_WEEK)dt.day_of_week;
   
   datetime startOfDay = now - (datetime)(dt.hour * 3600 + dt.min * 60 + dt.sec);
   datetime currentSecondsInDay = now - startOfDay;
   
   datetime from, to;
   for(int sessionIdx = 0; sessionIdx < 10; sessionIdx++)
   {
      if(!SymbolInfoSessionTrade(_Symbol, today, sessionIdx, from, to))
         break;
      if(currentSecondsInDay >= from && currentSecondsInDay < to)
         return startOfDay + to;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Handle open chains during EOD window                             |
//| - Force-close chains below EODZoneThreshold orders               |
//| - Let larger chains wait for TP naturally                        |
//| - Set WaitingForMarketOpen when all chains are closed            |
//+------------------------------------------------------------------+
void HandleEODChains()
{
   // Force-close chains that haven't entered Zone 2 yet
   ChainStats buyStats = GetChainStats(SIDE_BUY);
   if(buyStats.orderCount > 0 && buyStats.orderCount < EODZoneThreshold)
   {
      Print("EOD: BUY chain has ", buyStats.orderCount, " orders (< threshold ", EODZoneThreshold, "). Force closing.");
      CloseChainBySide(SIDE_BUY);
   }
   
   ChainStats sellStats = GetChainStats(SIDE_SELL);
   if(sellStats.orderCount > 0 && sellStats.orderCount < EODZoneThreshold)
   {
      Print("EOD: SELL chain has ", sellStats.orderCount, " orders (< threshold ", EODZoneThreshold, "). Force closing.");
      CloseChainBySide(SIDE_SELL);
   }
   
   // If all chains are closed, wait for next market session
   if(BuyChainEntryPrice == 0 && SellChainEntryPrice == 0 && !WaitingForMarketOpen)
   {
      WaitingForMarketOpen = true;
      Print("EOD: All chains closed. Waiting for next market session to open.");
   }
}