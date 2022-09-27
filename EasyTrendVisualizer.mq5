//+------------------------------------------------------------------+
//|                                            Easy Trend Visualizer |
//|                                 Copyright © 2009-2022, EarnForex |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2009-2022, EarnForex"
#property link      "https://www.earnforex.com/metatrader-indicators/EasyTrendVisualizer/"
#property version   "1.11"

#property description "Easy Trend Visualizer - displays trend strength, direction, and support and resistance levels."

#define Alvl 35.0
#define Alvl2 30.0

#property indicator_chart_window
#property indicator_buffers 9
#property indicator_plots   4
#property indicator_color1 clrRed, clrSteelBlue
#property indicator_width1 2
#property indicator_color2 clrLime
#property indicator_color3 clrLime
#property indicator_color4 clrIndigo
#property indicator_width2 2
#property indicator_width3 2
#property indicator_width4 1
#property indicator_type1  DRAW_COLOR_HISTOGRAM2
#property indicator_style1 STYLE_SOLID
#property indicator_type2  DRAW_ARROW
#property indicator_style2 STYLE_SOLID
#property indicator_type3  DRAW_ARROW
#property indicator_style3 STYLE_SOLID
#property indicator_type4  DRAW_LINE
#property indicator_style4 STYLE_SOLID

input int ADXperiod1 = 10;
input int ADXperiod2 = 14;
input int ADXperiod3 = 20;
input bool UseAlertHorizontalLine = false;
input bool UseAlertUpDownArrows = false;
input bool UseAlertHorizontalLineCross = false;
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
double Color[];
double Up[];
double Dn[];
double Ex[];

double ADX1[];
double ADX2[];
double ADX3[];

double Last_Ex[]; // Buffer to hold previous "last line levels". Required for price/line alert because imaginary line cross also count.
datetime was_alert_phlc[]; // Price crosses and closes above/below previous horizontal line.

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
void OnInit()
{
    MxP = MathMax(MathMax(ADXperiod1, ADXperiod2), ADXperiod3);
    MnP = MathMin(MathMin(ADXperiod1, ADXperiod2), ADXperiod3);
    if (MxP == ADXperiod1) MdP = MathMax(ADXperiod2, ADXperiod3);
    else if (MxP == ADXperiod2) MdP = MathMax(ADXperiod1, ADXperiod3);
    else MdP = MathMax(ADXperiod2, ADXperiod1);

    IndicatorSetString(INDICATOR_SHORTNAME, "ETV(" + IntegerToString(MnP) + "/" + IntegerToString(MdP) + "/" + IntegerToString(MxP) + ")");

    SetIndexBuffer(0, To, INDICATOR_DATA);
    SetIndexBuffer(1, Tc, INDICATOR_DATA);
    SetIndexBuffer(2, Color, INDICATOR_COLOR_INDEX);
    SetIndexBuffer(3, Up, INDICATOR_DATA);
    SetIndexBuffer(4, Dn, INDICATOR_DATA);
    SetIndexBuffer(5, Ex, INDICATOR_DATA);
    SetIndexBuffer(6, ADX1, INDICATOR_CALCULATIONS);
    SetIndexBuffer(7, ADX2, INDICATOR_CALCULATIONS);
    SetIndexBuffer(8, ADX3, INDICATOR_CALCULATIONS);

    ArraySetAsSeries(To, true);
    ArraySetAsSeries(Tc, true);
    ArraySetAsSeries(Color, true);
    ArraySetAsSeries(Up, true);
    ArraySetAsSeries(Dn, true);
    ArraySetAsSeries(Ex, true);
    ArraySetAsSeries(ADX1, true);
    ArraySetAsSeries(ADX2, true);
    ArraySetAsSeries(ADX3, true);

    PlotIndexSetInteger(1, PLOT_ARROW, 225);
    PlotIndexSetInteger(2, PLOT_ARROW, 226);

    PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, MxP);
    PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, MxP);
    PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, MxP);
    PlotIndexSetInteger(3, PLOT_DRAW_BEGIN, MxP + 1);

    PlotIndexSetString(1, PLOT_LABEL, "Up");
    PlotIndexSetString(2, PLOT_LABEL, "Down");
    PlotIndexSetString(3, PLOT_LABEL, "End");

    ArrayResize(Last_Ex, PHLC_Arrow_Color);
    ArrayInitialize(Last_Ex, EMPTY_VALUE);

    ArrayResize(was_alert_phlc, PHLC_Arrow_Color);
    ArrayInitialize(was_alert_phlc, 0);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Delete all alert arrows.
    ObjectsDeleteAll(0, "PHLCArrow_", -1, OBJ_ARROW);
}

