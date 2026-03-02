#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "==== General Inputs ===="
input double InpLotSize = 0.01;
input long InpMagicNumber = 123456;
input int InpSL = 150; // stop loss in % of the range (0=off)
input int InpTP = 200; // take profit in % of the range (0=off)

input group "==== Time Range Inputs ===="
input int InpRangeStart = 0;      // Range start time in minutes
input int InpRangeDuration = 420;   // Range duration in minutes
input int InpRangeClose = 1200;     // Range close time in minutes
input bool InpUseCloseTime = true;  // Flag if use close time

// Phiên Úc (Sydney): Mở cửa sớm nhất, thị trường thường yên tĩnh.
// Giờ mùa hè: 4:00 - 13:00 (VN)
// Giờ mùa đông: 5:00 - 14:00 (VN)
// Phiên Á (Tokyo): Bắt đầu giao dịch sôi động hơn sau phiên Úc.
// Giờ mùa hè: 6:00 - 15:00 (VN)
// Giờ mùa đông: 6:00 - 15:00 (VN)
// Phiên Âu (London): Thanh khoản tăng cao, giá vàng thường bắt đầu xu hướng mới.
// Giờ mùa hè: 14:00 - 23:00 (VN)
// Giờ mùa đông: 15:00 - 24:00 (VN)
// Phiên Mỹ/New York (NY): Phiên quan trọng nhất, khối lượng giao dịch lớn nhất và biến động giá mạnh nhất, thường chịu ảnh hưởng bởi tin tức kinh tế Mỹ.
// Giờ mùa hè: 19:00 - 4:00 sáng hôm sau (VN)
// Giờ mùa đông: 20:00 - 5:00 sáng hôm sau (VN) 


enum BREAKOUT_MODE_ENUM {
   BREAKOUT_MODE_HIGH_LOW, // buy and sell
   BREAKOUT_MODE_HIGH, // only buy
   BREAKOUT_MODE_LOW, // only sell
   BREAKOUT_MODE_ONE_TRADE_PER_RANGE // only one trade (buy/sell) for a range
};

input BREAKOUT_MODE_ENUM InpBreakoutMode = BREAKOUT_MODE_HIGH_LOW; // breakout mode

input group "==== Day Filter Inputs ===="
input bool InpMonday = true; // active trade on Monday
input bool InpTuesday = true; // active trade on Tuesday
input bool InpWednesday = true; // active trade on Wednesday
input bool InpThursday = true; // active trade on Thursday
input bool InpFriday = true; // active trade on Friday

//+------------------------------------------------------------------+
//| Include files                                                    |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
struct RANGE_STRUCT{
  datetime start_time;           // start of the range
  datetime end_time;             // end of the range
  datetime close_time;           // close time of the range
  double   high;                // high of the range
  double   low;                 // low of the range
  bool     f_entry;             // flag if we are inside the range
  bool     f_high_breakout;     // flag if we have a high breakout
  bool     f_low_breakout;      // flag if we have a low breakout

  RANGE_STRUCT() : start_time(0), end_time(0), close_time(0), high(0), low(DBL_MAX), f_entry(false), f_high_breakout(false), f_low_breakout(false) {}
};

