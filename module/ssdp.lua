-- Copyright 2020 Control4 Corporation. All rights reserved.

COMMON_SSDP_VER = 8

require ('global.lib')
require ('global.handlers')
require ('global.timer')
require ('global.url')

local SSDP = {}

function SSDP:new (searchTarget, options)
	searchTarget = searchTarget or 'upnp:rootdevice'

	if (SSDP.SearchTargets and SSDP.SearchTargets [searchTarget]) then
		local ssdp = SSDP.SearchTargets [searchTarget]
		return ssdp
	end

	options = options or {}

	local ssdp = {
		searchTarget = searchTarget,
		devices = {},
		locations = {},
		mcIP = '239.255.255.250',
		bcIP = '255.255.255.255',
		mcOnly = options.mcOnly,
		bcOnly = options.bcOnly,
		friendlyNameTag = options.friendlyNameTag or 'friendlyName'
	}

	setmetatable (ssdp, self)
	self.__index = self

	SSDP.SearchTargets = SSDP.SearchTargets or {}
	SSDP.SearchTargets [searchTarget] = ssdp

	ssdp:setupC4Connection ()

	return ssdp
end

function SSDP:delete ()
	self:disconnect ()

	if (SSDP.SearchTargets) then
		if (self.searchTarget) then
			SSDP.SearchTargets [self.searchTarget] = nil
		end

		if (self.mcBinding) then
			OCS [self.mcBinding] = nil
			RFN [self.mcBinding] = nil
			SSDP.SearchTargets [self.mcBinding] = nil
			C4:SetBindingAddress (self.mcBinding, '')
		end

		if (self.bcBinding) then
			OCS [self.bcBinding] = nil
			RFN [self.bcBinding] = nil
			SSDP.SearchTargets [self.bcBinding] = nil
			C4:SetBindingAddress (self.bcBinding, '')
		end
	end

	return nil
end

function SSDP:StartDiscovery (resetLocations)
	self:StopDiscovery (resetLocations)

	self:connect ()

	local _timer = function (timer)
		self:connect ()
	end

	self.repeatingDiscoveryTimer = SetTimer (self.repeatingDiscoveryTimer, 5 * ONE_MINUTE, _timer, true)
end

function SSDP:StopDiscovery (resetLocations)
	if (resetLocations) then
		for location, timer in pairs (self.locations or {}) do
			self.locations [location] = CancelTimer (timer)
		end
	end

	self.repeatingDiscoveryTimer = CancelTimer (self.repeatingDiscoveryTimer)

	self:disconnect ()
end

function SSDP:SetProcessXMLFunction (f)
	local _f = function (s, uuid, data, headers)
		local success, ret = pcall (f, s, uuid, data, headers)
	end
	self.ProcessXML = _f

	return self
end

function SSDP:SetUpdateDevicesFunction (f)
	local _f = function (s, devices)
		local success, ret = pcall (f, s, devices)
	end
	self.UpdateDevices = _f

	return self
end

function SSDP:setupC4Connection ()
	local i = 6999
	if (not self.bcOnly) then
		while (not self.mcBinding and i > 6900) do
			local checkAddress = C4:GetBindingAddress (i)
			if (checkAddress == nil or checkAddress == '') then
				self.mcBinding = i
			end
			i = i - 1
		end
	end
	if (not self.mcOnly) then
		while (not self.bcBinding and i > 6900) do
			local checkAddress = C4:GetBindingAddress (i)
			if (checkAddress == nil or checkAddress == '') then
				self.bcBinding = i
			end
			i = i - 1
		end
	end

	RFN = RFN or {}
	OCS = OCS or {}

	local parseResponse = function (idBinding, nPort, strData)
		self:parseResponse (strData)
	end

	local isOnline = function (idBinding, nPort, strStatus)
		if (idBinding == self.mcBinding) then
			self.mcConnected = (strStatus == 'ONLINE')
			if (self.mcConnected) then
				self:sendDiscoveryPacket (self.mcBinding)
			end

		elseif (idBinding == self.bcBinding) then
			self.bcConnected = (strStatus == 'ONLINE')
			if (self.bcConnected) then
				self:sendDiscoveryPacket (self.bcBinding)
			end
		end
	end

	if (self.bcBinding) then
		SSDP.SearchTargets = SSDP.SearchTargets or {}
		SSDP.SearchTargets [self.bcBinding] = self

		RFN [self.bcBinding] = parseResponse
		OCS [self.bcBinding] = isOnline

		C4:CreateNetworkConnection (self.bcBinding, self.bcIP)
	end

	if (self.mcBinding) then
		SSDP.SearchTargets = SSDP.SearchTargets or {}
		SSDP.SearchTargets [self.mcBinding] = self

		RFN [self.mcBinding] = parseResponse
		OCS [self.mcBinding] = isOnline

		C4:CreateNetworkConnection (self.mcBinding, self.mcIP)
	end

	return self
