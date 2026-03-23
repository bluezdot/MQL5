#property copyright "Copyright 2026, Tran Hoang Nam"
#property link ""
#property version "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

//==============================================
// CONFIGURATION
//==============================================
input int MagicNumber = 12; // Unique identifier for the expert advisor's trades
input int MaxOrdersPerSide = 20; // Maximum number of orders on each side (buy/sell)
input double BaseLot = 0.01; // Base lot size for the first order
input double ChainStopLoss = 60000; // Maximum loss per day in account currency
input bool BuyOnly = false; // If true, the bot will only open buy orders
input bool SellOnly = false; // If true, the bot will only open sell orders
input int TimeToOpenNewChain = 15; // Time in seconds to wait before opening a new DCA chain after closing the previous one

// Grid step sizes for each zone (in points)
input double Zone1_GridStep = 10000; // Distance in points for the first grid level
input double Zone2_GridStep = 10000; // Distance in points for the second grid level
input double Zone3_GridStep = 10000; // Distance in points for the third grid level
input double Zone4_GridStep = 15000; // Distance in points for the fourth grid level

// Distance thresholds for each zone (in points)
input double Zone1_To_Zone2_Distance = 30000;    // Distance in points Zone 1 -> Zone 2
input double Zone2_To_Zone3_Distance = 45000;    // Distance in points Zone 2 -> Zone 3
input double Zone3_To_Zone4_Distance = 35000;    // Distance in points Zone 3 -> Zone 4

// Take profit per lot for all DCA chain (in account currency)
input double TP_PerLot = 500; // Take profit per lot for all DCA chain (in account currency)

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
double BuyChainEntryPrice = 0;   // Entry price for buy chain
double SellChainEntryPrice = 0;  // Entry price for sell chain
datetime LastBuyCloseTime = 0;   // Last time buy chain was closed
datetime LastSellCloseTime = 0;  // Last time sell chain was closed
bool BotStopped = false;         // Flag to stop bot after ChainStopLoss triggered

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
int GetMagicNumber(TradeSide side, int orderIndex);
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
   // Check if bot is stopped
   if(BotStopped) return;
   
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
      
      BotStopped = true;
      Print("Bot stopped due to ChainStopLoss!");
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
//| Get magic number for specific side and order index              |
//| Buy: MagicNumber*100 + 0-19, Sell: MagicNumber*100 + 50-69     |
//+------------------------------------------------------------------+
int GetMagicNumber(TradeSide side, int orderIndex)
{
   int baseMagic = MagicNumber * 100;
   if(side == SIDE_BUY)
      return baseMagic + orderIndex;
   else
      return baseMagic + 50 + orderIndex;
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
   int baseMagic = MagicNumber * 100;
   int minMagic = (side == SIDE_BUY) ? baseMagic : baseMagic + 50;
   int maxMagic = minMagic + 19;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            long posMagic = PositionGetInteger(POSITION_MAGIC);
            if(posMagic >= minMagic && posMagic <= maxMagic)
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
   
   int baseMagic = MagicNumber * 100;
   int minMagic = (side == SIDE_BUY) ? baseMagic : baseMagic + 50;
   int maxMagic = minMagic + 19;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            long posMagic = PositionGetInteger(POSITION_MAGIC);
            if(posMagic >= minMagic && posMagic <= maxMagic)
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
   int baseMagic = MagicNumber * 100;
   int minMagic = (side == SIDE_BUY) ? baseMagic : baseMagic + 50;
   int maxMagic = minMagic + 19;
   
   bool allClosed = true;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            long posMagic = PositionGetInteger(POSITION_MAGIC);
            if(posMagic >= minMagic && posMagic <= maxMagic)
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
   // Check bot stop flag
   if(BotStopped) return false;
   
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
   int magic = GetMagicNumber(side, orderIndex);
   
   // Normalize volume
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   volume = MathMax(minLot, MathMin(maxLot, volume));
   volume = MathFloor(volume / lotStep) * lotStep;
   
   trade.SetExpertMagicNumber(magic);
   
   bool result = false;
   if(side == SIDE_BUY)
      result = trade.Buy(volume, _Symbol, 0, 0, 0, "GridDCA");
   else
      result = trade.Sell(volume, _Symbol, 0, 0, 0, "GridDCA");
   
   if(result)
   {
      Print("Order placed: ", (side == SIDE_BUY ? "BUY" : "SELL"), 
            " Index:", orderIndex, " Zone:", zone, " Level:", level, 
            " Volume:", volume, " Magic:", magic);
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
   int baseMagic = MagicNumber * 100;
   int minMagic = (side == SIDE_BUY) ? baseMagic : baseMagic + 50;
   int maxMagic = minMagic + 19;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            long posMagic = PositionGetInteger(POSITION_MAGIC);
            if(posMagic >= minMagic && posMagic <= maxMagic)
            {
               int orderIndex = (int)(posMagic - minMagic);
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
   int magic = GetMagicNumber(side, orderIndex);
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if(PositionGetInteger(POSITION_MAGIC) == magic)
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