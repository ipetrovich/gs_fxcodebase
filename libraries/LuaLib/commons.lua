function rows(tablename)
	function table_iter(enum) return enum:next() end
    local enum = core.host:findTable(tablename):enumerator();
	return table_iter, enum
end

function string:split(sep)
 local sep, fields = sep or ";", {}
 local pattern = string.format("([^%s]+)", sep)
 self:gsub(pattern, function(c) fields[#fields + 1] = c end)
 return fields
end

timeutils = {
	breakdate = function (datetime)
	    local dt = math.floor(datetime)
	    local tm = datetime - dt
	    return dt, tm
	end
}
