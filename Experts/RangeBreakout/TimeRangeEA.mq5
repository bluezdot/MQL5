#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input int InpRangeStart = 600;      // in minutes
input int InpRangeDuration = 120;   // in minutes
input int InpRangeClose = 1200;     // in minutes
input double InpLotSize = 0.01;
input long InpMagicNumber = 123456;

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

  RANGE_STRUCT() : start_time(0), end_time(0), close_time(0), high(0), low(999999), f_entry(false), f_high_breakout(false), f_low_breakout(false) {}
};

RANGE_STRUCT range;
MqlTick prevTick, lastTick;
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {

  if (InpMagicNumber <= 0) {
    Alert("Magic Number must be greater than 0");
    return INIT_FAILED;
  }

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
   
   // time range calculation
   if ((InpRangeClose >= 0 && lastTick.time >= range.close_time)                      // close time reached
      || (range.f_high_breakout && range.f_low_breakout)                              // both breakout flags are true
      || range.end_time == 0                                                          // range not calculated yet
      || (range.end_time != 0 && lastTick.time > range.end_time && !range.f_entry)){  // there was a range calculated but no tick inside
      // CountOpenPosition()==0
      
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
      if (lastTick.time >= range.start_time || dow == 6 || dow == 0) {
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
   range.close_time = (range.end_time - (range.end_time % time_cycle)) + InpRangeClose*60;
   for (int i=0; i<3; i++) {
      MqlDateTime tmp;
      TimeToStruct(range.close_time, tmp);
      int dow = tmp.day_of_week;
      if (range.close_time <= range.end_time || dow == 6 || dow == 0) {
         range.close_time += time_cycle;
      }
   }
   
   // draw objects
   DrawObjects();
}

void CheckBreakouts() {
   // check if we are after the range end
   if (lastTick.time >= range.end_time && range.end_time > 0 && range.f_entry) {
      // check for high breakout
      if (lastTick.ask > range.high) {
         range.f_high_breakout = true;
         DrawObjects();
      }
   
      // check for low breakout
      if (lastTick.bid < range.low) {
         range.f_low_breakout = true;
         DrawObjects();
      }
   }
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

      ObjectCreate(NULL, "range high forward", OBJ_TREND, 0, range.end_time, range.high, range.close_time, range.high);
      ObjectSetString(NULL, "range high forward", OBJPROP_TOOLTIP, "high of the range \n" + DoubleToString(range.high, _Digits));
      ObjectSetInteger(NULL, "range high forward", OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(NULL, "range high forward", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(NULL, "range high forward", OBJPROP_BACK, true);
   }

   // low
   ObjectsDeleteAll(NULL, "range low");
   if (range.low < 999999) {
      ObjectCreate(NULL, "range low", OBJ_TREND, 0, range.start_time, range.low, range.end_time, range.low);
      ObjectSetString(NULL, "range low", OBJPROP_TOOLTIP, "low of the range \n" + DoubleToString(range.low, _Digits));
      ObjectSetInteger(NULL, "range low", OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(NULL, "range low", OBJPROP_WIDTH, 2);
      ObjectSetInteger(NULL, "range low", OBJPROP_BACK, true);

      ObjectCreate(NULL, "range low forward", OBJ_TREND, 0, range.end_time, range.low, range.close_time, range.low);
      ObjectSetString(NULL, "range low forward", OBJPROP_TOOLTIP, "low of the range \n" + DoubleToString(range.low, _Digits));
      ObjectSetInteger(NULL, "range low forward", OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(NULL, "range low forward", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(NULL, "range low forward", OBJPROP_BACK, true);
   }
}