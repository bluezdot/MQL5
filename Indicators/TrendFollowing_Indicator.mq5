//+------------------------------------------------------------------+
//|                                    TrendFollowing_Indicator.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- plot EMA 10
#property indicator_label1  "EMA 10"
#property indicator_type1   DRAW_LINE
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_color1  clrDodgerBlue

//--- plot EMA 20
#property indicator_label2  "EMA 20"
#property indicator_type2   DRAW_LINE
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2
#property indicator_color2  clrRed

//--- indicator buffers
double ema10_buffer[];
double ema20_buffer[];

//--- indicator handles
int ema10_handle;
int ema20_handle;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- indicator buffers mapping
   SetIndexBuffer(0, ema10_buffer, INDICATOR_DATA);
   SetIndexBuffer(1, ema20_buffer, INDICATOR_DATA);

  // set buffers as series (index 0 = current bar)
   ArraySetAsSeries(ema10_buffer, true);
   ArraySetAsSeries(ema20_buffer, true);

//--- create EMA handles
   ema10_handle = iMA(_Symbol, _Period, 10, 0, MODE_EMA, PRICE_CLOSE);
   ema20_handle = iMA(_Symbol, _Period, 20, 0, MODE_EMA, PRICE_CLOSE);

   if(ema10_handle == INVALID_HANDLE || ema20_handle == INVALID_HANDLE)
     {
      Print("Error creating EMA handles");
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total<=0)
      return(0);

   // ensure our buffers are large enough
   ArrayResize(ema10_buffer, rates_total);
   ArrayResize(ema20_buffer, rates_total);
   ArraySetAsSeries(ema10_buffer, true);
   ArraySetAsSeries(ema20_buffer, true);

   // temporary arrays to receive indicator handle data
   double temp10[];
   double temp20[];
   ArraySetAsSeries(temp10, true);
   ArraySetAsSeries(temp20, true);
   ArrayResize(temp10, rates_total);
   ArrayResize(temp20, rates_total);

   int copied10 = CopyBuffer(ema10_handle, 0, 0, rates_total, temp10);
   if(copied10 <= 0)
     {
      // nothing to draw yet
      return(rates_total);
     }

   int copied20 = CopyBuffer(ema20_handle, 0, 0, rates_total, temp20);
   if(copied20 <= 0)
     {
      return(rates_total);
     }

   // fill indicator buffers (aligned as series)
   int limit = MathMin(copied10, copied20);
   for(int i=0;i<limit && i<rates_total;i++)
     {
      ema10_buffer[i] = temp10[i];
      ema20_buffer[i] = temp20[i];
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| OnDeinit function                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(ema10_handle);
   IndicatorRelease(ema20_handle);
  }
//+------------------------------------------------------------------+