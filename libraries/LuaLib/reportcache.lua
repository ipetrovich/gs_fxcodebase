-- declare report cache interface
reportcache = {};

reportcache.version = 2

--reportcache.waiting_trades = {}
reportcache.closed_version = nil;
reportcache.closed_trades  = {}
reportcache.activities     = {}

reportcache.temp_folder = nil;
reportcache.loaded      = false;
reportcache.changed     = false;
reportcache.last_update_date = 0

reportcache.HOUR = 1 / 24

function reportcache.initialize(account)
	--core.host:trace("reportcache.initialize")
	self = reportcache

	self.account    = account

	self.init_temp_folder()
end

--------------------------------------------------
-- Return table containing all closed_trades.
-- The table can be empty on the moment of calling, and
-- will be filled later
--------------------------------------------------
function reportcache.get_closed_trades()
	--core.host:trace("reportcache.get_closed_trades")
	self = reportcache

	if not self.loaded then
		self.load_cache()
	end

	return self.closed_trades
end

function reportcache.get_activities()
	--core.host:trace("reportcache.get_closed_trades")
	self = reportcache

	if not self.loaded then
		self.load_cache()
	end

	return self.activities
end

function reportcache.load_cache()
	--core.host:trace("reportcache.load_cache")
	self = reportcache

	if not self.load_from_disk() then
		return
	else
		table_trades = self.get_table_trades()

		if #table_trades == 0 then
			local now_day  = self.get_financial_day(self.now())
			local last_day = timeutils.breakdate(self.last_update_date)
			if now_day > last_day then
				update = true
			end
		elseif table_trades[1].close_date > self.last_update_date then
			update = true
		end

		if update then
			self.request_from_server(self.last_update_date)
		else
			for _, trade in pairs(table_trades) do
				self.add_trade(trade)
			end
		end
	end

	self.loaded  = true
	self.changed = true
end

function reportcache.get_table_trades()
	--core.host:trace("reportcache.get_table_trades")
	self = reportcache

	local table_trades = {}
	for row in rows("closed trades") do
		local closed_trade = self.get_trade_from_row(row)
		table.insert(table_trades, closed_trade)
	end

	table.sort(table_trades, self.closed_trades_compare)
	return table_trades
end

-------------------------------------
-- Load closed_trades from disk
-- cache will be created if empty
--
function reportcache.load_from_disk()
	--core.host:trace("reportcache.load_from_disk")
	self = reportcache

	if self.is_blocked() then
		return false
	end

	f = io.open(temp_folder .. "\\last_update", "r")
	if f ~= nil then
	   	self.last_update_date = f:read("*n") or 0

	   	local last_version = f:read("*n") or 1
	   	if last_version < self.version then
			os.remove(temp_folder .. "\\closed_trades")	   		
			os.remove(temp_folder .. "\\activities")	   		
			self.last_update_date = 0
	   	end
	   	f:close()
	end

	f = io.open(temp_folder .. "\\closed_trades", "r")
	if f ~= nil then
	   	local line = f:read()

	   	while line ~= nil do
	   		local closed_trade = self.get_trade_from_string(line)
	   		self.add_trade(closed_trade)
			line = f:read()
		end	   		
	   	f:close()
	end

	f = io.open(temp_folder .. "\\activities", "r")
	if f ~= nil then
	   	local line = f:read()

	   	while line ~= nil do
	   		local activity = self.get_activity_from_string(line)
	   		self.add_activity(activity)
			line = f:read()
		end	   		
	   	f:close()
	end


	return true
end

function reportcache.request_from_server(start_date)
	core.host:trace("reportcache.request_from_server(" .. core.formatDate(start_date) .. ")")
	self = reportcache

	local last_day  = self.get_financial_day(self.now())
	local first_day = 0

	if (start_date ~= nil) then
		first_day = timeutils.breakdate(start_date)
	end

	self.block()
    reportapi.requestReportForCurrentSession(nil, self.account, first_day, last_day, self.on_report_loaded)
end

