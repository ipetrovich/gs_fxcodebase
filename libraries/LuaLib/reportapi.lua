-- declare report API interface
reportapi = {};

require("expat_lua");
require("http_lua");

-- the type for the loading requests
reportapi.LOADING = 1;

reportapi.LOAD_DELAY = 1 / 24 / 60 / 6 -- 10 sec

-- the request identifier to be used for the next report request
reportapi.requestID = 0;

-- the list of requests being executed
reportapi.requests = {count = 0};

reportapi.useCache = false

reportapi.lastRequestTime = 0

reportapi.pending = {}

-- the function checks whether the report can be requested
-- returns true if the report can be requested
function reportapi.canRequestReportForCurrentSession()
    if core.host:execute("isTableFilled", "accounts") then
        local url = core.host:execute("getTradingProperty", "ReportURL", nil, account);
        return url ~= nil and url ~= "";
    else
        return false;
    end
end

-- requests the report from the report server associated with the current TS connection
-- associated with the current connection
-- parameters:
--  id          [any]       the request identifier
--  account     [string]    the account to request the report for
--  from        [double]    date (a day) to request the report from
--  to          [double]    date (a day) to request the report to
--  callback    [function]  the callback function to be called when the report loading is finished
--                          the function has three parameters:
--                          id  - the request id (the first value sent to this function)
--                          s   - the boolean flag indicating whether the request has been finished succesfully
--                          xml - the XML content of the report (if s is true)
--                          You can use reportapi.parseReport to parse this xml file.
function reportapi.requestReportForCurrentSession(id, account, from, to, callback)
    if (core.now() - reportapi.lastRequestTime < reportapi.LOAD_DELAY) then
        table.insert(reportapi.pending, {id = id, account = account, from = from, to = to, callback = callback})
        return
    end

    -- get the report URL
    local url = core.host:execute("getTradingProperty", "ReportURL", nil, account);

    url = url .. "&outFormat=xml";

    if from ~= nil then
        local from = core.dateToTable(core.host:execute("convertTime", core.TZ_EST, core.TZ_FINANCIAL, from));
        url = url .. "&from=" .. string.format("%02i/%02i/%04i", from.month, from.day, from.year);
    else
        url = url .. "&from=so";
    end

    if to ~= nil then
        local _to = core.dateToTable(core.host:execute("convertTime", core.TZ_EST, core.TZ_FINANCIAL, to));
        url = url .. "&till=" .. string.format("%02i/%02i/%04i", _to.month, _to.day, _to.year);
    else
        url = url .. "&till=now";
    end

    local request = {};
    reportapi.requestID = reportapi.requestID + 1;
    request.type = reportapi.LOADING;
    request.internal_id = reportapi.requestID;
    request.id = id;
    request.callback = callback;
    request.loader = http_lua.createRequest();
    request.loader:start(url, "GET");
    core.host:trace("HTTP GET")
    reportapi.lastRequestTime = core.now()

    reportapi.requests[request.internal_id] = request;
    reportapi.requests.count = reportapi.requests.count + 1;
end

-- requests the report from the specified report server
-- associated with the current connection
-- parameters:
--  id          [any]       the request identifier
--  server      [string]    the server name
--  user        [string]    the user name
--  password    [string]    the password
--  account     [string]    the account to request the report for
--  from        [double]    date (a day) to request the report from
--  to          [double]    date (a day) to request the report to
--  callback    [function]  the callback function to be called when the report loading is finished
--                          the function has three parameters:
--                          id  - the request id (the first value sent to this function)
--                          s   - the boolean flag indicating whether the request has been finished succesfully
--                          xml - the XML content of the report (if s is true)
--                          You can use reportapi.parseReport to parse this xml file.
function reportapi.requestReportForServer(id, server, user, password, account, from, to, callback)
    -- get the report URL
    local url = "https://fxpa2.fxcorporate.com/fxpa/getreport.app/?signal=get_report&lc=enu&outFormat=xml&report_name=REPORT_NAME_CUSTOMER_ACCOUNT_STATEMENT&app_id=API";

    url = url .. "&cn=" .. server;
    url = url .. "&account=" .. account;

    if from ~= nil then
        local from = core.dateToTable(core.host:execute("convertTime", core.TZ_EST, core.TZ_FINANCIAL, from));
        url = url .. "&from=" .. string.format("%02i/%02i/%04i", from.month, from.day, from.year);
    else
        url = url .. "&from=so";
    end

    if to ~= nil then
        local _to = core.dateToTable(core.host:execute("convertTime", core.TZ_EST, core.TZ_FINANCIAL, toDate));
        url = url .. "&till=" .. string.format("%02i/%02i/%04i", _to.month, _to.day, _to.year);
    else
        url = url .. "&till=now";
    end

    local request = {};
    reportapi.requestID = reportapi.requestID + 1;
    request.type = reportapi.LOADING;
    request.internal_id = reportapi.requestID;
    request.id = id;
    request.callback = callback;
    request.loader = http_lua.createRequest();

    local md2 = http_lua.toHex(http_lua.md2(password));
    local auth = http_lua.toBase64(user .. ":" .. md2);
    request.loader:setAgent("reportapi.lua");
    request.loader:setRequestHeader("Accept", "*/*");
    request.loader:setRequestHeader("Authorization", "Basic " .. auth);
    request.loader:start(url, "GET");
    reportapi.requests[request.internal_id] = request;
    reportapi.lastRequestTime = core.now()
    reportapi.requests.count = requests.count + 1;
