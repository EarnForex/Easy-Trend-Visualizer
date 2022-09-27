// Original indicator by KurlFX 23/6/09
//+------------------------------------------------------------------+
//|                                            Easy Trend Visualizer |
//|                                 Copyright © 2009-2022, EarnForex |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2009-2022, EarnForex"
#property link      "https://www.earnforex.com/metatrader-indicators/EasyTrendVisualizer/"
#property version   "1.11"
#property strict

#property description "Easy Trend Visualizer - displays trend strength, direction, and support and resistance levels."

#define Alvl 35.0
#define Alvl2 30.0

#property indicator_chart_window
#property indicator_buffers 5
#property indicator_color1 clrRed
#property indicator_color2 clrSteelBlue
#property indicator_width1 2
#property indicator_width2 2
#property indicator_color3 clrIndigo
#property indicator_color4 clrIndigo
#property indicator_color5 clrIndigo
#property indicator_width3 1
#property indicator_width4 1

input int ADXperiod1 = 10;
input int ADXperiod2 = 14;
input int ADXperiod3 = 20;
input bool UseAlertHorizontalLine = false;
input bool UseAlertHorizontalLineCross = false;
input bool UseAlertUpDownArrows = false;
input int NumberPHLtoTrack = 0; // How many previous horizontal lines to track for alert purposes?
input int IgnorePHLShorterThan = 2; // Ignore previous horizontal lines short than
input color PHLC_Arrow_Color = clrChocolate;
input bool NativeAlerts = false; // Use pop-up alerts?
input bool SendEmails = false; // Send alerts via email?
input bool SendNotifications = false; // Send alerts via push notifications?

int MxP, MnP, MdP;

double was_alert_hl = EMPTY_VALUE; // Horizontal line
double was_alert_au = EMPTY_VALUE; // Arrow up
double was_alert_ad = EMPTY_VALUE; // Arrow down
datetime was_alert_hlcross = 0;    // Horizontal line cross

double To[];
double Tc[];
double ADX1[];
double ADX2[];
double ADX3[];
double Up[];
double Dn[];
double Ex[];