function reportcache.add_trade(closed_trade)
	--core.host:trace("reportcache.add_trade")
	self = reportcache

	if #self.closed_trades == 0 then
		table.insert(self.closed_trades, closed_trade)
	else
		local last_trade = self.closed_trades[#self.closed_trades]

		if (closed_trade.close_date > last_trade.close_date) then
			table.insert(self.closed_trades, closed_trade)
		end
	end
end

function reportcache.add_activity(activity)
	--core.host:trace("reportcache.add_trade")
	self = reportcache

	if #self.activities == 0 then
		table.insert(self.activities, activity)
	else
		local last_activity = self.activities[#self.activities]

		if (activity.date > last_activity.date) then
			table.insert(self.activities, activity)
		end
	end
end

function reportcache.closed_trades_compare(ct1, ct2)
    return ct1.close_date < ct2.close_date
end

function reportcache.activity_compare(act1, act2)
    return act1.date < act2.date
end


--===================================================================
--========     CALLBACKS FUNCTIONS     ==============================
--===================================================================

function reportcache.onTimer()
	local self = reportcache

	local closed_trades_table = core.host:findTable("closed trades");

	if self.closed_version ~= closed_trades_table:version() then
		local closed_trades = self.get_table_trades()

	    for _, ctrade in pairs(closed_trades) do
            --Check if trade already in closed_trades
            -- if ctrade.account and ctrade.instrument
            local found = false
            for _, ct in ipairs(self.closed_trades) do
                if ct.ticket_id == ctrade.ticket_id then
                    found = true
                    break
                end
            end

            if not(found) then
                --local closed_trade = self.get_trade_from_row(ctrade)
                self.add_trade(ctrade)
                self.changed = true
            end
        end

        self.closed_version = closed_trades_table:version() 
    end

    -- Report changed status
    if self.changed then
    	self.changed = false
    	return true
    end

    return false
end

--function reportcache.onTrades(message)
	--local self = reportcache
	--core.host:trace("reportcache.onTrades" .. message)
	--table.insert(self.waiting_trades, message)
--end

function reportcache.on_report_loaded(id, success, xml)
	--core.host:trace("reportcache.on_report_loaded")
	local self = reportcache

    if success then
        local report = reportapi.parseXml(xml);
    
        --=================== CLOSED TRADES =========================
        local add_trades = {}

        for _, row in ipairs(report.tables.closed_trades.rows) do
            if row.grouping_type ~= 3 then --and row.symbol == source:instrument() then
            	local closed_trade = self.get_trade_from_xmlrow(row)
                table.insert(add_trades, closed_trade)
            end
        end

        table.sort(add_trades, self.closed_trades_compare)

        for _, ctrade in pairs(add_trades) do
			self.add_trade(ctrade)
		end

		--=================== ACCOUNT ACTIVITIES =========================
		local add_activities = {}

        for _, act in ipairs(report.tables.account_activity.rows) do
            if act.grouping_type ~= 3 then
                local activity = {}

                activity.date = act.time_posted
                activity.balance = act.balance

                table.insert(add_activities, activity)
            end
        end

		table.sort(add_activities, self.activity_compare)

        for _, act in pairs(add_activities) do
			self.add_activity(act)
		end
    end

    self.changed = true
    self.sync()
    self.unblock()
end

--====================================================================
--========     FILE UTILS FUNCTIONS     ==============================
--====================================================================

-- initializes the temporary folder to store the cache
function reportcache.init_temp_folder()
	--core.host:trace("reportcache.init_temp_folder")
	self = reportcache

    if temp_folder == nil then
        local file, file_h, error;

        temp_folder = core:app_path() .. "\\reportcache\\" .. self.account;

        file = temp_folder .. "\\test.txt";
        local file_h, err = io.open(file, "w");
        if file_h ~= nil then
            file_h:close();
            os.remove(file);
        else
            os.execute("mkdir \"" .. temp_folder .. "\"");
        end
    end
end 

function reportcache.is_blocked()
	--core.host:trace("reportcache.is_blocked")
	self = reportcache

	local now = self.now()
	local blocked = false

	f = io.open(temp_folder .. "\\blocking", "r")
	if f ~= nil then
	   	since = f:read("*n") or 0
	   	f:close()

	   	if (now - since) < self.HOUR then
	   		blocked = true
	   	end
	end

	return blocked
end

function reportcache.block()
	--core.host:trace("reportcache.block")
	self = reportcache

	f = io.open(temp_folder .. "\\blocking", "w")
	f:write(self.now())
	f:close()
end

function reportcache.unblock()
	--core.host:trace("reportcache.unblock")
	self = reportcache

	os.remove(temp_folder .. "\\blocking")
end

function reportcache.sync()
	--core.host:trace("reportcache.sync")
	self = reportcache

	local f = io.open(temp_folder .. "\\closed_trades", "a")

	if f ~= nil then
		for _, ctrade in pairs(self.closed_trades) do
			if ctrade.close_date > self.last_update_date then
				f:write(self.print_trade_to_string(ctrade))
			end
		end
		f:close()
	end

	local f = io.open(temp_folder .. "\\activities", "a")

	if f ~= nil then
		for _, act in pairs(self.activities) do
			if act.date > self.last_update_date then
				f:write(self.print_activity_to_string(act))
			end
		end
		f:close()
	end

	f = io.open(temp_folder .. "\\last_update", "w")
	if f ~= nil then
		f:write(self.now() .. "\n")
		f:write(self.version)
		f:close()
	end
end



--====================================================================
--========     TIME UTILS FUNCTIONS     ==============================
--====================================================================

function reportcache.now()
	return core.host:execute("convertTime", core.TZ_LOCAL, core.TZ_EST, core.now())
end

function reportcache.get_financial_day(dt)
	local day, time = timeutils.breakdate(core.host:execute ("convertTime", core.TZ_EST, core.TZ_FINANCIAL, dt))
	return day
end

--===========================================================================
--========     PARSING/PRINTING FUNCTIONS     ===============================
--===========================================================================


function reportcache.get_trade_from_row(ctrade)
	local closed_trade = {}

	--core.host:trace(ctrade.TradeID .. "," .. ctrade.OpenTime)
    closed_trade.ticket_id = ctrade.TradeID
    closed_trade.open_date = ctrade.OpenTime
    closed_trade.open_day, closed_trade.open_time = timeutils.breakdate(ctrade.OpenTime)
    closed_trade.open_rate = ctrade.Open
    closed_trade.close_date = ctrade.CloseTime
    closed_trade.close_day, closed_trade.close_time = timeutils.breakdate(ctrade.CloseTime)
    closed_trade.close_rate = ctrade.Close
    closed_trade.net_pl = ctrade.GrossPL - ctrade.Com + ctrade.Int
    closed_trade.gross_pl = ctrade.GrossPL
    closed_trade.quantity = ctrade.BS == "B" and 1 or -1
    closed_trade.volume   = ctrade.Lot
    closed_trade.symbol = ctrade.Instrument

    return closed_trade
end

function reportcache.get_trade_from_string(line)
	local closed_trade = {}

    closed_trade.ticket_id,  closed_trade.open_date, closed_trade.open_rate, closed_trade.close_date, 
    closed_trade.close_rate, closed_trade.net_pl,    closed_trade.gross_pl, closed_trade.quantity,
    closed_trade.volume, 	 closed_trade.symbol = line:match("(%d+),([%d%.]+),(.+),(.+),(.+),(.+),(.+),(.+),(.+),(.+)")

    closed_trade.open_date  = tonumber(closed_trade.open_date)
    closed_trade.open_rate  = tonumber(closed_trade.open_rate)
    closed_trade.close_date = tonumber(closed_trade.close_date)
    closed_trade.close_rate = tonumber(closed_trade.close_rate)
    closed_trade.quantity   = tonumber(closed_trade.quantity)
    --core.host:trace("Parsed: " .. reportcache.print_trade_to_string(closed_trade))

    return closed_trade
end

function reportcache.get_activity_from_string(line)
	local activity = {}

	activity.balance, activity.date = line:match("([%d%.]+),([%d%.]+)")

	activity.balance = tonumber(activity.balance)
	activity.date    = tonumber(activity.date)

	return activity
end

function reportcache.print_trade_to_string(ctrade)
	
    return "" .. ctrade.ticket_id .. "," .. ctrade.open_date .. "," .. ctrade.open_rate .. "," .. ctrade.close_date .. "," ..
    			 ctrade.close_rate .. "," .. ctrade.net_pl .. "," ..  ctrade.gross_pl .. "," .. ctrade.quantity .. "," ..
    			 tostring(ctrade.volume) .. "," .. tostring(ctrade.symbol) .. "\n"

end

function reportcache.print_activity_to_string(act)
    return "" .. act.balance .. "," .. act.date .. "\n"

end

function reportcache.get_trade_from_xmlrow(ctrade)
    -- ctrade = adj, closed_by, precision, net_pl, ticket_id, close_rate, quantity, statement_gross_pl, grouping_type, open_order_id, open_condition, 
    --          created_by, symbol, close_order_id, close_date, close_condition, open_date, statement_adj, volume, statement_comm, open_rate, 
    --          gross_pl, rollover, comm
    closed_trade = {}

    closed_trade.ticket_id = ctrade.ticket_id
    closed_trade.open_date = ctrade.open_date
    closed_trade.open_day, closed_trade.open_time = timeutils.breakdate(ctrade.open_date)
    closed_trade.open_rate = tonumber(ctrade.open_rate)
    closed_trade.close_date = ctrade.close_date
    closed_trade.close_day, closed_trade.close_time = timeutils.breakdate(ctrade.close_date)
    closed_trade.close_rate = tonumber(ctrade.close_rate)
    closed_trade.net_pl = ctrade.net_pl
    closed_trade.gross_pl = ctrade.gross_pl
    closed_trade.quantity   = ctrade.quantity
    closed_trade.volume   = ctrade.volume
    closed_trade.symbol = ctrade.symbol
    
    return closed_trade
end	