end


-- the function which must be called by timer
function reportapi.onTimer()
    if reportapi.requests.count > 0 then
        for k, v in pairs(reportapi.requests) do
            if k ~= "count" then
                if v ~= nil and v.type == reportapi.LOADING then
                    if not v.loader:loading() then
                        if v.loader:success() then
                            if v.loader:httpStatus() ~= 200 then
                                v.callback(v.id, false, "http/" .. v.loader:httpStatus());
                            end

                            local hdr = v.loader:responseHeaders();
                            local i;
                            local err = false;
                            for i = 0, hdr.count - 1, 1 do
                                if string.lower(hdr[i].name) == "x-fxpa_error" and hdr[i].value ~= nil and hdr[i].value ~= "" then
                                    err = true;
                                    v.callback(v.id, false, hdr[i].value);
                                end
                            end
                            if not err then
                                v.callback(v.id, true, v.loader:response());
                            end
                            reportapi.requests[k] = nil;
                            reportapi.requests.count = reportapi.requests.count - 1;
                        else
                            v.callback(v.id, false, nil);
                            reportapi.requests[k] = nil;
                            reportapi.requests.count = reportapi.requests.count - 1;
                        end
                    end
                end
            end
        end
    end

    if #reportapi.pending > 0 then
        if core.now() - reportapi.lastRequestTime >= reportapi.LOAD_DELAY then
            local request = table.remove(reportapi.pending, 1)
            reportapi.requestReportForCurrentSession(request.id, request.account, request.from, request.to, request.callback)
        end
    end
end

-- waits while all requests are finished
function reportapi.waitAll()
    if reportapi.requests.count > 0 then
        while reportapi.requests.count > 0 do
            reportapi.onTimer();
        end
    end
end

function reportapi.cancelAll()
    if reportapi.requests.count > 0 then
        for k, v in pairs(reportapi.requests) do
            if k ~= "count" then
                if v ~= nil and v.type == reportapi.LOADING then
                    v.loader:cancel();
                    reportapi.requests[k] = nil;
                    reportapi.requests.count = reportapi.requests.count - 1;
                end
            end
        end
    end
end

function reportapi.running()
    return reportapi.requests.count > 0 or #reportapi.pending > 0
end

-- Utility: Parse the date/time string and convert it into EST time zone
function reportapi.parseDate(dateString)
    local pos = 1;
    local year, month, day, hour, minute, second = string.match(dateString, "(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)", pos);
    local reportDate = {};
    reportDate.month = tonumber(month);
    reportDate.day = tonumber(day);
    reportDate.year = tonumber(year);
    reportDate.hour = tonumber(hour);
    reportDate.min = tonumber(minute);
    reportDate.sec = tonumber(second);
    return core.host:execute("convertTime", core.TZ_SERVER, core.TZ_EST, core.tableToDate(reportDate));
end