RANGE_STRUCT range;
MqlTick prevTick, lastTick;
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {

  // todo: validate input

  if (InpMagicNumber <= 0) {
    Alert("Magic Number must be greater than 0");
    return INIT_FAILED;
  }
  
  // set magicnumber
  trade.SetExpertMagicNumber(InpMagicNumber);

  // calculated new range if inputs changed
  if (_UninitReason == REASON_PARAMETERS && CountOpenPositions() == 0) {
    CalculateRange();
  }

  // draw objects
  DrawObjects();

  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {

   // delete objects
   ObjectsDeleteAll(NULL, "range");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {

  Comment("Range Start: ", range.start_time, "\n",
          "Range End: ", range.end_time, "\n",
          "Range Close: ", range.close_time, "\n",
          "Range High: ", range.high, "\n",
          "Range Low: ", range.low, "\n",
          "Range Entry: ", range.f_entry, "\n",
          "Range High Breakout: ", range.f_high_breakout, "\n",
          "Range Low Breakout: ", range.f_low_breakout);

   // Get current tick
   prevTick = lastTick;
   SymbolInfoTick(_Symbol, lastTick);

   // price range calculation
   if (lastTick.time >= range.start_time && lastTick.time < range.end_time) {
      // set flag
      range.f_entry = true;
      
      // update high
      if (lastTick.ask > range.high) {
         range.high = lastTick.ask;
         DrawObjects();
      }
      
      // update low
      if (lastTick.bid < range.low) {
         range.low = lastTick.bid;
         DrawObjects();
      }
   }

   // close position if range close time is reached
   if (InpUseCloseTime && lastTick.time >= range.close_time && range.close_time > 0) {
      if(!ClosePositions()) {return;}
   }
   
   // time range calculation
   if (((InpRangeClose >= 0 && lastTick.time >= range.close_time)                     // close time reached
      || (range.f_high_breakout && range.f_low_breakout)                              // both breakout flags are true
      || range.end_time == 0                                                          // range not calculated yet
      || (range.end_time != 0 && lastTick.time > range.end_time && !range.f_entry))   // there was a range calculated but no tick inside
      && CountOpenPositions()==0) {
      
      CalculateRange();
   }

   // check for breakouts
   CheckBreakouts();
}

// calculate a new range
void CalculateRange () {
   // Reset range variables
   range.start_time = 0;
   range.close_time = 0;
   range.end_time = 0;
   range.f_high_breakout = false;
   range.f_low_breakout = false;
   range.high = 0.0;
   range.low = 999999;
   range.f_entry = false;
   
   // calculate range start time
   int time_cycle = 86400;
   range.start_time = (lastTick.time - (lastTick.time % time_cycle)) + InpRangeStart*60;
   for (int i=0; i<8; i++) {
      MqlDateTime tmp;
      TimeToStruct(range.start_time, tmp);
      int dow = tmp.day_of_week;
      if (lastTick.time >= range.start_time || dow == 6 || dow == 0 || (dow == 1 && !InpMonday) || (dow == 2 && !InpTuesday) || (dow == 3 && !InpWednesday) || (dow == 4 && !InpThursday) || (dow == 5 && !InpFriday)) {
         range.start_time += time_cycle;
      }
   }
   
   // calculate range end time
   range.end_time = range.start_time + InpRangeDuration*60;
   for (int i =0; i<2; i++) {
      MqlDateTime tmp;
      TimeToStruct(range.end_time, tmp);
      int dow = tmp.day_of_week;
      if (dow==6 || dow==0) {
         range.end_time += time_cycle;
      }
   }
   
   // calculate range close
   if (InpUseCloseTime) {
      range.close_time = (range.end_time - (range.end_time % time_cycle)) + InpRangeClose*60;
      for (int i=0; i<3; i++) {
         MqlDateTime tmp;
         TimeToStruct(range.close_time, tmp);
         int dow = tmp.day_of_week;
         if (range.close_time <= range.end_time || dow == 6 || dow == 0) {
            range.close_time += time_cycle;
         }
      }
   }
   
   // draw objects
   DrawObjects();
}

int CountOpenPositions () {
   int counter = 0;
   int total = PositionsTotal();
   
   for (int i=total-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      
      if (ticket <= 0) {
         Print("Failed to get position ticket");
         return -1;
      }
      
      if (!PositionSelectByTicket(ticket)) {
         Print("Failed to select position by ticket");
         return -1;
      }
      
      long magicnumber;
      
      if (!PositionGetInteger(POSITION_MAGIC, magicnumber)) {
         Print("Failed to get position magicnumber");
         return -1;
      }
      
      if (InpMagicNumber == magicnumber) {
         counter++;
      }
   }
   
   return counter;
}

void CheckBreakouts() {
   // check if we are after the range end
   if (lastTick.time >= range.end_time && range.end_time > 0 && range.f_entry) {
      // check for high breakout
      if (InpBreakoutMode != BREAKOUT_MODE_LOW && !range.f_high_breakout && lastTick.ask >= range.high) {
         range.f_high_breakout = true;

         if (InpBreakoutMode == BREAKOUT_MODE_ONE_TRADE_PER_RANGE) {
            range.f_low_breakout = true;
         }
         
         // cal sl & tp
         double sl = InpSL == 0 ? 0 : NormalizeDouble(lastTick.bid - ((range.high - range.low) * InpSL * 0.01), _Digits);
         double tp = InpTP == 0 ? 0 : NormalizeDouble(lastTick.bid + ((range.high - range.low) * InpTP * 0.01), _Digits);

         trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, InpLotSize, lastTick.ask, sl, tp, "Range Breakout Buy");
      }
   
      // check for low breakout
      if (InpBreakoutMode != BREAKOUT_MODE_HIGH && !range.f_low_breakout && lastTick.bid <= range.low) {
         range.f_low_breakout = true;

         if (InpBreakoutMode == BREAKOUT_MODE_ONE_TRADE_PER_RANGE) {
            range.f_high_breakout = true;
         }
         
         // cal sl & tp
         double sl = InpSL == 0 ? 0 : NormalizeDouble(lastTick.ask + (range.high - range.low) * InpSL * 0.01, _Digits);
         double tp = InpTP == 0 ? 0 : NormalizeDouble(lastTick.ask - (range.high - range.low) * InpTP * 0.01, _Digits);

         trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, InpLotSize, lastTick.bid, sl, tp, "Range Breakout Sell");
      }
   }
}