end

function SSDP:connect ()
	self:disconnect ()

	if (self.mcBinding) then
		C4:NetConnect (self.mcBinding, 1900, 'UDP')
	end
	if (self.bcBinding) then
		C4:NetConnect (self.bcBinding, 1900, 'UDP')
	end
end

function SSDP:disconnect ()
	if (self.mcBinding) then
		C4:NetDisconnect (self.mcBinding, 1900, 'UDP')
	end
	if (self.bcBinding) then
		C4:NetDisconnect (self.bcBinding, 1900, 'UDP')
	end
end

function SSDP:sendDiscoveryPacket (binding)

	local ip, online

	if (binding == self.mcBinding) then
		ip = self.mcIP
		online = self.mcConnected
	elseif (binding == self.bcBinding) then
		ip = self.bcIP
		online = self.bcConnected
	end

	if (ip and online) then

		local packet = {
			'M-SEARCH * HTTP/1.1',
			'HOST: ' .. ip .. ':1900',
			'MAN: "ssdp:discover"',
			'MX: 5',
			'ST: ' .. self.searchTarget,
			'',
		}

		packet = table.concat (packet, '\r\n')

		for i = 1, 3 do
			C4:SendToNetwork (binding, 1900, packet)
		end
	end
end

function SSDP:parseResponse (data)
	local headers = {}
	for line in string.gmatch (data, '(.-)\r\n') do
		local k, v = string.match (line, '%s*(.-)%s*[:/*]%s*(.+)')
		if (k and v) then
			k = string.upper (k)
			headers [k] = v
		end
	end

	if (self.searchTarget and not (headers.ST and headers.ST == self.searchTarget)) then return end

	local alive, byebye

	if (headers.HTTP and headers.HTTP == '1.1 200 OK') then
		alive = true

	elseif (headers.NOTIFY and headers.NTS and headers.NTS == 'ssdp:alive') then
		alive = true

	elseif (headers.NOTIFY and headers.NTS and headers.NTS == 'ssdp:byebye') then
		byebye = true
	end

	if (alive) then
		local interval
		if (headers ['CACHE-CONTROL']) then
			interval = string.match (headers ['CACHE-CONTROL'], 'max-age = (%d+)')
		end
		interval = tonumber (interval) or 1800

		if (headers.LOCATION and headers.USN) then
			local location = headers.LOCATION

			local secure, server = string.match (location, 'http(s?)://(.-)/.*')

			if (not secure and server) then
				return
			end

			local ip, port

			if (server) then
				ip, port = string.match (server, '(.-):(.+)')
			end
			if (not port) then
				ip = server
				port = (secure == '' and 80) or (secure == 's' and 443) or nil
			end

			local usnUUID = string.match (headers.USN, 'uuid:(.*)')

			if (usnUUID and usnUUID == self.CurrentDeviceUUID) then
				self.rediscoverCurrentDeviceTimer = CancelTimer (self.rediscoverCurrentDeviceTimer)
			end

			if (self.devices [usnUUID] and self.devices [usnUUID].udnUUID == self.CurrentDeviceUUID) then
				self.rediscoverCurrentDeviceTimer = CancelTimer (self.rediscoverCurrentDeviceTimer)
			end

			if (usnUUID) then
				self.devices [usnUUID] = self.devices [usnUUID] or {}

				for k, v in pairs (headers) do
					self.devices [usnUUID] [k] = v
				end

				self.devices [usnUUID].IP = ip
				self.devices [usnUUID].PORT = port

				if (not self.locations [location]) then
					local contextInfo = {
						usnUUID = usnUUID,
					}
					local _callback = function (strError, responseCode, tHeaders, data, context, url)
						self:parseXML (strError, responseCode, tHeaders, data, context, url)
					end
					urlGet (location, nil, _callback, contextInfo)
				end

				local _timer = function (timer)
					self.locations [location] = nil
					for uuid, device in pairs (self.devices or {}) do
						if (device.LOCATION == location) then
							self:deviceOffline (uuid)
						end
					end
				end
				self.locations [location] = SetTimer (self.locations [location], interval * ONE_SECOND * 1.005, _timer)

				self:updateDevices ()
			end
		end

	elseif (byebye) then
		if (headers.USN) then
			local usnUUID = string.match (headers.USN, 'uuid:(.+)')
			self:deviceOffline (usnUUID)
		end
	end