double Last_Ex[]; // Buffer to hold previous "last line levels". Required for price/line alert because imaginary line cross also count.
datetime was_alert_phlc[]; // Price crosses and closes above/below previous horizontal line.

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int init()
{
    MxP = MathMax(MathMax(ADXperiod1, ADXperiod2), ADXperiod3);
    MnP = MathMin(MathMin(ADXperiod1, ADXperiod2), ADXperiod3);
    if (MxP == ADXperiod1) MdP = MathMax(ADXperiod2, ADXperiod3);
    else if (MxP == ADXperiod2) MdP = MathMax(ADXperiod1, ADXperiod3);
    else MdP = MathMax(ADXperiod2, ADXperiod1);

    IndicatorShortName("ETV(" + IntegerToString(MnP) + "/" + IntegerToString(MdP) + "/" + IntegerToString(MxP) + ")");

    IndicatorBuffers(8);
    SetIndexBuffer(0, To);
    SetIndexBuffer(1, Tc);
    SetIndexBuffer(2, Up);
    SetIndexBuffer(3, Dn);
    SetIndexBuffer(4, Ex);
    SetIndexBuffer(5, ADX1);
    SetIndexBuffer(6, ADX2);
    SetIndexBuffer(7, ADX3);
    SetIndexLabel(0, NULL);
    SetIndexLabel(1, NULL);
    SetIndexStyle(0, DRAW_HISTOGRAM);
    SetIndexStyle(1, DRAW_HISTOGRAM);
    SetIndexLabel(2, "Up");
    SetIndexLabel(3, "Dn");
    SetIndexLabel(4, "End");
    SetIndexStyle(2, DRAW_ARROW);
    SetIndexStyle(3, DRAW_ARROW);
    SetIndexStyle(4, DRAW_LINE);
    SetIndexArrow(2, 225);
    SetIndexArrow(3, 226);

    ArrayResize(Last_Ex, PHLC_Arrow_Color);
    ArrayInitialize(Last_Ex, EMPTY_VALUE);

    ArrayResize(was_alert_phlc, PHLC_Arrow_Color);
    ArrayInitialize(was_alert_phlc, 0);

    return(0);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void deinit()
{
    // Delete all alert arrows.
    ObjectsDeleteAll(0, "PHLCArrow_", -1, OBJ_ARROW);
}

//+------------------------------------------------------------------+
//| Custom Easy Trend Visualization indicator                        |
//+------------------------------------------------------------------+
int start()
{
    int cntbar = IndicatorCounted();
    int limit = Bars - cntbar;
    if (cntbar == 0) limit -= MxP;
    // Need to update at least the most recent two values for use in the main cycle.
    for (int i = MathMax(limit - 1, 2); i >= 0; i--)
    {
        ADX1[i] = iADX(NULL, 0, MnP, PRICE_CLOSE, MODE_MAIN, i);
        ADX2[i] = iADX(NULL, 0, MdP, PRICE_CLOSE, MODE_MAIN, i);
        ADX3[i] = iADX(NULL, 0, MxP, PRICE_CLOSE, MODE_MAIN, i);
    }

    if (cntbar == 0) limit--;

    for (int i = limit - 1; i >= 0; i--)
    {
        bool f1 = false, f2 = false, f3 = false;
        To[i] = EMPTY_VALUE;
        Tc[i] = EMPTY_VALUE;
        Up[i] = EMPTY_VALUE;
        Dn[i] = EMPTY_VALUE;
        Ex[i] = EMPTY_VALUE;

        // Remember last lines for imaginary crosses.
        if ((NumberPHLtoTrack > 0) && (i + 2 < Bars)) // Check if we fit into arrays.
        {
            // New line found and it has not yet been included.
            if ((Ex[i + 1] == EMPTY_VALUE) && (Ex[i + 2] != EMPTY_VALUE) && (Last_Ex[0] != Ex[i + 2]))
            {
                // Count the length of the added line.
                int length = 1;
                for (int j = i + 3; j < Bars; j++)
                {
                    if (Ex[j] == EMPTY_VALUE) break;
                    length++;
                }

                if (length >= IgnorePHLShorterThan)
                {
                    // Shift arrays (FIFO, 0 - newest):
                    for (int j = NumberPHLtoTrack - 1; j >= 0; j--)
                    {
                        // This check is needed for a very special case of chart data not being fully loaded.
                        // When it is being loaded the indicator is recalculated, but new bars appear from left, not from right as usually.
                        // This keeps rewriting the Last_Ex array with basically the same values, which can lead to lots of unnecessary alerts.
                        if (Time[i + 2] < was_alert_phlc[j]) break;
                        if (j == 0) // Insert new value.
                        {
                            Last_Ex[j] = Ex[i + 2];
                            was_alert_phlc[j] = 0;
                        }
                        else // Shift.
                        {
                            Last_Ex[j] = Last_Ex[j - 1];
                            was_alert_phlc[j] = was_alert_phlc[j - 1];
                        }
                    }
                }
            }
        }

        if (ADX1[i + 1] < ADX1[i]) f1 = true;
        if (ADX2[i + 1] < ADX2[i]) f2 = true;
        if (ADX3[i + 1] < ADX3[i]) f3 = true;

        if ((f1) && (f2) && (f3) && (ADX1[i] > Alvl) && (ADX2[i] > Alvl2))
        {
            double di = iADX(NULL, 0, MnP, PRICE_CLOSE, MODE_PLUSDI,  i)
                      - iADX(NULL, 0, MnP, PRICE_CLOSE, MODE_MINUSDI, i);
            double hi = MathMax(Open[i], Close[i]);
            double lo = MathMin(Open[i], Close[i]);
            double op = Open[i];
            if (di > 0)
            {
                To[i] = lo;
                Tc[i] = hi;
                if (To[i + 1] == EMPTY_VALUE) Up[i] = op;
            }
            else
            {
                To[i] = hi;
                Tc[i] = lo;
                if (To[i + 1] == EMPTY_VALUE) Dn[i] = op;
            }
        }
        else
        {
            if (To[i + 1] != EMPTY_VALUE) Ex[i] = Close[i + 1];
            else Ex[i] = Ex[i + 1];
        }
    }

    // If at least one type and one source of alerts is defined.
    if (((NativeAlerts) || (SendEmails) || (SendNotifications)) && ((UseAlertHorizontalLine) || (UseAlertHorizontalLineCross) || (UseAlertUpDownArrows)))
    {
        string DateTime = TimeToString(Time[0]);
        string PerStr = PeriodToString(Period());
        if (UseAlertHorizontalLine)
        {
            if ((Ex[1] != EMPTY_VALUE) && (Ex[1] != was_alert_hl) && (Ex[1] != Ex[2]))
            {
                string text = "ETV - HL Start ";
                if (To[2] < Tc[2]) text += "After Uptrend ";
                else if (To[2] > Tc[2]) text += "After Downtrend ";
                text += Symbol() + " @ " + PerStr;
                if (NativeAlerts) Alert(text);
                if (SendEmails) SendMail(text, text);
                if (SendNotifications) SendNotification(text);
                was_alert_hl = Ex[1];
            }
        }
        if (UseAlertHorizontalLineCross)
        {
            if ((Ex[1] != EMPTY_VALUE) && (Ex[2] != EMPTY_VALUE) && (was_alert_hlcross != Time[1]) && (((Close[1] > Ex[1]) && (Open[1] <= Ex[1])) || ((Close[1] <= Ex[1]) && (Open[1] > Ex[1]))))
            {
                string text = "ETV - HL Cross ";
                if (Open[1] < Close[1]) text += "Up ";
                else if (Open[1] > Close[1]) text += "Down ";
                text += Symbol() + " @ " + PerStr;
                if (NativeAlerts) Alert(text);
                if (SendEmails) SendMail(text, text);
                if (SendNotifications) SendNotification(text);
                was_alert_hlcross = Time[1];
            }
        }
        if (UseAlertUpDownArrows)
        {
            if ((Up[0] != EMPTY_VALUE) && (Up[0] != was_alert_au))
            {
                string text = "ETV - Arrow Up " + Symbol() + " @ " + PerStr;
                if (NativeAlerts) Alert(text);
                if (SendEmails) SendMail(text, text);
                if (SendNotifications) SendNotification(text);
                was_alert_au = Up[0];
            }
            if ((Dn[0] != EMPTY_VALUE) && (Dn[0] != was_alert_ad))
            {
                string text = "ETV - Arrow Down " + Symbol() + " @ " + PerStr;
                if (NativeAlerts) Alert(text);
                if (SendEmails) SendMail(text, text);
                if (SendNotifications) SendNotification(text);
                was_alert_ad = Dn[0];
            }
        }
        // Alerts for the previous HL crosses.
        if (NumberPHLtoTrack > 0)
        {
            DateTime = TimeToString(Time[1]);
            CheckImaginaryLinesCrosses(DateTime, PerStr);
        }
    }
    
    return(0);
}

string PeriodToString(int per)
{
    switch (per)
    {
    case 60:
        return("H1");
    case 240:
        return("H4");
    case 1440:
        return("D1");
    case 10080:
        return("W1");
    case 43200:
        return("MN1");
    case 30:
        return("M30");
    case 15:
        return("M15");
    case 5:
        return("M5");
    case 1:
        return("M1");
    }
    return("");
}

void CheckImaginaryLinesCrosses(string DateTime, string PerStr)
{
    for (int i = 0; i < NumberPHLtoTrack; i++)
    {
        if ((Last_Ex[i] != EMPTY_VALUE) && (was_alert_phlc[i] != Time[0]) && (((Close[1] > Last_Ex[i]) && (Open[1] <= Last_Ex[i])) || ((Close[1] <= Last_Ex[i]) && (Open[1] > Last_Ex[i]))))
        {
            string text = "ETV - PHLC Cross ";
            if (Open[1] < Close[1]) text += "Up ";
            else if (Open[1] > Close[1]) text += "Down ";
            text += DateTime;
            Alert(text);
            string obj_name = "PHLCArrow_" + DateTime + IntegerToString(i);
            ObjectCreate(0, obj_name, OBJ_ARROW, 0, Time[1], Last_Ex[i]);
            ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, 200);
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, PHLC_Arrow_Color);
            string desc = "Price crossed: " + DoubleToString(Last_Ex[i], Digits()) + " @ " + PerStr;
            ObjectSetString(0, obj_name, OBJPROP_TOOLTIP, desc);
            ObjectSetString(0, obj_name, OBJPROP_TEXT, desc);
            ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, false);
            text += " " + Symbol() + " @ " + PerStr;
            if (SendEmails) SendMail(text, text);
            if (SendNotifications) SendNotification(text);
            was_alert_phlc[i] = Time[0];
        }
    }
}
//+------------------------------------------------------------------+