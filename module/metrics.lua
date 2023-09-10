-- Copyright 2021 Snap One, LLC. All rights reserved.

COMMON_METRICS_VER = 7

local Metrics = {
}

DEBUG_METRICS = DEBUG_METRICS or false

function Metrics:new (group, version, identifier)

	if (group == nil) then
		group = tostring (C4:GetDriverConfigInfo ('name'))
		version = tostring (C4:GetDriverConfigInfo ('version'))

	elseif (type (group) == 'string') then
		if (type (version) == 'number') then
			version = tostring (version)
		end
		if (type (version) ~= 'string') then
			error ('Metrics:new - version is required when specifying a metric group', 2)
		end

	else
		error ('Metrics:new - group must be a string or nil', 2)
		return
	end

	if (type (identifier) ~= 'string') then
		identifier = ''
	end

	local driverName = C4:GetDriverConfigInfo ('name')
	local driverId = tostring (C4:GetDeviceID ())

	group = self:GetSafeString (group)
	version = self:GetSafeString (version)
	identifier = self:GetSafeString (identifier, true)
	driverName = self:GetSafeString (driverName)
	driverId = self:GetSafeString (driverId)

	local namespace = {
		'drivers',
		group,
		version,
		identifier,
		driverName,
		driverId,
	}

	if (not (IN_PRODUCTION)) then
		table.insert (namespace, 1, 'sandbox')
	end

	namespace = table.concat (namespace, '.')

	if (Metrics.NameSpaces and Metrics.NameSpaces [namespace]) then
		local metric = Metrics.NameSpaces [namespace]
		return metric
	end

	local metric = {
		namespace = namespace,
	}

	setmetatable (metric, self)
	self.__index = self

	Metrics.NameSpaces = Metrics.NameSpaces or {}
	Metrics.NameSpaces [namespace] = metric

	return metric
end

function Metrics:SetCounter (key, value, sampleRate)
	if (not C4.StatsdCounter) then
		return
	end

	if (type (key) ~= 'string') then
		error ('Metrics:SetCounter - key must be a string', 2)
	end

	if (value == nil) then
		value = 1
	end

	if (type (value) ~= 'number') then
		error ('Metrics:SetCounter - Cannot set counter ' .. tostring (key) ..  ' to non-number value', 2)
	end

	key = self:GetSafeString (key)

	C4:StatsdCounter (self.namespace, key, value, (sampleRate or 0))
	if (DEBUG_METRICS) then
		print ('Metrics:SetCounter:', self.namespace, key, tostring (value))
	end
end

function Metrics:SetGauge (key, value)
	if (not C4.StatsdGauge) then
		return
	end

	if (type (key) ~= 'string') then
		error ('Metrics:SetGauge - Metric key must be a string', 2)
	end

	if (type (value) ~= 'number') then
		error ('Metrics:SetGauge - Cannot set stats gauge ' .. tostring (key) ..  ' to non-number value', 2)
	end

	key = self:GetSafeString (key)

	C4:StatsdGauge (self.namespace, key, value)
	if (DEBUG_METRICS) then
		print ('Metrics:SetGauge:', self.namespace, key, tostring (value))
	end
end

function Metrics:AdjustGauge (key, value)
	if (not C4.StatsdAdjustGauge) then
		return
	end

	if (type (key) ~= 'string') then
		error ('Metrics:AdjustGauge - Metric key must be a string', 2)
	end

	if (type (value) ~= 'number') then
		error ('Metrics:AdjustGauge - Trying to adjust stats gauge ' .. tostring (key) ..  ' by non-number value', 2)
	end

	key = self:GetSafeString (key)

	C4:StatsdAdjustGauge (self.namespace, key, value)
	if (DEBUG_METRICS) then
		print ('Metrics:AdjustGauge:', self.namespace, key, tostring (value))
	end
end

function Metrics:SetTimer (key, value)
	if (not C4.StatsdTimer) then
		return
	end

	if (type (key) ~= 'string') then
		error ('Metrics:SetTimer - Metric key must be a string', 2)
	end

	if (type (value) ~= 'number') then
		error ('Metrics:SetTimer - Cannot set stats timer ' .. tostring (key) ..  ' to non-number value', 2)
	end

	key = self:GetSafeString (key)

	C4:StatsdTimer (self.namespace, key, value)
	if (DEBUG_METRICS) then
		print ('Metrics:SetTimer:', self.namespace, key, tostring (value))
	end
end

function Metrics:SetString (key, value)
	if (not C4.StatsdString) then
		return
	end

	if (type (key) ~= 'string') then
		error ('Metrics:SetString - Metric key must be a string', 2)
	end

	if (type (value) ~= 'string') then
		error ('Metrics:SetString - Cannot set stats string ' .. tostring (key) ..  ' to non-string value', 2)
	end

	key = self:GetSafeString (key)

	value = string.gsub (value, '[\r\n]+', '    ')

	C4:StatsdString (self.namespace, key, value)
	if (DEBUG_METRICS) then
		print ('Metrics:SetString:', self.namespace, key, tostring (value))
	end
end

function Metrics:SetJSON (key, value)
	if (not C4.StatsdJSONObject) then
		return
	end

	if (type (key) ~= 'string') then
		error ('Metrics:SetJSON - Metric key must be a string', 2)
	end

	if (type (value) ~= 'string') then
		error ('Metrics:SetJSON - Cannot set stats JSONObject ' .. tostring (key) ..  ' to non-string value', 2)
	end

	key = self:GetSafeString (key)

	value = string.gsub (value, '[\r\n]+', '    ')

	C4:StatsdJSONObject (self.namespace, key, value)
	if (DEBUG_METRICS) then
		print ('Metrics:SetJSON:', self.namespace, key, tostring (value))
	end
end

function Metrics:SetIncrementingMeter (key, value)
	if (not C4.StatsdIncrementMeter) then
		return
	end

	if (type (key) ~= 'string') then
		error ('Metrics:SetIncrementingMeter - Metric key must be a string', 2)
	end

	if (type (value) ~= 'number') then
		error ('Metrics:SetIncrementingMeter - Cannot set incremeting meter ' .. tostring (key) ..  ' to non-number value', 2)
		return
	end

	key = self:GetSafeString (key)

	C4:StatsdIncrementMeter (self.namespace, key, value)
	if (DEBUG_METRICS) then
		print ('Metrics:SetIncrementMeter:', self.namespace, key, tostring (value))
	end
end

function Metrics:GetSafeString (s, ignoreUselessStrings)
	if (s == nil) then
		return
	end

	s = tostring (s)
	local p = '[^%w%-%_]+'
	local safe = string.gsub (s, p, '_')

	if (ignoreUselessStrings ~= true and string.gsub (safe, '_', '') == '') then
		error ('Metrics:GetSafeString - generated a non-useful string', 3)
	end

	return safe
end

return Metrics