end

function SSDP:deviceOffline (uuid)

	local deviceGoOfflineNow = function (device)
		local location = device.LOCATION
		self.locations [location] = CancelTimer (self.locations [location])

		self.devices [device.usnUUID] = nil
		self.devices [device.udnUUID] = nil

		if (self.CurrentDeviceUUID == device.udnUUID or self.CurrentDeviceUUID == device.usnUUID) then
			local _timer = function (timer)
				self:connect ()
			end

			self.rediscoverCurrentDeviceTimer = SetTimer (self.rediscoverCurrentDeviceTimer, 10 * ONE_SECOND, _timer, true)
		end
	end

	for _, device in pairs (self.devices or {}) do
		if (device.usnUUID == uuid or device.udnUUID == uuid) then
			deviceGoOfflineNow (device)
		end
	end

	self:updateDevices ()
end

function SSDP:updateDevices ()
	local _timer = function (timer)
		if (self.UpdateDevices and type (self.UpdateDevices == 'function')) then
			pcall (self.UpdateDevices, self, CopyTable (self.devices))
		end
	end

	self.updateDevicesTimer = SetTimer (self.updateDevicesTimer, ONE_SECOND, _timer)
end

function SSDP:parseXML (strError, responseCode, tHeaders, data, context, url)
	if (strError) then
		print ('Error retrieving device XML: ' .. (context.usnUUID or 'Unknown USN UUID') .. ' : url: ' .. url)
		return
	end

	if (responseCode == 200) then
		local udnUUID = string.match (data, '<UDN>uuid:(.-)</UDN>')

		if (udnUUID ~= context.usnUUID) then
			self.devices [udnUUID] = self.devices [context.usnUUID]
			-- If your device does this,
			-- when parsing the devices presented in updateDevices callback,
			-- check if the uuid matches the device.udnUUID before processing
		end

		local device = self.devices [udnUUID]

		local friendlyName = XMLDecode (string.match (data, '<' .. self.friendlyNameTag .. '>(.-)</' .. self.friendlyNameTag .. '>'))

		for k,v in pairs (tHeaders) do
			if (string.upper (k) == 'APPLICATION-URL') then
				local dialServer = v
				if (string.sub (dialServer, -1, -1) ~= '/') then
					dialServer = dialServer .. '/'
				end
				device.DIALSERVER = dialServer
			end
		end

		device.udnUUID = udnUUID
		device.usnUUID = context.usnUUID

		device.friendlyName = friendlyName
		device.deviceXML = data

		if (self.ProcessXML and type (self.ProcessXML == 'function')) then
			pcall (self.ProcessXML, self, context.usnUUID, data, tHeaders)
		end
		self:updateDevices ()

	end
end

return SSDP