-- internal function - creates the report parser
local function createParser()
    -- the type of the column
    local DATE = 1;
    local NUMBER = 2;
    local STRING = 3;

    return {
        report = {tables = {}, parameters = {}},            -- the report content

        current_table = nil,
        current_row = nil;
        current_cell = nil;

        -- SAX: handler for the comment content
        comment = function(this, data)
        end,

        -- SAX: handler for CDATA start
        startCDATA = function(this)
        end,

        -- SAX: handler for CDATA end
        endCDATA = function(this)
        end,

        -- SAX: handler for namespace start
        startNamespace = function(this, prefix, uri)
        end,

        -- SAX: handler for namespace end
        endNamespace = function(this, prefix)
        end,

        -- SAX: handler for processing instruction
        processingInstruction = function(this, target, data)
        end,


        -- SAX: handler for element start
        startElement = function(this, name, attributes)
            local itemName = this:extractName(name);
            if itemName == "parameter" then
                this.current_param = {}
                this.current_param.name = this:getAttribute(attributes, "name")
            elseif itemName == "table" then
                local tableName = this:getAttribute(attributes, "name");
                local tableName1 = tableName;
                local i = 1;
                this.current_table = {};
                while this.report.tables[tableName1] ~= nil do
                    tableName1 = tableName .. tostring(i);
                    i = i + 1;
                end
                this.current_table.name = tableName;
                this.current_table.columns = {};
                this.current_table.rows = {};
                this.current_table.rows.count = 0;
                this.report.tables[tableName1] = this.current_table;
            elseif itemName == "column" then
                if this.current_table ~= nil then
                    local columnName = this:getAttribute(attributes, "name");
                    local columnType = this:getAttribute(attributes, "type");
                    if columnType == "DATE" then
                        columnType = DATE;
                    elseif columnType == "LONG" or columnType == "INTEGER" or columnType == "DOUBLE" then
                        columnType = NUMBER;
                    else
                        columnType = STRING;
                    end
                    local column = {};
                    column.name = columnName;
                    column.type = columnType;
                    this.current_table.columns[columnName] = column;
                end
            elseif itemName == "row" then
                if this.current_table ~= nil then
                    this.current_row = {};
                end
            elseif itemName == "cell" then
                if this.current_row ~= nil then
                    local cellName = this:getAttribute(attributes, "name");
                    local cell = {};
                    cell.name = cellName;
                    cell.column = this.current_table.columns[cellName];
                    cell.value = nil;
                    this.current_cell = cell;
                end
            end
        end,

        -- SAX: handler for element end
        endElement = function(this, name)
            local itemName = this:extractName(name);
            if itemName == "table" then
                this.current_table = nil;
            elseif itemName == "row" then
                -- move to end with 'grouping type testing'
                if this.current_row.grouping_type ~= 3 then
                    this.current_table.rows.count = this.current_table.rows.count + 1;
                    this.current_table.rows[this.current_table.rows.count] = this.current_row;
                elseif this.current_row.grouping_type == 3 then
                    this.current_table.total = this.current_row
                end

                this.current_row = nil;
            elseif itemName == "cell" then
                if this.current_cell ~= nil and this.current_row ~= nil then
                    this.current_row[this.current_cell.name] = this.current_cell.value;
                end
                this.current_cell = nil;
            elseif itemName == "parameter" then
                if this.report.parameters == nil then
                    this.report.parameters = {}
                end
                this.report.parameters[this.current_param.name] = this.current_param.value
                this.current_param = nil
            end
        end,

        -- SAX: handler for the tag content
        characters = function(this, data)
            if this.current_cell ~= nil then
                local value = nil;
                if this.current_cell.column ~= nil then
                    if this.current_cell.column.type == DATE then
                        this.current_cell.value = reportapi.parseDate(data);
                    elseif this.current_cell.column.type == NUMBER then
                        this.current_cell.value = tonumber(data);
                    else
                        this.current_cell.value = data;
                    end
                else
                    this.current_cell.value = data;
                end
            elseif this.current_param ~= nil then
                this.current_param.value = data
            end
        end,

        -- Utility: Find attribute and return its value
        getAttribute = function (this, attributes, name)
            local i;
            for i = 0, attributes.count - 1, 1 do
                if this:extractName(attributes[i].name) == name then
                    return attributes[i].value;
                end
            end
            return nil;
        end,

        -- Utility: Extract the node name from namespace|node notation
        extractName = function(this, name)
            local pos = string.find(name, "|");
            if pos == nil then
                return name;
            end
            return string.sub(name, pos + 1, string.len(name));
        end,
    };
end


-- parses the report
-- parameters:
--  xml     report
function reportapi.parseXml(xml)
    local parser = createParser();
    expat_lua.parseSAX(xml, parser);
    return parser.report;
end