//+------------------------------------------------------------------+
//| Custom Easy Trend Visualizer                                     |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &Time[],
                const double &Open[],
                const double &high[],
                const double &low[],
                const double &Close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    ArraySetAsSeries(Open, true);
    ArraySetAsSeries(Close, true);
    ArraySetAsSeries(Time, true);

    int limit = rates_total - prev_calculated;
    if (prev_calculated == 0) limit -= MxP;
    double ADXBuffer1[], ADXBuffer2[], ADXBuffer3[], ADXBuffer1_1[], ADXBuffer1_2[];
    int myADX = iADX(NULL, 0, MnP);
    if (CopyBuffer(myADX, MAIN_LINE, 0, rates_total, ADXBuffer1) != rates_total) return(0);
    if (CopyBuffer(myADX, PLUSDI_LINE, 0, rates_total, ADXBuffer1_1) != rates_total) return(0);
    if (CopyBuffer(myADX, MINUSDI_LINE, 0, rates_total, ADXBuffer1_2) != rates_total) return(0);
    myADX = iADX(NULL, 0, MdP);
    if (CopyBuffer(myADX, MAIN_LINE, 0, rates_total, ADXBuffer2) != rates_total) return(0);
    myADX = iADX(NULL, 0, MxP);
    if (CopyBuffer(myADX, MAIN_LINE, 0, rates_total, ADXBuffer3) != rates_total) return(0);

    for (int i = rates_total - 1; i >= 0; i--)
    {
        ADX1[i] = ADXBuffer1[rates_total - i - 1];
        ADX2[i] = ADXBuffer2[rates_total - i - 1];
        ADX3[i] = ADXBuffer3[rates_total - i - 1];
    }

    if (prev_calculated == 0) limit--;

    if (limit < 1) limit = 2;
    for (int i = limit - 1; i >= 0; i--)
    {
        bool f1 = false, f2 = false, f3 = false;
        To[i] = EMPTY_VALUE;
        Tc[i] = EMPTY_VALUE;
        Up[i] = EMPTY_VALUE;
        Dn[i] = EMPTY_VALUE;
        Ex[i] = EMPTY_VALUE;

        int k = i + 1;

        // Remember last lines for imaginary crosses.
        if ((NumberPHLtoTrack > 0) && (i + 2 < rates_total)) // Check if we fit into arrays.
        {
            // New line found and it has not yet been included:
            // It did not exist on a previous bar, it did exist on the pre-previous bar and the latest recorded line is not it.
            if ((Ex[i + 1] == EMPTY_VALUE) && (Ex[i + 2] != EMPTY_VALUE) && (Last_Ex[0] != Ex[i + 2]))
            {
                // Count the length of the added line.
                int length = 1;
                for (int j = i + 3; j < rates_total; j++)
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

        if (ADX1[k] < ADX1[i]) f1 = true;
        if (ADX2[k] < ADX2[i]) f2 = true;
        if (ADX3[k] < ADX3[i]) f3 = true;

        if ((f1) && (f2) && (f3) && (ADX1[i] > Alvl) && (ADX2[i] > Alvl2))
        {
            double di = ADXBuffer1_1[rates_total - i - 1] - ADXBuffer1_2[rates_total - i - 1];
            double hi = MathMax(Open[i], Close[i]);
            double lo = MathMin(Open[i], Close[i]);
            double op = Open[i];
            if (di > 0)
            {
                To[i] = lo;
                Tc[i] = hi;
                if (To[k] == EMPTY_VALUE) Up[i] = op;
                Color[i] = 1;

            }
            else
            {
                To[i] = hi;
                Tc[i] = lo;
                if (To[k] == EMPTY_VALUE) Dn[i] = op;
                Color[i] = 0;
            }
        }
        else
        {
            if (To[k] != EMPTY_VALUE)
            {
                Ex[i] = Close[i + 1];
            }
            else Ex[i] = Ex[k];
        }
    }

    // If at least one type and one source of alerts is defined.
    if (((NativeAlerts) || (SendEmails) || (SendNotifications)) && ((UseAlertHorizontalLine) || (UseAlertHorizontalLineCross) || (UseAlertUpDownArrows)))
    {
        string DateTime = TimeToString(Time[0]);
        string PerStr = EnumToString(Period());
        if (UseAlertHorizontalLine)
        {
            if ((Ex[1] != EMPTY_VALUE) && (Ex[1] != was_alert_hl) && (Ex[1] != Ex[2]))
            {
                string text = "ETV - HL Start ";
                if (To[2] < Tc[2]) text += "After Uptrend";
                else if (To[2] > Tc[2]) text += "After Downtrend";
                if (NativeAlerts) Alert(text);
                text += " " + Symbol() + " @ " + PerStr;
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
                if (Open[1] < Close[1]) text += "Up";
                else if (Open[1] > Close[1]) text += "Down";
                if (NativeAlerts) Alert(text);
                text += " " + Symbol() + " @ " + PerStr;
                if (SendEmails) SendMail(text, text);
                if (SendNotifications) SendNotification(text);
                was_alert_hlcross = Time[1];
            }
        }
        if (UseAlertUpDownArrows)
        {
            if ((Up[0] != 0) && (Up[0] != was_alert_au))
            {
                string text = "ETV - Arrow Up";
                if (NativeAlerts) Alert(text);
                text += " " + Symbol() + " @ " + PerStr;
                if (SendEmails) SendMail(text, text);
                if (SendNotifications) SendNotification(text);
                was_alert_au = Up[0];
            }
            if ((Dn[0] != 0) && (Dn[0] != was_alert_ad))
            {
                string text = "ETV - Arrow Down";
                if (NativeAlerts) Alert(text);
                text += " " + Symbol() + " @ " + PerStr;
                if (SendEmails) SendMail(text, text);
                if (SendNotifications) SendNotification(text);
                was_alert_ad = Dn[0];
            }
        }
        // Alerts for the previous HL crosses.
        if (NumberPHLtoTrack > 0)
        {
            DateTime = TimeToString(Time[1]);
            CheckImaginaryLinesCrosses(DateTime, PerStr, Time, Open, Close);
        }
    }

    return(rates_total);
}

void CheckImaginaryLinesCrosses(const string DateTime, const string PerStr, const datetime &Time[], const double &Open[], const double &Close[])
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
            string obj_name = "PHLCArrow_" + DateTime + "-" + IntegerToString(i);
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