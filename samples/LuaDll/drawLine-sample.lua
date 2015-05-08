-- Indicator profile initialization routine
-- Defines indicator profile properties and indicator parameters
function Init()
    indicator:name("drawLine sample");
    indicator:description("Illustrates use of drawLine");
    indicator:requiredSource(core.Bar);
    indicator:type(core.Indicator);
    
    indicator.parameters:addColor("clr", "Color", "", core.rgb(255, 0, 0));
    indicator.parameters:addInteger("width", "Width", "", 1, 1, 5);
    indicator.parameters:addInteger("style", "Style", "", core.LINE_SOLID);
    indicator.parameters:setFlag("style", core.FLAG_LINE_STYLE);
end

-- Indicator instance initialization routine
-- Processes indicator parameters and creates output streams

local source = nil;
local first = 0;
local Color = nil;
local Width = nil;
local Style = nil;
local host = nil;

-- Routine
function Prepare()
    host = core.host;
    source = instance.source;
    first = source:first() + 10;
    require("LuaDll");
    local name = profile:id();
    instance:name(name);
    
    Color = instance.parameters.clr;
    Width = instance.parameters.width;
    Style = instance.parameters.style;
end

local errorLoad = false;

-- Indicator calculation routine
function Update(period)
    if (period >= first) then
        local lineID = 1;
        local fromDate, fromLevel, toDate, toLevel = LuaDll:getLineCoordinates(source.close[period]);
        host:execute("drawLine", lineID, fromDate, fromLevel, toDate, toLevel, Color, Width, Style, "sample line");
    end
end