bool ClosePositions() {
   int total = PositionsTotal();
   
   for (int i=total-1; i>=0; i--) {
      if (total != PositionsTotal()) {
         total = PositionsTotal(); 
         i = total;
         continue;  
      }
      
      ulong ticket = PositionGetTicket(i); // select position
      
      if (ticket <= 0) {
         Print("Failed to get postion ticket");
         return false;
      }
      
      if (!PositionSelectByTicket(ticket)) {
         Print("Failed to select position by ticket");
         return false;
      }
      
      long magicnumber;
      
      if (!PositionGetInteger(POSITION_MAGIC, magicnumber)) {
         Print("Failed to get position magic number");
         return false;
      }
      
      if (magicnumber == InpMagicNumber) {
         trade.PositionClose(ticket);
         
         if (trade.ResultRetcode() != TRADE_RETCODE_DONE) {
            Print("Failed to close position. Result: " + (string)trade.ResultRetcode() + ":" + trade.ResultRetcodeDescription());
            return false;
         }
      }
   }

   return true;
}

void DrawObjects() {
   // start
   ObjectDelete(NULL, "range start");
   if (range.start_time > 0) {
      ObjectCreate(NULL, "range start", OBJ_VLINE, 0, range.start_time, 0);
      ObjectSetString(NULL, "range start", OBJPROP_TOOLTIP, "start of the range \n" + TimeToString(range.start_time, TIME_DATE|TIME_MINUTES));
      ObjectSetInteger(NULL, "range start", OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(NULL, "range start", OBJPROP_WIDTH, 2);
      ObjectSetInteger(NULL, "range start", OBJPROP_BACK, true);
   }
   
   // end
   ObjectDelete(NULL, "range end");
   if (range.end_time > 0) {
      ObjectCreate(NULL, "range end", OBJ_VLINE, 0, range.end_time, 0);
      ObjectSetString(NULL, "range end", OBJPROP_TOOLTIP, "end of the range \n" + TimeToString(range.end_time, TIME_DATE|TIME_MINUTES));
      ObjectSetInteger(NULL, "range end", OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(NULL, "range end", OBJPROP_WIDTH, 2);
      ObjectSetInteger(NULL, "range end", OBJPROP_BACK, true);
   }

   // close
   ObjectDelete(NULL, "range close");
   if (range.close_time > 0) {
      ObjectCreate(NULL, "range close", OBJ_VLINE, 0, range.close_time, 0);
      ObjectSetString(NULL, "range close", OBJPROP_TOOLTIP, "close of the range \n" + TimeToString(range.close_time, TIME_DATE|TIME_MINUTES));
      ObjectSetInteger(NULL, "range close", OBJPROP_COLOR, clrRed);
      ObjectSetInteger(NULL, "range close", OBJPROP_WIDTH, 2);
      ObjectSetInteger(NULL, "range close", OBJPROP_BACK, true);
   }

   // high
   ObjectsDeleteAll(NULL, "range high");
   if (range.high > 0) {
      ObjectCreate(NULL, "range high", OBJ_TREND, 0, range.start_time, range.high, range.end_time, range.high);
      ObjectSetString(NULL, "range high", OBJPROP_TOOLTIP, "high of the range \n" + DoubleToString(range.high, _Digits));
      ObjectSetInteger(NULL, "range high", OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(NULL, "range high", OBJPROP_WIDTH, 2);
      ObjectSetInteger(NULL, "range high", OBJPROP_BACK, true);

      ObjectCreate(NULL, "range high forward", OBJ_TREND, 0, range.end_time, range.high, InpUseCloseTime ? range.close_time : INT_MAX, range.high);
      ObjectSetString(NULL, "range high forward", OBJPROP_TOOLTIP, "high of the range \n" + DoubleToString(range.high, _Digits));
      ObjectSetInteger(NULL, "range high forward", OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(NULL, "range high forward", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(NULL, "range high forward", OBJPROP_BACK, true);
   }

   // low
   ObjectsDeleteAll(NULL, "range low");
   if (range.low < DBL_MAX) {
      ObjectCreate(NULL, "range low", OBJ_TREND, 0, range.start_time, range.low, range.end_time, range.low);
      ObjectSetString(NULL, "range low", OBJPROP_TOOLTIP, "low of the range \n" + DoubleToString(range.low, _Digits));
      ObjectSetInteger(NULL, "range low", OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(NULL, "range low", OBJPROP_WIDTH, 2);
      ObjectSetInteger(NULL, "range low", OBJPROP_BACK, true);

      ObjectCreate(NULL, "range low forward", OBJ_TREND, 0, range.end_time, range.low, InpUseCloseTime ? range.close_time : INT_MAX, range.low);
      ObjectSetString(NULL, "range low forward", OBJPROP_TOOLTIP, "low of the range \n" + DoubleToString(range.low, _Digits));
      ObjectSetInteger(NULL, "range low forward", OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(NULL, "range low forward", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(NULL, "range low forward", OBJPROP_BACK, true);
   }

   // refresh chart
   ChartRedraw();
}