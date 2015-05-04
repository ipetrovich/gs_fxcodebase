--+------------------------------------------------------------------+
--|                                                    Mogalef.lua   |
--|                               Copyright © 2015, Gehtsoft USA LLC | 
--|                                            http://fxcodebase.com |
--+------------------------------------------------------------------+
--|                                      Developed by : Mario Jemic  |     
--|                                          mario.jemic@gmail.com   |
--|                               Developed by : Victor Tereschenko  |        
--+------------------------------------------------------------------+
--|                                 Support our efforts by donating  | 
--|                                    Paypal: http://goo.gl/cEP5h5  |
--|                    BitCoin : 1MfUHS3h86MBTeonJzWdszdzF2iuKESCKU  |  
--+------------------------------------------------------------------+

-- http://fxcodebase.com/code/viewtopic.php?f=17&t=4449

-- Indicator profile initialization routine
-- Defines indicator profile properties and indicator parameters
-- TODO: Add minimal and maximal value of numeric parameters and default color of the streams
function Init()
    indicator:name("Mogalef");
    indicator:description("Mogalef");
    indicator:requiredSource(core.Bar);
    indicator:type(core.Indicator);

    indicator.parameters:addGroup("Calculation");    
    indicator.parameters:addInteger("LRL", "Linear Regression Length", "Linear Regression Length", 3);
    indicator.parameters:addInteger("SDL", "Standard Deviation Length", "Standard Deviation Length", 7);
    indicator.parameters:addInteger("Multiplier", "Standard Deviation Multiplier", "Linear Regression Multiplier", 2);
    
    indicator.parameters:addGroup("Style");    
    indicator.parameters:addColor("Top_color", "Color of Top", "", core.rgb(0, 255, 0));
    indicator.parameters:addColor("Median_color", "Color of Median", "", core.rgb(255, 0, 0));
    indicator.parameters:addColor("Bottom_color", "Color of Bottom", "", core.rgb(0, 0, 255));
    
    indicator.parameters:addInteger("Top_width", "Top Line width", "", 1, 1, 5);
    indicator.parameters:addInteger("Top_style", "Top Line style", "", core.LINE_SOLID);
    indicator.parameters:setFlag("Top_style", core.FLAG_LINE_STYLE);
    
    indicator.parameters:addInteger("Bottom_width", "Bottom Line width", "", 1, 1, 5);
    indicator.parameters:addInteger("Bottom_style", "Bottom Line style", "", core.LINE_SOLID);
    indicator.parameters:setFlag("Bottom_style", core.FLAG_LINE_STYLE);
    
    indicator.parameters:addInteger("Median_width", "Median Line width", "", 1, 1, 5);
    indicator.parameters:addInteger("Median_style", "Median Line style", "", core.LINE_SOLID);
    indicator.parameters:setFlag("Median_style", core.FLAG_LINE_STYLE);
    indicator.parameters:addInteger("transparency", "Channel transparency (%)", "", 70, 0, 100);
    indicator.parameters:addBoolean("draw_channels", "Draw Channels", "", false);
    indicator.parameters:addColor("Top_stream_color", "Color of Top stream", "", core.rgb(0, 255, 0));
    indicator.parameters:addColor("Bottom_stream_color", "Color of Bottom stream", "", core.rgb(255, 0, 0));
end

-- Indicator instance initialization routine
-- Processes indicator parameters and creates output streams
-- TODO: Refine the first period calculation for each of the output streams.
-- TODO: Calculate all constants, create instances all subsequent indicators and load all required libraries
-- Parameters block
local LRL;
local SDL;

local first;
local source = nil;

-- Streams block
local Top = nil;
local Median = nil;
local Bottom = nil;
local Multiplier;
local DEV; 
local PRICE;
local topIntStr, midIntStrTop, midIntStrBottom, botIntStr;

-- Routine
function Prepare()
    Multiplier = instance.parameters.Multiplier;
    LRL = instance.parameters.LRL;
    SDL = instance.parameters.SDL;
    source = instance.source;
    first = source:first();
    
    PRICE = instance:addInternalStream(first, 0);
    DEV = instance:addInternalStream(first, 0);
    
    local name = profile:id() .. "(" .. source:name() .. ", " .. LRL .. ", " .. SDL .. ")";
    instance:name(name);
    Top = instance:addStream("Top", core.Line, name .. ".Top", "Top", instance.parameters.Top_color, first);
    Median = instance:addStream("Median", core.Line, name .. ".Median", "Median", instance.parameters.Median_color, first);
    Bottom = instance:addStream("Bottom", core.Line, name .. ".Bottom", "Bottom", instance.parameters.Bottom_color, first);
    
    Top:setWidth(instance.parameters.Top_width);
    Top:setStyle(instance.parameters.Top_style);
    
    Bottom:setWidth(instance.parameters.Bottom_width);
    Bottom:setStyle(instance.parameters.Bottom_style);
    
    Median:setWidth(instance.parameters.Median_width);
    Median:setStyle(instance.parameters.Median_style);
    
    if instance.parameters.draw_channels then
        topIntStr        = instance:addInternalStream(first, 0);
        midIntStrTop     = instance:addInternalStream(first, 0);
	midIntStrBottom  = instance:addInternalStream(first, 0);
        botIntStr        = instance:addInternalStream(first, 0);
        instance:createChannelGroup("topCh", "topCh", topIntStr, midIntStrTop, instance.parameters.Top_stream_color, 100 - instance.parameters.transparency);
        instance:createChannelGroup("botCh", "botCh", midIntStrBottom, botIntStr, instance.parameters.Bottom_stream_color, 100 - instance.parameters.transparency);
    end
end

-- Indicator calculation routine
-- TODO: Add your code for calculation output values
function Update(period)
    if period >= first and source:hasData(period) then
        PRICE[period] = (source.open[period] + source.low[period] + source.high[period] + (2 * source.close[period])) / 5
        
        if period < first + LRL then 
            return;
        end
        
        if period < SDL then 
            return;
        end
        
        Median[period] = mathex.lreg(PRICE, period - LRL, period);
        
        DEV[period] = mathex.stdev(source.close, period - SDL, period);
        
        Top[period]    = Median[period] + Multiplier * DEV[period];
        Median[period] = Median[period];
        Bottom[period] = Median[period] - Multiplier * DEV[period];
        
        if Median[period] < Top[period - 1] and Median[period] > Bottom[period - 1] then 
            DEV[period]    = DEV[period - 1];
            Top[period]    = Top[period - 1];            
            Bottom[period] = Bottom[period - 1];
            Median[period] = Median[period - 1];
        end
		
        if topIntStr ~= nil then
            topIntStr[period]       = Top[period];
            midIntStrTop[period]    = Median[period];
            midIntStrBottom[period] = Median[period];
            botIntStr[period]       = Bottom[period];
        end
    end
end


